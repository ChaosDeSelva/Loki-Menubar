import Foundation
import Darwin

final class LocalProcessRunner: @unchecked Sendable {
    struct Output { let status: Int32; let stdout: String; let stderr: String }
    private let lock = NSLock()
    private var processID: pid_t?
    private var cancellation: String?

    func cancel(reason: String = "Reply stopped.") {
        lock.lock(); cancellation = reason
        let pid = processID
        if let pid { kill(-pid, SIGTERM) }
        lock.unlock()

    }

    func run(executable: URL, arguments: [String], input: String = "", directory: URL,
             environment: [String: String], timeout: TimeInterval = 120,
             onOutput: @escaping (Data) -> Void = { _ in }) throws -> Output {
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        let handles = [stdin.fileHandleForReading, stdin.fileHandleForWriting, stdout.fileHandleForReading,
                       stdout.fileHandleForWriting, stderr.fileHandleForReading, stderr.fileHandleForWriting]
        defer { handles.forEach { try? $0.close() } }
        // A client may exit before reading stdin; EPIPE must not terminate Loki.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, stdin.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        for handle in handles { posix_spawn_file_actions_addclose(&actions, handle.fileDescriptor) }
        if #available(macOS 26, *) { posix_spawn_file_actions_addchdir(&actions, directory.path) }
        else { posix_spawn_file_actions_addchdir_np(&actions, directory.path) }
        // A separate process group makes Stop and timeouts also terminate shell children holding our pipes.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let env = environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { argv.forEach { free($0) }; env.forEach { free($0) } }
        var pid: pid_t = 0
        lock.lock()
        if let cancellation { lock.unlock(); throw LauncherFailure(cancellation) }
        guard processID == nil else { lock.unlock(); throw LauncherFailure("A command is already running.") }
        let launchError = argv.withUnsafeBufferPointer { argv in env.withUnsafeBufferPointer { env in
            posix_spawn(&pid, executable.path, &actions, &attributes, argv.baseAddress!, env.baseAddress!)
        } }
        guard launchError == 0 else { lock.unlock(); throw NSError(domain: NSPOSIXErrorDomain, code: Int(launchError)) }
        processID = pid; lock.unlock()
        try? stdin.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
        var reaped = false
        defer {
            lock.lock()
            if !reaped { kill(-pid, SIGKILL); var status: Int32 = 0; while waitpid(pid, &status, 0) == -1 && errno == EINTR {} }
            if processID == pid { processID = nil }
            lock.unlock()
        }
        let inputData = Data(input.utf8)
        var inputOffset = 0, inputOpen = true, outputOpen = true, errorsOpen = true
        var output = Data(), errors = Data()
        let inputFD = stdin.fileHandleForWriting.fileDescriptor
        let outputFD = stdout.fileHandleForReading.fileDescriptor
        let errorsFD = stderr.fileHandleForReading.fileDescriptor
        for fd in [inputFD, outputFD, errorsFD] { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        let started = ProcessInfo.processInfo.systemUptime
        func checkCancellation() throws {
            lock.lock(); let reason = cancellation; lock.unlock()
            if let reason { throw LauncherFailure(reason) }
            if ProcessInfo.processInfo.systemUptime - started >= timeout {
                throw LauncherFailure("The command took too long. Please try again.")
            }
        }
        // Polling keeps cancellation bounded even if a detached descendant keeps a pipe open.
        while outputOpen || errorsOpen || inputOpen {
            try checkCancellation()
            if inputOpen && inputOffset == inputData.count { try? stdin.fileHandleForWriting.close(); inputOpen = false }
            var descriptors = [
                pollfd(fd: outputOpen ? outputFD : -1, events: Int16(POLLIN), revents: 0),
                pollfd(fd: errorsOpen ? errorsFD : -1, events: Int16(POLLIN), revents: 0),
                pollfd(fd: inputOpen ? inputFD : -1, events: Int16(POLLOUT), revents: 0)
            ]
            let count = poll(&descriptors, nfds_t(descriptors.count), 50)
            if count < 0 { if errno == EINTR { continue }; throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if inputOpen && descriptors[2].revents != 0 {
                let written = inputData.withUnsafeBytes { bytes in
                    Darwin.write(inputFD, bytes.baseAddress!.advanced(by: inputOffset), min(8192, inputData.count - inputOffset))
                }
                if written > 0 { inputOffset += written }
                else if written < 0 && errno != EAGAIN && errno != EINTR { try? stdin.fileHandleForWriting.close(); inputOpen = false }
            }
            for index in 0...1 where descriptors[index].fd >= 0 && descriptors[index].revents != 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let length = Darwin.read(descriptors[index].fd, &bytes, bytes.count)
                if length > 0 {
                    let data = Data(bytes.prefix(length))
                    if index == 0 {
                        guard output.count + data.count <= 2_000_000 else { throw LauncherFailure("The output was too large. Try a smaller request.") }
                        output.append(data); onOutput(data)
                    } else {
                        errors.append(data)
                        if errors.count > 32_768 { errors = errors.suffix(32_768) }
                    }
                } else if length == 0 {
                    if index == 0 { outputOpen = false } else { errorsOpen = false }
                } else if errno != EAGAIN && errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            }
        }
        var status: Int32 = 0
        while !reaped {
            try checkCancellation()
            lock.lock()
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { reaped = true; processID = nil }
            lock.unlock()
            if result == -1 && errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if !reaped { usleep(10_000) }
        }
        lock.lock(); let stopped = cancellation; lock.unlock()
        if let stopped { throw LauncherFailure(stopped) }
        let exitStatus = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return Output(status: exitStatus, stdout: String(decoding: output, as: UTF8.self), stderr: String(decoding: errors, as: UTF8.self))
    }
}

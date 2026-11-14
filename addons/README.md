# Reloadable Loki add-ons

Loki can load new commands, native forms, and local HTML interfaces without rebuilding or restarting the app. Enable **Loki Launch** in Add-ons, then choose **Install folder…**, or put a package in:

```text
~/Library/Application Support/Loki/Add-ons/<package-folder>/
```

Enable the installed package in Add-ons. Its commands appear in launcher search. **Add examples** installs Text Tools (native form) and Text Workbench (custom HTML interface), initially disabled. Their complete source is in [examples](examples).

Files are checked every three seconds; **Reload** checks immediately. Updating a package disables it until you review and enable its new contents. Disabling, removing, or changing a package stops its active command and invalidates its open interface. Changes affect only the add-on folder, so Loki’s app signature and Accessibility grant remain unchanged. Keep persistent data outside the package; changing files inside it triggers review.

## Package format

Every package contains `manifest.json` and its entrypoint files. IDs begin with a lowercase letter or number and use lowercase letters, numbers, periods, underscores, and hyphens (80 characters maximum).

```json
{
  "schemaVersion": 1,
  "id": "example.greeting",
  "name": "Greeting",
  "version": "1.0.0",
  "description": "A small local greeting tool.",
  "commands": [{
    "id": "greet",
    "title": "Make a Greeting",
    "type": "script",
    "runtime": "shell",
    "entrypoint": "greet.sh",
    "inputs": [{ "id": "name", "label": "Name", "type": "text", "required": true }]
  }]
}
```

Optional package fields: `author`, `icon` (SF Symbol name). Optional command fields: `subtitle`, `keywords` (string array), `icon`, `timeout` (1–120 seconds; default 30), and `inputs` (up to 20 fields). Command IDs must be unique within the package. `type` is required for both commands and fields.

Fields support `text`, `multiline`, `choice`, and `toggle`. Optional field properties are `placeholder`, `required`, and `value` (a string default). Choice fields require a unique `options` string array; their default must match an option, or the first option is selected. Toggles use the strings `"true"` and `"false"`. Input values are limited to 32,000 characters. Undeclared inputs are discarded. Required values are validated before execution.

Packages are limited to 50 commands, 500 regular files, 1,000 total files/folders, and 20 MB. Manifests are limited to 128 KB. Entrypoints must be relative paths inside the package. Symbolic links and special files are rejected. Duplicate package IDs are all disabled until the conflict is resolved. Loki loads at most 100 package folders.

## Script commands

Supported runtimes:

| Runtime | Execution |
| --- | --- |
| `shell` | `/bin/zsh -f <entrypoint>` |
| `python` | `/usr/bin/python3 <entrypoint>`; requires Python at that path |
| `node` | Node in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`; install separately |
| `executable` | Executes the package entrypoint directly; it must have execute permission |

The working directory is the package folder. Loki passes one JSON request through standard input; it never interpolates input into shell commands:

```json
{
  "apiVersion": 1,
  "command": "greet",
  "inputs": { "name": "Jacob" },
  "context": {
    "addonID": "example.greeting",
    "packageDirectory": "/path/to/package",
    "dataDirectory": "/path/to/Loki/Add-on Data/example.greeting"
  }
}
```

`LOKI_ADDON_DATA_DIR` also contains the persistent data-directory path. Use it for saved data. The environment includes a predictable PATH and basic account/locale settings; ambient API tokens and custom AI configuration paths are not inherited. Do not assume shell startup files have run.

Write plain text to stdout, or one JSON object:

```json
{"title":"Greeting","text":"Hello, Jacob!","copyText":"Hello, Jacob!"}
```

`text` is required; `title` and `copyText` are optional. Plain output preserves whitespace. Exit with zero on success. A nonzero status displays stderr (bounded to a recent tail). Output is capped at 2 MB. Stop, disabling the package, and timeouts terminate its process group; a deliberately detached process can outlive that group, but cannot keep Loki waiting indefinitely.

Minimal `greet.sh`:

```sh
set -euo pipefail
request=$(cat)
name=$(printf '%s' "$request" | /usr/bin/plutil -extract inputs.name raw -n -o - -)
printf 'Hello, %s!' "$name"
```

## Custom interfaces

Add a command with `"type": "view"` and an HTML `entrypoint`. Bundle CSS, JavaScript, and assets locally. Loki displays the page in a nonpersistent WebKit view, restricts navigation to the package, and installs rules blocking remote web resources. External links do not open from this interface. Declare native work as separate script commands in the same manifest:

```js
try {
  const result = await window.loki.run('greet', {name: 'Jacob'});
  document.querySelector('#result').textContent = result.text;
} catch (error) {
  document.querySelector('#error').textContent = error.message;
}
```

`window.loki.apiVersion` is `1`. Input values must be strings. Only declared script commands from that enabled package can run; one request runs at a time. Errors reject the promise. There is no arbitrary shell, filesystem, clipboard, or chat-token API exposed to JavaScript. Leaving a custom interface cancels its active command. Use native script commands for network operations and bundle all interface dependencies rather than loading a CDN.

## Trust and host compatibility

Enable only source you trust. Native add-on scripts execute as your macOS account and can read files or use the network. Package validation, environment filtering, timeouts, and UI navigation restrictions are not a sandbox for native scripts. The host never executes a package merely because it was discovered or installed.

The version-1 API supports new commands, forms, scripts, and custom interfaces without a host build. Adding new native host capabilities or changing the bridge API still requires a Loki update. There is no marketplace, automatic dependency installer, background trigger API, or automatic code execution on startup.

For host development, run `bash scripts/test.sh`, then `bash scripts/test-addons-ui.sh` in an active macOS desktop session. The latter verifies actual HTML loading, bridge calls, result delivery, input errors, and navigation restrictions using a temporary package.

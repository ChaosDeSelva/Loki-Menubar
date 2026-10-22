# Publishing updates

Loki uses Sparkle 2.10.0. The release archive is pinned by checksum in scripts/prepare-sparkle.sh. The bundle contains the public update key; the private key remains in the publisher's login Keychain under the Loki-Menubar account. No private keys belong in this repository.

1. Increment CFBundleVersion in scripts/build.sh for every published build. Update the package version and release links.
2. Build with a Developer ID identity. The script signs nested Sparkle components before the host app. Ad-hoc source builds omit hardened runtime so local framework loading works; distributed builds require hardened runtime.
3. Submit the app for Apple notarization and staple its ticket. Package it with scripts/package.sh, then notarize and staple the DMG.
4. Put only the finished DMG in a staging feed directory. Generate the signed appcast using build/vendor/Sparkle/bin/generate_appcast with --account Loki-Menubar, --maximum-deltas 0, and --download-url-prefix pointing to the exact GitHub release tag's download directory.
5. Verify the archive's Ed25519 signature and the signed appcast with sign_update --verify. Copy the generated appcast unchanged into docs/appcast.xml. Editing the signed XML invalidates its signature.
6. Upload release assets before deploying the appcast; verify the live URLs, feed signature, version, archive length, and digest.
7. Test a genuine older signed install upgrading to the new build, including download cancellation, installation, and relaunch. Signature checks alone do not replace this test.

Automatic checks are off by default. Users can enable them in Settings. The standard updater presents download/install controls and verifies signed archives before extraction. System profiling is disabled. Alpha 1 and 2 have no embedded updater and require one manual installation to reach an updater-enabled build.

Forks must use their own bundle identity, update key, and feed URL. Never point a fork's update feed at an unrelated application's releases.

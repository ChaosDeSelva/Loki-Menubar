# Deploying Loki with MDM

Loki reads managed preferences, the standard macOS mechanism for configuring apps
across a fleet. An organization delivers them in a configuration profile through its
device management (MDM) service. Loki applies a setting only when macOS reports it as
forced by an installed profile, so values a user writes with `defaults write` are
never treated as policy.

Loki reads the policy once at launch. After installing, changing, or removing a
profile, quit and reopen Loki (or log out and back in).

Removing a profile restores each user's own choices. Loki lays managed values over
the user's saved settings and never overwrites them.

## Preference domain

| Item | Value |
|---|---|
| Preference domain (payload type) | `io.github.ChaosDeSelva.Loki` |
| Bundle identifier | `io.github.ChaosDeSelva.Loki` |
| Managed preferences file (written by macOS) | `/Library/Managed Preferences/io.github.ChaosDeSelva.Loki.plist` |

## Keys

Every key is optional. A key with the wrong type is ignored and Loki falls back to
the user's setting, so a typo never stops Loki from launching.

| Key | Type | Effect |
|---|---|---|
| `HiddenItems` | Array of String | Menu-extra IDs to keep hidden, in every realm. Replaces each user's hidden list and locks the hidden-icons checklist. An empty array means nothing is hidden. Find IDs with `--list-items` (below). On macOS 27 hiding is per app: one ID hides every icon of the app that owns it, and IDs of Apple's own menu extras (`com.apple.` owners and system controls) are ignored. |
| `AutoRehide` | Boolean | Hide icons again after the pointer leaves the menu bar. Locks the toggle. |
| `RehideDelay` | Number | Seconds before icons hide again. Clamped to 1 through 30. Locks the slider. |
| `HoverReveal` | Boolean | Show hidden icons when the pointer touches the menu bar. Locks the toggle. |
| `DisableUpdates` | Boolean | `true` turns off the built-in updater completely: no checks, no update menu item, no update controls. Use this when you deploy new versions yourself. |
| `AutomaticUpdateChecks` | Boolean | Forces automatic update checks on or off and locks the toggle. Ignored when `DisableUpdates` is `true`. |
| `DisableHiding` | Boolean | `true` means Loki never moves or hides menu-bar icons, on any macOS version. The shelf, realms, and groups keep working. |
| `LaunchAtLogin` | Boolean | Informational. Locks the Launch at login toggle so users cannot change it. Deliver the login item itself with your MDM's managed login items (Service Management) payload. |

Locked controls appear dimmed in Loki with the caption "Managed by your organization".

These keys apply to both hiding mechanisms. On macOS 14 to 26, Loki hides icons
per icon behind a divider status item, using public interfaces and Accessibility.
On macOS 27, where no public interface can hide icons, Loki uses Apple's
undocumented MenuBarClientCore allowlist, which hides whole apps; it is resolved at
runtime and turns itself off if missing or changed. Neither mechanism is saved, so
quitting Loki shows every icon. Run `Loki --status` while Loki is open and read
`backend` (`divider`, `allowlist`, or `unavailable`) to see which one a Mac uses.

## Example profile

Most MDM services accept a custom settings payload for an app's preference domain:
a payload whose `PayloadType` is the domain, with the keys placed directly inside it.
Upload the property list below as a custom configuration profile, or paste just the
keys into your MDM's custom settings form for the domain `io.github.ChaosDeSelva.Loki`.
Replace the UUIDs and identifiers with your own (`uuidgen` prints a new UUID).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadIdentifier</key>
    <string>com.example.loki</string>
    <key>PayloadUUID</key>
    <string>F4EC0BF2-0BF6-4F1C-A50B-EDB1D399B8D8</string>
    <key>PayloadDisplayName</key>
    <string>Loki settings</string>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>io.github.ChaosDeSelva.Loki</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>com.example.loki.settings</string>
            <key>PayloadUUID</key>
            <string>45BAF293-0F25-4A7B-8116-19B6AFEAB277</string>
            <key>PayloadDisplayName</key>
            <string>Loki</string>

            <key>HiddenItems</key>
            <array>
                <string>menu-slot:com.apple.weather.menu:0</string>
            </array>
            <key>AutoRehide</key>
            <true/>
            <key>RehideDelay</key>
            <integer>5</integer>
            <key>HoverReveal</key>
            <false/>
            <key>DisableUpdates</key>
            <true/>
            <key>DisableHiding</key>
            <false/>
            <key>LaunchAtLogin</key>
            <true/>
        </dict>
    </array>
</dict>
</plist>
```

If your MDM only offers the older managed preferences form, the same keys go under
`PayloadType` `com.apple.ManagedClient.preferences`, nested as
`PayloadContent` > `io.github.ChaosDeSelva.Loki` > `Forced` > (array of one dict) >
`mcx_preference_settings` > the keys above. macOS writes both forms to the same
managed preferences file, and Loki reads them the same way.

### Checking a deployment

On a managed Mac, run:

```sh
/Applications/Loki.app/Contents/MacOS/Loki --diagnose
```

`managedKeys` lists the keys Loki is enforcing. (`hidingBackend` names the mechanism in use, and `privateFrameworks` is `true` when it is the macOS 27 allowlist.) `ignoredManagedKeys` lists keys the
profile supplied with the wrong type, which Loki ignored. Both are empty on an
unmanaged Mac.

## Finding menu-extra IDs

`HiddenItems` takes the IDs Loki uses for menu-bar icons. List them on a Mac set up
like your fleet:

```sh
/Applications/Loki.app/Contents/MacOS/Loki --list-items
```

This prints a JSON array with one object per menu-bar icon:

```json
[
  {
    "hideable" : true,
    "id" : "menu-slot:com.apple.weather.menu:0",
    "owner" : "WeatherMenu",
    "title" : "Weather"
  }
]
```

Copy the `id` values you want hidden into `HiddenItems`. Icons with `"hideable" :
false` (for example Clock and Control Center) are pinned by macOS and stay where they
are. `hideable` reflects the macOS 14 to 26 divider; on macOS 27 an Apple-owned ID
listed as hideable (such as the Weather example) is still ignored, and any
third-party ID hides its whole app. Loki needs Accessibility to read the menu bar. When you run the command from a
terminal, macOS checks the terminal's Accessibility permission, so allow the terminal
in System Settings > Privacy & Security > Accessibility first, or the command exits
with an error. IDs are stable across launches and Macs for the same app, but an app
that renames its menu extra in an update may change its ID; recheck after major app
updates.

## Pre-approving Accessibility (PPPC)

Loki reads the menu bar through Accessibility, and on macOS 14 to 26 also moves icons
with it. (On macOS 27, hiding itself does not need Accessibility, but the checklist
and `--list-items` do.) Instead of asking each
user to approve it, an organization can pre-approve it with a Privacy Preferences
Policy Control payload (`com.apple.TCC.configuration-profile-policy`).

Requirements:

- The profile must be installed by an MDM service, on a Mac enrolled through
  Automated Device Enrollment or with user-approved MDM. macOS ignores PPPC payloads
  in profiles a user installs by hand.
- Loki must carry a stable Developer ID signature. The code requirement below pins
  the signing identity; an ad hoc or locally signed build has a requirement based on
  its cdhash, which changes with every build, and would stop matching.

Get the code requirement from the installed app:

```sh
codesign -dr - /Applications/Loki.app
```

Use the text after `designated =>` as the `CodeRequirement` value. A Developer ID
signed build prints something of the form
`identifier "io.github.ChaosDeSelva.Loki" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "TEAMID"`.

Example payload (add it to the profile's `PayloadContent` array, or deploy it as its
own profile):

```xml
<dict>
    <key>PayloadType</key>
    <string>com.apple.TCC.configuration-profile-policy</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadIdentifier</key>
    <string>com.example.loki.pppc</string>
    <key>PayloadUUID</key>
    <string>CFC88552-74D6-4D0E-AFCC-03C941EA3AF5</string>
    <key>PayloadDisplayName</key>
    <string>Loki Accessibility</string>
    <key>Services</key>
    <dict>
        <key>Accessibility</key>
        <array>
            <dict>
                <key>Identifier</key>
                <string>io.github.ChaosDeSelva.Loki</string>
                <key>IdentifierType</key>
                <string>bundleID</string>
                <key>CodeRequirement</key>
                <string>PASTE THE designated REQUIREMENT HERE</string>
                <key>StaticCode</key>
                <false/>
                <key>Authorization</key>
                <string>Allow</string>
                <key>Comment</key>
                <string>Lets Loki list and arrange menu-bar icons.</string>
            </dict>
        </array>
    </dict>
</dict>
```

Loki never uses Screen Recording, so no other privacy service needs approval. If you
set `DisableHiding` and only want the shelf of running apps, Accessibility is optional.

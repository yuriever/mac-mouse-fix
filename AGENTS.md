# Repository Guide

Owner's fork of Mac Mouse Fix 3.1.0. It adds an application scope to button rules and builds without Xcode.

## Branch

* `codex/mmf-app-scope`: the working branch, installed on Owner's Mac.
* `master`: upstream history.

## Change

* Scope UI: right-click a row in the Buttons tab; `App/UI/Main/Tabs/ButtonTab/RemapTable/RuleScopeMenu.swift`.
* Scope matching in the helper: `Helper/Core/Buttons/ApplicationButtonRules.swift`. Rules store the scope as `applicationScope` in the live `config.plist`.

## Build

The Command Line Tools compile the app and helper; nib, asset, and string resources come from the official 3.1.0 build, so keep source edits off storyboards and XIBs.

``` shell
uv run script/build-local.py --identity <fingerprint> --upstream <official-zip>
```

* `<fingerprint>`: the "MMF Local Development" identity from `security find-identity -p codesigning`. A stable identity keeps the Accessibility grant across rebuilds.
* `<official-zip>`: the official 3.1.0 (24898) app, backed up at `$HOME/Library/Application Support/MMF Local Build/official-3.1.0-24898.zip`; on a new Mac, take it from the upstream release.
* Output: `build/MacMouseFix-local.zip`.

To install, quit Mac Mouse Fix, replace `/Applications/Mac Mouse Fix.app` with the built app, then open it and enable it. Keep `checkForUpdates` off so the official update does not replace the build.

Run the scope tests:

``` shell
xcrun swiftc Helper/Core/Buttons/ApplicationButtonRules.swift Tests/ApplicationButtonRules/main.swift -o build/scope-tests && build/scope-tests
```

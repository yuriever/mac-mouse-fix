# Application button rules

This fork adds an optional `button-rules.json` alongside Mac Mouse Fix 3.1.0's `config.plist` in `~/Library/Application Support/com.nuebling.mac-mouse-fix/`. Create the file in that application support directory and restart the custom helper. The official 3.1.0 app does not read this file.

The helper loads the rules at runtime. Editing them requires no rebuild.

* `defaults` maps button numbers (3–32) to actions. Each listed button replaces existing click and modifier bindings that use that button. Other buttons retain their normal Mac Mouse Fix settings.
* `applications` uses foreground application bundle identifiers. Omit a button to inherit its default. Set it to `"passThrough"` for native input or specify a replacement action.
* Actions supported here are `"missionControl"`, `"threeFingerDrag"`, `"passThrough"`, and an object with a macOS virtual `keyCode` and optional numeric modifier `flags`.
* A held button or chord keeps its profile until release. Profile changes run on application activation and on button input. Pointer motion does not query the foreground app.

## Build

Use Xcode with the macOS 26 SDK. Initialize submodules, then build the application and its embedded helper:

```sh
git submodule update --init --recursive
xcodebuild -project 'Mouse Fix.xcodeproj' -scheme 'App - Release' -configuration Release -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

The development build is ad-hoc signed. It uses the upstream bundle IDs and requires its own usable Accessibility authorization. Test it instead of the official helper; running both gives ambiguous results. Keep the official app available for rollback. Install or switch helpers outside an active game session. The fork retains the upstream license and trial handling.

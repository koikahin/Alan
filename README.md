# Alan

Draws a transparent, click-through border around the window receiving keyboard
focus. Forked from [tylerhall/Alan](https://github.com/tylerhall/Alan).

This fork keeps the original border UI and preferences. It replaces the 100 ms
poller with Accessibility observers and macOS application, display, and Space
notifications. It uses public AppKit and Accessibility APIs, with no external
dependencies or private WindowServer calls.

## Tracking behavior

- Reads the app's focused window, with a containing-window fallback for apps
  that only expose a focused control. A control itself is never used as a
  fallback window.
- Uses documented `AXPosition` and `AXSize` attributes instead of `AXFrame`.
- Anchors coordinate conversion to the menu-bar display, including when other
  displays extend above it or have negative coordinates.
- Rebinds the window observer when focus changes and releases old observers.
- Updates on window movement/resizing notifications. Smooth tracking during
  dragging is deliberately out of scope; depending on the app, the border can
  remain at its previous position until the operation finishes.
- Hides the previous border on app/Space changes, missing focus, query errors,
  screen sleep, or session deactivation. The overlay cannot become the key or
  main window and never accepts mouse clicks.
- Uses a 250 ms Accessibility messaging timeout and at most three delayed
  retries after a transient failure. There is no repeating timer or idle polling.

Accessibility implementations vary between apps. An app that supports none of
the focus-change notifications will not be highlighted. Unsupported notifications
and unexpected failures are logged rather than silently enabling polling.
Inspect them in Console under subsystem `studio.retina.Alan`, or use:

```sh
log stream --predicate 'subsystem == "studio.retina.Alan"' --level info
```

## Build and run

Requires macOS 15.7 or later and Xcode 26 or later to build the complete app.
Open `Alan.xcodeproj`, select the Alan scheme, and build/run. Set your own signing
team if using automatic signing. Alternatively, build without a signing identity:

```sh
xcodebuild -project Alan.xcodeproj -scheme Alan -configuration Release \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The app is in `.build/DerivedData/Build/Products/Release/Alan.app`. Launch it,
grant Alan Accessibility permission in System Settings, and relaunch it. Configure
border width, inset, and light/dark colors in Alan's preferences.

GitHub Actions runs the tests and builds a universal app including XIB resources.
Download the `Alan-macOS` artifact from a successful run. This development build
is ad-hoc signed, not notarized. Forks may need Actions enabled before the first
workflow can run.

## Validation

With Xcode or the standalone Swift Command Line Tools installed:

```sh
bash scripts/test.sh
```

This runs geometry and Accessibility-decoding regression tests without requesting
Accessibility permission, then compiles and links all app sources. Compiling XIBs
requires full Xcode and is checked separately in CI.

Before relying on the app, check these behaviors with Accessibility enabled:

1. Switch between two windows of the same app and apps on different displays.
2. Open and dismiss dialogs, then minimize/close the focused window.
3. Move and resize windows; check the border after releasing the mouse.
4. Use displays above, below, and beside the primary display. Reconnect a display.
5. Switch Spaces, enter/exit full screen, and sleep/wake the displays.
6. Confirm typing and clicking still reach the intended app, and border preferences
   and appearance changes update immediately.

The automated tests do not substitute for these live WindowServer/Accessibility
checks. Upstream's MIT license and attribution are retained.

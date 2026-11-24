# hbak fork of AeroSpace

Upstream AeroSpace releases plus a few local fixes, on branch `hbak/patches`
(based on the upstream release tag it was last rebased onto).

| Fix | Files |
|---|---|
| No focus bounce on workspace switch: ignore a native-focus report for a window on a hidden workspace for 300 ms after AeroSpace focuses a window itself. Chromium/Electron apps (Helium, Notion, Linear, Spotify) post a focused-window notification when hidden, and macOS still reports them frontmost for a moment, so AeroSpace followed them back to the workspace just left. | `Sources/AppBundle/focusCache.swift`, `Sources/AppBundle/tree/MacApp.swift` |

## Build and install

    ./hbak-build.sh --install     # app + CLI, replaces the Homebrew copy, restarts AeroSpace

Needs Xcode (its Swift builds both; `swiftly` with the `.swift-version`
toolchain is used if installed) and the self-signed
`aerospace-codesign-certificate` in the login keychain. Keep the same
certificate: macOS ties AeroSpace's Accessibility permission to it.

## New upstream release

    ./hbak-sync-upstream.sh       # rebase onto the newest v* tag, build, install, push

The Homebrew cask is uninstalled (and commented out of the dotfiles
Brewfile): reinstalling or upgrading it would replace this build.

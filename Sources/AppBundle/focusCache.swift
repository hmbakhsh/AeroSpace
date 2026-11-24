@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// When AeroSpace itself last asked macOS to focus a window (`MacApp.nativeFocus`).
@MainActor var lastAeroSpaceNativeFocusRequest: ContinuousClock.Instant? = nil

/// For this long after AeroSpace focuses a window, macOS may still report the app being left as frontmost.
/// See `updateFocusCache`.
private let nativeFocusSettleDuration: Duration = .milliseconds(300)
@MainActor private var settleRefreshTask: Task<(), any Error>? = nil

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        // Right after AeroSpace focuses a window (e.g. on a workspace switch), macOS can still report the app
        // being left as frontmost: Chromium and Electron apps post a focused-window notification when their
        // window is hidden in the corner, and the refresh it triggers reads `frontmostApplication` before the
        // activation of the new app has landed. Following that report bounced focus back to the workspace just
        // left for a frame or two. A window on an invisible workspace can't be what the user just picked, so
        // ignore it until macOS has settled, then look again.
        if let nativeFocused,
           let requested = lastAeroSpaceNativeFocusRequest,
           ContinuousClock.now - requested < nativeFocusSettleDuration,
           nativeFocused.nodeWorkspace?.isVisible == false
        {
            scheduleSettleRefresh(after: nativeFocusSettleDuration - (ContinuousClock.now - requested))
            return
        }
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}

/// Re-reads the native focus once the settle period is over, so a real focus change that arrived during it
/// (e.g. Cmd-Tab to an app on another workspace) is still followed.
@MainActor private func scheduleSettleRefresh(after delay: Duration) {
    settleRefreshTask?.cancel()
    settleRefreshTask = Task.startUnstructured { @MainActor in
        try await Task.sleep(for: delay + .milliseconds(10))
        scheduleCancellableCompleteRefreshSession(.ax("nativeFocusSettled"))
    }
}

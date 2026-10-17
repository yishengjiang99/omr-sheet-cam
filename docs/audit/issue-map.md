# Issue map (step ID | issue | severity | title | url)
P1.4 | #20 | P1 | [P1.4] A free scan is charged before recognition runs, so failed/cancelled/reader-not-ready scans burn 1 of 5 | https://github.com/yishengjiang99/omr-sheet-cam/issues/20
P3.7 | #21 | P1 | [P3.7] Photo that hit the paywall is discarded after purchase; user must re-shoot | https://github.com/yishengjiang99/omr-sheet-cam/issues/21
P6.1 | #22 | P1 | [P6.1] Restore purchases is only reachable from the paywall (no Settings entry) | https://github.com/yishengjiang99/omr-sheet-cam/issues/22
P7.4 | #23 | P1 | [P7.4] Pro stays unlocked after subscription expires until the app is relaunched | https://github.com/yishengjiang99/omr-sheet-cam/issues/23
F2.7 | #24 | P1 | [F2.7] Deleting a scan leaves its captured photo (Documents/captures/*.jpg) on disk, contradicting the privacy policy | https://github.com/yishengjiang99/omr-sheet-cam/issues/24
P1.10 | #25 | P2 | [P1.10] No remaining-scans counter, no Pro status/confirmation, and no way to open the paywall voluntarily | https://github.com/yishengjiang99/omr-sheet-cam/issues/25
P11.1 | #26 | P2 | [P11.1] App Review notes say to repeat "Try sample picture" on Library home, but the button disappears after the first scan | https://github.com/yishengjiang99/omr-sheet-cam/issues/26
P2.5 | #27 | P2 | [P2.5] Paywall product-load failure shows two messages, no Retry, and an error flashes before loading starts | https://github.com/yishengjiang99/omr-sheet-cam/issues/27
P5.1 | #28 | P2 | [P5.1] Ask-to-Buy "pending" is shown as a red error and later approval does not update the open paywall | https://github.com/yishengjiang99/omr-sheet-cam/issues/28
P7.6 | #30 | P2 | [P7.6] Refunding one subscription locks Pro even when another entitlement is still valid | https://github.com/yishengjiang99/omr-sheet-cam/issues/30
F10.10 | #31 | P2 | [F10.10] Playback stops when the app is backgrounded or the screen locks (no UIBackgroundModes audio, no Now Playing/remote commands) | https://github.com/yishengjiang99/omr-sheet-cam/issues/31
F2.9 | #32 | P2 | [F2.9] Unreadable index.json silently empties the Library and the next save overwrites it for good | https://github.com/yishengjiang99/omr-sheet-cam/issues/32
F5.5 | #33 | P2 | [F5.5] "Retake" on Result/failure screens returns to Library instead of the Camera | https://github.com/yishengjiang99/omr-sheet-cam/issues/33
F6.8 | #34 | P2 | [F6.8] Cancel on the Reading screen does not cancel the parse; zombie parse blocks the next scan and may add a Library entry later | https://github.com/yishengjiang99/omr-sheet-cam/issues/34
P1.12 | #35 | P3 | [P1.12] Two StoreKitManager instances (ScanQuota + RootFlowView) run duplicate listeners and entitlement refreshes | https://github.com/yishengjiang99/omr-sheet-cam/issues/35
P10.2 | #37 | P3 | [P10.2] Purchase funnel has no cancel/restore/dismiss/expiry events, and pending is logged as a failure | https://github.com/yishengjiang99/omr-sheet-cam/issues/37
P4.2 | #38 | P3 | [P4.2] Purchase errors show raw localizedDescription; unverified transactions are indistinguishable from other failures | https://github.com/yishengjiang99/omr-sheet-cam/issues/38
F10.3 | #39 | P3 | [F10.3] Raw Swift error descriptions are shown to users (player load, save, delete, playlist) | https://github.com/yishengjiang99/omr-sheet-cam/issues/39
F11.2 | #40 | P3 | [F11.2] Deleting the currently playing scan leaves playback/mini-player running on a deleted entry | https://github.com/yishengjiang99/omr-sheet-cam/issues/40
F4.7 | #41 | P3 | [F4.7] Library "Try sample picture" failure is silent (log only) while Camera shows an error | https://github.com/yishengjiang99/omr-sheet-cam/issues/41
F7.7 | #42 | P3 | [F7.7] Share MIDI from Result uses the capture timestamp as file name, unlike Library/Player which use the title | https://github.com/yishengjiang99/omr-sheet-cam/issues/42
F8.7 | #43 | P3 | [F8.7] "Save feedback" / "Feedback saved" implies the report was submitted, but it is only written to the local diagnostics log | https://github.com/yishengjiang99/omr-sheet-cam/issues/43
P1.6 | #44 | ENH | [P1.6] Enhancement: "N scans left today" nudge near the quota limit (Library + Camera) with a soft path to Pro | https://github.com/yishengjiang99/omr-sheet-cam/issues/44
P2.1 | #45 | ENH | [P2.1] Enhancement: shared upgrade-prompt policy (reasons, frequency cap, Pro suppression) before adding any new upsell surface | https://github.com/yishengjiang99/omr-sheet-cam/issues/45
P2.2 | #46 | ENH | [P2.2] Enhancement: soft, dismissible upgrade card on the Result screen after a successful scan | https://github.com/yishengjiang99/omr-sheet-cam/issues/46
P2.9 | #47 | ENH | [P2.9] Enhancement: gentle, capped upgrade reminder when a free user returns to the app | https://github.com/yishengjiang99/omr-sheet-cam/issues/47
P9.4 | #49 | ENH | [P9.4] Enhancement: Pro status / upgrade row in Settings and a quiet entry point in Library | https://github.com/yishengjiang99/omr-sheet-cam/issues/49
P11.3 | #50 | P2 | [P11.3] OMRSheetCam.storekit is not attached to the Run scheme or project, so Xcode runs cannot load products | https://github.com/yishengjiang99/omr-sheet-cam/issues/50
P6.3 | #29 | P2 | [P6.3] Restore purchases gives no progress, success, "nothing to restore" or cancel-safe feedback | https://github.com/yishengjiang99/omr-sheet-cam/issues/29
P1.8 | #36 | P3 | [P1.8] Daily quota date string uses the device calendar/locale (no en_US_POSIX), so changing region/calendar can spuriously reset the quota | https://github.com/yishengjiang99/omr-sheet-cam/issues/36
F4.5 | #51 | P3 | [F4.5] iCloud-only photo fallback uses PHAsset without ever requesting Photos authorization | https://github.com/yishengjiang99/omr-sheet-cam/issues/51
P9.1 | #48 | ENH | [P9.1] Enhancement (product decision): contextual upgrade prompt on locked Pro features | https://github.com/yishengjiang99/omr-sheet-cam/issues/48
P10.3 | #52 | P3 | [P10.3] Analytics key filter regex matches "lat" in "platform" and silently drops it from event props | https://github.com/yishengjiang99/omr-sheet-cam/issues/52

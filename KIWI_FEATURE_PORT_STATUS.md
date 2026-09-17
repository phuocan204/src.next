# Kiwi feature port status for Chromium 154

This project treats the Chromium 105 Kiwi tree as a functional reference, not as an overlay.
Every feature is either mapped to a maintained Chromium 154 implementation or rewritten as a
small, independently applicable patch.

| Feature | Chromium 154 approach | Status |
| --- | --- | --- |
| Current Chromium and Android SDK | Clean Chromium 154.0.8037.21 checkout and its SDK 37 toolchain | Ready |
| History privacy lock | Device reauthentication with fingerprint, face, PIN, pattern, or password | Ported; compile-checked |
| Full-screen video assistant | Public MediaSession API plus current fullscreen callbacks | Ported; compile-checked |
| Toolbar shortcut reliability | Keep short-click listener active during optional-button animations | Ported; compile-checked |
| Automatic translation | Native TranslateBridge and current always-translate preferences | Upstream implementation retained |
| Top/bottom address bar | Current ToolbarPositionController and AddressBarPreference | Upstream implementation retained |
| Dark pages/night mode | Current WebContents dark-mode implementation | Upstream implementation retained |
| Expanded privacy lock | Device-auth gates for Bookmarks and Downloads; sensitive UI is created only after success | Ported; compile-checked |
| Per-site ad blocking switch | Current ADS content-setting API, dynamic menu label, and page reload | Ported; compile-check pending |
| Extension runtime | Chromium 154 Desktop Android extension backend enabled in the main release configuration | Integrated; compile-check pending |
| Extension menu, popup and actions | Current Android extensions toolbar, action popup, site-access controls, context menu, manager and Web Store | Upstream implementation integrated; compile-check pending |
| Toolbar and appearance customization | Current top/bottom address bar, Appearance settings, adaptive toolbar shortcut, plus reliable animation clicks | Integrated; compile-check pending after full configuration change |
| Edge-swipe back/forward navigation | Current HistoryNavigationCoordinator and NavigationHandler, including history checks and transition animation | Upstream implementation integrated; enabled by default |
| Remaining Kiwi settings/menu customizations | Recreate only settings backed by a working current implementation | Pending |
| Legacy web translator choices | Do not port brittle external redirect URLs | Replaced by native translation |

## Porting rules

1. Never copy the complete Chromium 105 source overlay into Chromium 154.
2. Prefer an existing Chromium 154 feature when it provides the same behavior.
3. Keep each Kiwi-owned feature in a separate patch under `.build/patches/chromium154`.
4. Compile the smallest affected GN target first, then `chrome_java`, then the APK target.
5. Do not advertise a setting until its runtime implementation exists and compiles.
6. Keep the old Chromium 105 checkout untouched as the behavior reference.

## Build stages

The Java integration target is `chrome_java`. The APK target is `chrome_public_apk`. The provided
`BUILD_CHROMIUM_154_J5.cmd` applies all accepted patches and builds the APK with five parallel jobs.

The main `BUILD_CHROMIUM_154_J5.cmd` now enables Chromium 154's maintained Desktop Android
extension implementation, including its native Android menu and popup surfaces. The older
`BUILD_KIWI_154_EXTENSIONS_J5.cmd` remains as a separate-cache diagnostic builder.

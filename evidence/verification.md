# Verification - 2026-11-10, release 0.1.1

Delivered native Swift/AppKit arm64 app. The reported placement bug is fixed and checked on the current crowded, notched Mac. Stable Developer ID signing replaces ad-hoc signing. Real item/menu/restore acceptance is still blocked by the delivered app's TCC grants; full native UI acceptance is also incomplete. No permission was granted or bypassed by the agent.

| Check | Observed result | Evidence |
|---|---|---|
| Automatic placement from a previously hidden position | PASS. Only our saved position was deliberately set to 10000 before launch. The app reset its own placement automatically. AppKit frame x=1160..1198 lies entirely in right safe area x=759..1352. The matching real hosted window is onscreen at {{1160,0},{38,30}}. 18 actual menu windows were present. No Command-drag or TCC needed. | `permission-issue/hidden-position-launchservices.json` |
| macOS 26 virtual window identity | PASS for own anchor discovery. NSStatusBarWindow.windowNumber is 4294967296, not a CGWindowID. An intermediate diagnostic trapped on conversion; fixed with exact conversion plus unique geometry matching. Final diagnostic exits normally and resolves the real hosted anchor. | Same JSON; `buttonPrivateFrame`, `buttonHostedWindowOnScreen=true` |
| Existing permission toggle | Actual Settings Accessibility row for Menu Bar Panel was ON, while LaunchServices app returned false. TCC log confirms an incompatible old cdhash and validity status -67050. | `permission-issue/tcc-excerpt.txt`, `current.json`, `signing.txt` |
| Signing fix | Developer ID Application, Team MQKD7Z7V2L; signature verifies. Designated requirement remains identical after code changes, instead of binding to one ad-hoc cdhash. No notarization/publication. | `signature.txt`, `permission-issue/signature-continuity.txt` |
| Current app grants | Accessibility=false, ScreenRecording=false. Requires one user-controlled replacement of the legacy entry with this signed app in System Settings. | `permission-issue/hidden-position-launchservices.json` |
| Native build | PASS. arm64 Mach-O, macOS 14 minimum, AppKit/ApplicationServices/ScreenCaptureKit. | `build.txt`, `binary.txt` |
| Reproducible build | PASS. Independent rebuild's unsigned Mach-O payload byte-identical. CMS signing metadata is intentionally excluded from byte comparison. | `reproducible-build.txt` |
| Durable restoration | PASS on fixtures: item and source PID, both neighbors, old-format journal, reopen, second-move lock, corrupt bytes preserved, no-neighbor guard. No mouse events posted. | `journal-checks.txt`, `Tests/JournalChecks.swift` |
| macOS 26 real source process | Implemented using bounded Accessibility extras-menu frame matching off the main thread, with source PID in journal/menu-close monitoring. Actual AX mapping/menu/restore NOT TESTED without app permission. | `Sources/SourceApplication.swift`, `THIRD_PARTY.md` |
| Native rendered UI | Intermediate real denied state inspected in light theme, cropped window only. Final CUA binding returned cgWindowNotFound. Final full-screen light/dark review NOT PASSED. | `permission-issue/native-ui.txt`, session tool screenshots |
| Keyboard, Escape, outside click, toggle, UI Quit | NOT PASSED through normal final UI interactions. Explicit Tab loop added after observed non-advancing focus; no unsupported claim based on source/build. | Same native report |
| Actual hidden icons, real owner menus/actions, real order restoration | BLOCKED by app TCC; no synthetic images, Dock list or fake success used. | LaunchServices diagnostics |
| Displays | Physical 1352x878 @2x screen, safeTop=29; placement checked there. A second display observed earlier disconnected without agent action. Multi-display switching and full-screen Spaces NOT TESTED. | Diagnostics |
| State preservation | No third-party menu item moved during tests. Only this app's own preferred-position key changed. No TCC/SIP/foreign settings/services or login item changed. | Fixture log; own-position reproduction |
| ZIP | App, complete corresponding source, checks, docs, evidence. Signature/extraction verified. | `archive-check.txt`, `dist/SHA256SUMS` |

## Remaining user action

In System Settings -> Privacy & Security -> Accessibility, remove the old **Menu Bar Panel** entry and add `/Users/alex/Projects/mine/menu-bar-panel/dist/Menu Bar Panel.app` using the normal minus/plus controls, then enable it yourself. Repeat the legacy-entry replacement in Screen & System Audio Recording if the delivered app still reports no capture access. Restart only Menu Bar Panel if macOS asks. The agent has not toggled or transferred permissions. This one-time migration is needed because the old grant was tied to an obsolete ad-hoc signature; subsequent builds must retain this Developer ID identity.

After the user confirms, recheck through LaunchServices and perform real image/menu/action/neighbor-restoration acceptance, final full-screen UI review in both themes, keyboard/outside click and display-switch checks. Do not substitute direct executable launch under a trusted terminal, a screenshot, compilation, or fixtures for those checks.

## Historical evidence

`diagnostics.json` came from direct executable launch under the terminal host and reported true permissions. It is explicitly rejected as evidence for the delivered LaunchServices app. Earlier 0.1.0 archives/logs describe the ad-hoc build, not the current release. Intermediate diagnostics with `buttonWindowOnScreen=false` used an invalid own-PID lookup on macOS 26; the current hosted-window diagnostic supersedes them. Raw targeted TCC/sample logs remain locally in `.build/investigation`; the release contains the minimal relevant TCC excerpt.

## Recheck after user reported granting access

The native System Settings Accessibility row was observed ON. TCC recorded Accessibility Allowed for the current Developer ID requirement at 06:55:56 local time. A fresh LaunchServices diagnostic at 06:59 still returned Accessibility=false and ScreenRecording=false; new process PID 80116 was checked against the legacy ad-hoc cdhash and rejected with -67050. Merely toggling the existing row did not resolve the stale requirement. No permissions were modified by the agent. Evidence: `permission-issue/after-user-grant.json`, `permission-issue/after-user-grant-tcc.txt`. The app was restarted normally and left running; native popover still displayed the Accessibility required state. The button remained onscreen outside the notch. User-controlled removal and re-addition of the app entry is still required; real menus and restoration remain unverified.

## Continued permission failure, fresh process

After the next user report, the existing signed bundle was not rebuilt. Repeated the actual Refresh button through native UI; the denied state remained. Graceful quit and fresh LaunchServices process PID 86062 again returned both grants false (`permission-issue/retry-fresh-process.json`). The live process signature was then checked with Security.framework: SecCodeCheckValidity returned 0, Team MQKD7Z7V2L and the expected Developer ID requirement, with the same cdhash as the disk binary (`permission-issue/dynamic-signature.txt`). This rules out an old executable or a broken on-disk signature. System Settings Accessibility was still ON. System tccd (UID 0) logged the new Allowed requirement but continued validating requests against the legacy ad-hoc cdhash (-67050). The remaining cause is in TCC permission-record/cache handling, not a cached Bool in the app (both properties call native preflight functions on every refresh). Whether the user removed/re-added the entry, rather than toggling it, is awaiting clarification. No bundle identifier was changed to evade the denial; no TCC database, permissions or services were modified.

## Confirmed removal/re-addition resolved Accessibility

After the user explicitly confirmed removing and re-adding the entry, a graceful restart and fresh LaunchServices diagnostic returned Accessibility=true, ScreenRecording=false (`permission-issue/after-readd.json`). Own hosted button remained onscreen outside the notch. Native app UI advanced to the real screen-capture permission state; it no longer asked for Accessibility. Invoked the app screen-recording request button; native System Settings opened Screen & System Audio Recording. Menu Bar Panel was absent from that list. The user must add the exact delivered app with the normal + control and enable access; the agent did not grant or modify permissions. Real snapshots/menu/restore acceptance remains blocked only by capture permission. Earlier false Accessibility results are historical.

## 2026-11-10: redesign and real end-to-end acceptance (Claude session)

UI: single permission checklist, ribbon of real icons in the menu bar appearance, "⋯" and right-click menu (Обновить, Выйти), single instance (second launch opens the running panel), `--diagnose` never moves or restores. Screenshots checked: ribbon in menu-bar (dark) appearance, light override shows white snapshots are invisible on a light panel (reason for matching the menu bar), permission screen light and dark via `--preview-setup`, restore-failure panel, right-click menu, Escape closes the panel (trace `key 53` then `closed`).

Root causes found and fixed in moving/restoring real items on macOS 26.5.2 with a notch:
- Move confirmation ran at 100 ms while the menu bar still animated; successful moves were reported as failures and retried, which drifted the Bitwarden item. Now confirmed by icon order after 0.6 s.
- A drop behind the notch or under the active app's menus is not placed by macOS. Restore now activates the app and rebuilds the recorded order by inserting items, left to right, before a visible anchor.
- The AudioVideoModule indicator keeps a fixed slot; a drop right of it is ignored. It is excluded from order and anchors.
- An unfinished synthetic Cmd-drag left Command and the left button down in the combined session state. Moves now release session state at the end; the modifier guard reads the HID state.
- Process-targeted click events did not open menus of Control Center-hosted items; replaced with a plain click at the item, cursor restored.
- Journal now stores the full order; neighbours-only restore could leave other items shifted.

Real acceptance (LaunchServices app, synthetic input from the agent's harness): Granola item hidden behind the notch was opened from the panel, moved next to the button, its real menu opened and stayed open; after the menu closed all 17 items returned to the exact recorded order (8 rebuild moves, all confirmed first attempt); journal cleared; session button/Command state clean. The user's layout disturbed during debugging was restored to the order recorded at session start. Bitwarden tray opens no menu on left click (owner behaviour). Not tested: second display, full-screen Spaces, VoiceOver.

## 2026-11-10: no auto-return, cursor kept in place (user request)

User asked: a selected icon just moves next to the button and stays; no automatic return, no cursor jumps. Removed the restoration journal, menu tracking, source-PID discovery and the synthetic click (moved out of the project, not deleted). Measured cursor during a move with 2 ms polling: before, it went to the screen corner and to the drop point for about 0.5 s; now it is hidden during the move and away for about 70 ms. Warping the cursor back between press and release broke the drop point (first attempts landed one slot off), so it is restored only after release. With confirmation polling up to 1.5 s, four long moves (Granola left and back twice) each landed on the first attempt. Real app: Granola selected from the panel now stays left of the button.

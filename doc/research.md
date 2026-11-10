# Research: macOS 26.5.2 (25F84), 2026-11-10

## Public API boundary

NSStatusBar/NSStatusItem creates and manages the caller's item. It does not provide an API to enumerate, reparent or embed other processes' NSStatusItem objects. Accessibility can expose menu extras and actions, but AXPress alone is not a guarantee that an offscreen item's menu becomes visible below the notch. A Dock/app list is unrelated to status item windows and was rejected.

The implementation enumerates actual status-window IDs using the WindowServer menu-bar-window interface, reads their frame/PID and captures their own backing images. Screen Recording is required for images owned by other applications. It never uses NSWorkspace.applicationIconImage or a Dock list as status content.

The selected window is moved beside our own anchor using targeted command-drag events, clicked, and restored relative to its original neighbor after the owner's interface disappears. Moving is journaled before events. Accessibility is required. This strategy follows the inspected Ice implementation; the relevant GPL adaptations are identified in THIRD_PARTY.md.

## Source evidence

- Apple NSStatusItem: https://developer.apple.com/documentation/appkit/nsstatusitem
- Apple AXUIElementCopyAttributeValue: https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue
- Apple CGPreflightScreenCaptureAccess: https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()
- Apple NSPopover transient behavior: https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/transient
- Ice source, pinned commit 11edd39115f3f43a83ae114b5348df6a0e1741cf: https://github.com/jordanbaird/Ice/tree/11edd39115f3f43a83ae114b5348df6a0e1741cf
- Ice/Utilities/ScreenCapture.swift explicitly documents the offscreen composite capture limitation of ScreenCaptureKit and uses the CGWindowList compatibility protocol. This is a source observation, not an Apple stability guarantee.
- Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift contains two-stage event delivery, target window fields, temporary item movement and neighbor restoration.
- SDK availability and real API linkage were verified by building and running against the installed macOS 26 SDK. Web Apple pages exposed JavaScript shells; SDK and upstream source supplied implementation detail. No claim of a public, supported embedding API is made.

## Local results and unresolved compatibility

A LaunchServices-launched app initially reported 36–40 status windows and two screens (one safe-area top 29 points). The final diagnostic reported one screen and 18 status windows after the external screen disconnected during work; no display settings were changed by the agent. WindowServer functions were available. It reported Accessibility=false and Screen Recording=false. Counts vary as apps create/destroy status windows. Enumeration alone does not prove that a particular hidden window has a usable backing image or accepts event delivery.

The exact full workflow remains unverified until the user grants the app's own TCC permissions. No third-party window captures or movement events were performed. Offscreen title/PID/window-ID continuity, nonmovable system extras, multiple displays with equal top coordinates and custom persistent popovers require real integration coverage. A custom popover that stays open keeps the item temporarily visible until closed or the user requests restoration through our panel/exit. Forced process termination needs next-launch recovery.

## Fixes verified on macOS 26.5.2 (2026-11-10)

The user's enabled Accessibility toggle did not match the current ad-hoc designated requirement. The targeted TCC log reports old cdhash `3e4aa531a9efe204f02cff4223ae5db3abb15b4a` and validity failure -67050. The release now uses a stable Developer ID requirement; code rebuilds were checked for requirement continuity. Apple explains how designated requirements identify compatible code and how ad-hoc requirements are code-specific: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements . This cannot transfer the old grant; the user must replace that entry once.

AppKit's own `NSStatusItem Preferred Position MenuBarPanelButton` is set to zero before constructing a zero-length item, then autosaveName and square length are applied. This follows Ice's preflight pattern, with the intentional change that the app always requests its own rightmost placement. Only its own defaults change. A reproduction starting with its own saved position 10000 yielded a real hosted onscreen frame x=1160..1198, outside the notch right edge x=759, among 18 actual status windows.

On this OS, the AppKit status window number is 4294967296; narrowing it to UInt32 traps. A safe exact conversion is used on earlier systems, and a unique frame match to the real WindowServer item is used for hosted windows. macOS 26 hosts menu windows in Control Center: original source PID must be resolved through Accessibility extras-menu frames before moving, monitoring menu close, or recording process identity. Primary implementation studied: https://github.com/jordanbaird/Ice/tree/6d74d25c33a9ab04307c1f222fbe68ad71847234 (macos-26 branch). Source-PID matching is bounded, fails closed, and remains unverified against a real selected item until the user updates app grants. See THIRD_PARTY.md for GPL attribution.

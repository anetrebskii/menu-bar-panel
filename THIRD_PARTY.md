# Third party

Menu Bar Panel is distributed under GPL-3.0 (see LICENSE), with complete corresponding source and build scripts.

The private WindowServer declarations, offscreen capture compatibility protocol, event field construction and two-stage event delivery strategy in Sources/StatusAccess.swift and Sources/ItemEvents.swift are adapted from Ice by Jordan Baird and contributors, GPL-3.0:
https://github.com/jordanbaird/Ice/tree/11edd39115f3f43a83ae114b5348df6a0e1741cf
Files studied: Ice/Bridging/Shims/Private.swift, Ice/Bridging/Bridging.swift, Ice/Utilities/ScreenCapture.swift, Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift.
Modifications: standalone minimal AppKit product, dynamic symbol availability checks, narrow hidden-window selection, order-based move confirmation, no Ice preferences or background services.

Own-status-item preferred-position preflight was researched from Ice's macos-26 branch, pinned at:
https://github.com/jordanbaird/Ice/tree/6d74d25c33a9ab04307c1f222fbe68ad71847234
Files studied: Ice/MenuBar/ControlItem/ControlItem.swift.
Modifications: exact-geometry matching for the app's own hosted button window, safe handling of virtual 64-bit AppKit window numbers. No additional package is linked.

These undocumented WindowServer/event interfaces may change with macOS releases. No code disables TCC, SIP or system protections. Screen Recording and Accessibility are required and must be granted by the user.

// Adapted in part from Ice (Jordan Baird and contributors), GPL-3.0; see THIRD_PARTY.md.
import AppKit
import ApplicationServices
import Darwin

@_silgen_name("CGSMainConnectionID") private func connection() -> Int32
@_silgen_name("CGSGetWindowCount") private func windowCount(_ c: Int32, _ target: Int32, _ count: inout Int32) -> CGError
@_silgen_name("CGSGetProcessMenuBarWindowList") private func menuWindows(_ c: Int32, _ target: Int32, _ count: Int32, _ list: UnsafeMutablePointer<CGWindowID>, _ real: inout Int32) -> CGError
@_silgen_name("CGSGetScreenRectForWindow") private func windowRect(_ c: Int32, _ id: CGWindowID, _ rect: inout CGRect) -> CGError

struct StatusWindow: Codable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let owner: String
    let frame: CGRect
    let onScreen: Bool
    var label: String { title.isEmpty ? owner : "\(owner): \(title)" }
}

enum AccessFailure: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let text) = self { return text }; return nil }
}

enum StatusAccess {
    static var trusted: Bool { AXIsProcessTrusted() }
    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }
    static var available: Bool {
        ["CGSMainConnectionID", "CGSGetWindowCount", "CGSGetProcessMenuBarWindowList", "CGSGetScreenRectForWindow"].allSatisfy {
            $0.withCString { dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0) != nil }
        }
    }
    static func frame(_ id: CGWindowID) -> CGRect? {
        guard available else { return nil }
        var rect = CGRect.zero
        return windowRect(connection(), id, &rect) == .success ? rect : nil
    }
    static func windows() throws -> [StatusWindow] {
        guard available else { throw AccessFailure.unavailable("Эта версия macOS не предоставляет нужный оконный интерфейс.") }
        var count: Int32 = 0
        guard windowCount(connection(), 0, &count) == .success, count > 0, count < 100_000 else {
            throw AccessFailure.unavailable("WindowServer не вернул список окон.")
        }
        var ids = [CGWindowID](repeating: 0, count: Int(count))
        var actual: Int32 = 0
        guard menuWindows(connection(), 0, count, &ids, &actual) == .success, actual >= 0, actual <= count else {
            throw AccessFailure.unavailable("Не удалось перечислить настоящие status items.")
        }
        var pointers = ids.prefix(Int(actual)).map { UnsafeRawPointer(bitPattern: UInt($0)) }
        let array = pointers.withUnsafeMutableBufferPointer { CFArrayCreate(nil, $0.baseAddress, $0.count, nil) }
        guard let array, let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else {
            throw AccessFailure.unavailable("Не удалось прочитать описание окон значков.")
        }
        return descriptions.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == CGWindowLevelForKey(.statusWindow),
                  let rect = frame(id), rect.width > 0, rect.height > 0 else { return nil }
            return StatusWindow(id: id, pid: pid,
                title: info[kCGWindowName as String] as? String ?? "",
                owner: info[kCGWindowOwnerName as String] as? String ?? "Значок",
                frame: rect, onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }
    static func displayBounds(_ screen: NSScreen) -> CGRect {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        return CGDisplayBounds(id)
    }
    static func hidden(_ items: [StatusWindow], screen: NSScreen, anchor: CGRect) -> [StatusWindow] {
        let bounds = displayBounds(screen)
        let rightArea = screen.auxiliaryTopRightArea
        let rightStart = rightArea.map { bounds.minX + $0.minX - screen.frame.minX } ?? bounds.minX
        return items.filter {
            $0.pid != getpid() && abs($0.frame.minY - bounds.minY) < 2 && $0.frame.width < 500 &&
            (!$0.onScreen || $0.frame.minX < rightStart || $0.frame.maxX <= bounds.minX) &&
            $0.frame.minX < anchor.maxX
        }.sorted { $0.frame.minX < $1.frame.minX }
    }
    static func image(_ item: StatusWindow) -> NSImage? {
        guard canCapture else { return nil }
        var pointer = UnsafeRawPointer(bitPattern: UInt(item.id))
        guard let array = CFArrayCreate(nil, &pointer, 1, nil),
              let image = CGImage.statusImage(bounds: .null, windows: array) else { return nil }
        return NSImage(cgImage: image, size: item.frame.size)
    }
}

private protocol OffscreenImage {
    init?(windowListFromArrayScreenBounds: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption)
}
private extension OffscreenImage {
    static func statusImage(bounds: CGRect, windows: CFArray) -> Self? {
        Self(windowListFromArrayScreenBounds: bounds, windowArray: windows, imageOption: [.boundsIgnoreFraming, .bestResolution])
    }
}
extension CGImage: OffscreenImage { }

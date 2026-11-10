// Adapted in part from Ice (Jordan Baird and contributors), GPL-3.0; see THIRD_PARTY.md.
import AppKit
import ApplicationServices

private final class TapWait {
    var taps: [CFMachPort] = []
    var sources: [CFRunLoopSource] = []
    var continuation: CheckedContinuation<Void, Error>?
    var event: CGEvent?
    var pid: pid_t = 0
    var finished = false
    func finish(_ error: Error? = nil) {
        guard !finished else { return }
        finished = true
        for tap in taps { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        for source in sources { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
    func add(pid: pid_t?, type: CGEventType, listen: Bool, callback: CGEventTapCallBack) throws {
        let ref = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1) << type.rawValue
        let tap: CFMachPort?
        if let pid {
            tap = CGEvent.tapCreateForPid(pid: pid, place: .tailAppendEventTap, options: listen ? .listenOnly : .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: ref)
        } else {
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: listen ? .listenOnly : .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: ref)
        }
        guard let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            throw AccessFailure.unavailable("macOS запретила доставку события. Проверьте Accessibility.")
        }
        taps.append(tap); sources.append(source)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

func trace(_ text: String) {
    guard CommandLine.arguments.contains("--trace-ui") else { return }
    FileHandle.standardError.write(Data("\(Date()) \(text)\n".utf8))
}

@MainActor
enum ItemEvents {
    static func event(_ type: CGEventType, point: CGPoint, window: StatusWindow, pid: pid_t, moving: Bool) throws -> CGEvent {
        guard StatusAccess.trusted, let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw AccessFailure.unavailable("Требуется разрешение Accessibility.")
        }
        event.flags = moving && type == .leftMouseDown ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.eventSourceUserData, value: Int64.random(in: 1...Int64.max))
        for field in [CGEventField.mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent, CGEventField(rawValue: 0x33)!] {
            event.setIntegerValueField(field, value: Int64(window.id))
        }
        if !moving { event.setIntegerValueField(.mouseEventClickState, value: 1) }
        return event
    }
    static func send(_ event: CGEvent, pid: pid_t, moving: Bool) async throws {
        let state = TapWait()
        state.event = event; state.pid = pid
        try await withCheckedThrowingContinuation { continuation in
            state.continuation = continuation
            do {
                try state.add(pid: nil, type: event.type, listen: true) { _, type, received, ref in
                    guard let ref else { return Unmanaged.passUnretained(received) }
                    let state = Unmanaged<TapWait>.fromOpaque(ref).takeUnretainedValue()
                    guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput, let expected = state.event else { return Unmanaged.passUnretained(received) }
                    if received.getIntegerValueField(.eventSourceUserData) == expected.getIntegerValueField(.eventSourceUserData) {
                        if state.pid != 0 { expected.postToPid(state.pid) }
                        state.finish()
                    }
                    return Unmanaged.passUnretained(received)
                }
                if moving {
                    guard let null = CGEvent(source: nil) else { throw AccessFailure.unavailable("Не удалось создать событие.") }
                    null.setIntegerValueField(.eventSourceUserData, value: event.getIntegerValueField(.eventSourceUserData))
                    try state.add(pid: pid, type: .null, listen: false) { _, _, received, ref in
                        guard let ref else { return Unmanaged.passUnretained(received) }
                        let state = Unmanaged<TapWait>.fromOpaque(ref).takeUnretainedValue()
                        guard let event = state.event,
                              received.getIntegerValueField(.eventSourceUserData) == event.getIntegerValueField(.eventSourceUserData) else { return Unmanaged.passUnretained(received) }
                        event.post(tap: .cgSessionEventTap)
                        return nil
                    }
                    null.postToPid(pid)
                } else {
                    state.pid = 0
                    event.post(tap: .cgSessionEventTap)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    state.finish(AccessFailure.unavailable("macOS не подтвердила доставку события."))
                }
            } catch { state.finish(error) }
        }
    }
    static func releaseSession() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let location = CGEvent(source: nil)?.location ?? .zero
        if CGEventSource.buttonState(.combinedSessionState, button: .left),
           let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) {
            up.flags = []; up.post(tap: .cgSessionEventTap)
        }
        if CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand), let flags = CGEvent(source: source) {
            flags.type = .flagsChanged; flags.flags = []; flags.post(tap: .cgSessionEventTap)
        }
    }
    static func adjacent(_ item: StatusWindow, _ target: StatusWindow, left: Bool) -> Bool {
        guard let all = try? StatusAccess.windows() else { return false }
        let line = all.filter { abs($0.frame.minY - target.frame.minY) < 2 && ($0.id == target.id || $0.id == item.id || $0.title != "AudioVideoModule") }
            .sorted { $0.frame.minX < $1.frame.minX }.map(\.id)
        guard let i = line.firstIndex(of: item.id), let j = line.firstIndex(of: target.id) else { return false }
        return left ? i + 1 == j : i == j + 1
    }
    static func move(_ item: StatusWindow, beside target: StatusWindow, left: Bool) async throws {
        let held = CGEventSource.flagsState(.hidSystemState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard held.isEmpty, !CGEventSource.buttonState(.hidSystemState, button: .left) else {
            throw AccessFailure.unavailable("Отпустите кнопки мыши и клавиши-модификаторы, затем повторите.")
        }
        var tried: [CGFloat] = []
        for attempt in 0..<4 {
            guard let rect = StatusAccess.frame(target.id), let start = StatusAccess.frame(item.id) else { throw AccessFailure.unavailable("Значок исчез.") }
            if adjacent(item, target, left: left) { return }
            let edge = left ? rect.minX + 2 : rect.maxX - 2
            let offsets = [start.midX < rect.midX ? -start.width : 0, 0, -start.width, start.width].filter { !tried.contains($0) }
            guard let offset = offsets.first else { break }
            tried.append(offset)
            let x = edge + offset
            let visible = (try? StatusAccess.windows())?.filter { $0.onScreen && abs($0.frame.minY - rect.minY) < 2 }.map(\.frame.minX).min() ?? rect.minX
            if x < visible + 2 { continue }
            trace("move \(item.id)@\(Int(start.minX)) \(left ? "left" : "right") of \(target.id)@\(Int(rect.minX)) drop x=\(Int(x)) attempt \(attempt)")
            let down = try event(.leftMouseDown, point: CGPoint(x: 20_000, y: 20_000), window: item, pid: item.pid, moving: true)
            let up = try event(.leftMouseUp, point: CGPoint(x: x, y: rect.midY), window: target, pid: item.pid, moving: true)
            let cursor = CGEvent(source: nil)?.location
            CGDisplayHideCursor(CGMainDisplayID())
            do {
                try await send(down, pid: item.pid, moving: true)
                try await Task.sleep(for: .milliseconds(60))
                try await send(up, pid: item.pid, moving: true)
            } catch {
                trace("move \(item.id) delivery failed: \(error.localizedDescription)")
            }
            releaseSession()
            if let cursor { CGWarpMouseCursorPosition(cursor) }
            CGDisplayShowCursor(CGMainDisplayID())
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(300))
                if adjacent(item, target, left: left) || adjacent(item, target, left: !left) { return }
            }
            trace("move \(item.id) not confirmed: now \(StatusAccess.frame(item.id).map { Int($0.minX) } ?? -1)")
        }
        trace("move \(item.id) gave up")
    }
}

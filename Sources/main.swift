import AppKit
import ApplicationServices
import ScreenCaptureKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ContentController: NSViewController {
    override func loadView() { view = FlippedView(frame: NSRect(x: 0, y: 0, width: 390, height: 220)) }
}

final class KeyboardButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}

final class ItemButton: NSButton {
    var hovering = false { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { true }
    var shape: NSBezierPath { NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 5, yRadius: 5) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted { NSColor.tertiaryLabelColor.setFill(); shape.fill() }
        else if hovering { NSColor.quaternaryLabelColor.setFill(); shape.fill() }
        super.draw(dirtyRect)
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { shape.fill() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static let positionKey = "NSStatusItem Preferred Position MenuBarPanelButton"
    static func makeStatusItem(rightmost: Bool = false) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: 0)
        if !CommandLine.arguments.contains("--diagnose") {
            if rightmost || UserDefaults.standard.object(forKey: positionKey) == nil { UserDefaults.standard.set(0, forKey: positionKey) }
            item.autosaveName = "MenuBarPanelButton"
        }
        item.length = NSStatusItem.squareLength
        return item
    }
    var status = makeStatusItem()
    let popover = NSPopover()
    let content = ContentController()
    var current: [StatusWindow] = []
    var working = false
    var errorText: String?
    var displayedAccess: (accessibility: Bool, capture: Bool)?
    let diagnosing = CommandLine.arguments.contains("--diagnose")
    let previewSetup = CommandLine.arguments.contains("--preview-setup")
    var appearanceOverride: NSAppearance?
    nonisolated static let showNotification = Notification.Name("net.thealex.menu-bar-panel.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--appearance=light") { appearanceOverride = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--appearance=dark") { appearanceOverride = NSAppearance(named: .darkAqua) }
        DistributedNotificationCenter.default().addObserver(forName: Self.showNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.popover.isShown == false { self?.toggle() } }
        }
        configureStatusButton()
        popover.behavior = .transient
        popover.contentViewController = content
        popover.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.traceUI("key \(event.keyCode)")
            if event.keyCode == 53, self?.popover.isShown == true { self?.popover.performClose(nil); return nil }
            if [48, 123, 124].contains(event.keyCode), let self, self.popover.isShown {
                let buttons = self.keyboardButtons(in: self.content.view)
                if !buttons.isEmpty {
                    let current = buttons.firstIndex { $0 === self.content.view.window?.firstResponder }
                    let step = event.keyCode == 123 || (event.keyCode == 48 && event.modifierFlags.contains(.shift)) ? -1 : 1
                    let index = current.map { ($0 + step + buttons.count) % buttons.count } ?? 0
                    self.content.view.window?.makeFirstResponder(buttons[index])
                    buttons[index].scrollToVisible(buttons[index].bounds)
                }
                return nil
            }
            if [36, 76].contains(event.keyCode), let self, self.popover.isShown,
               let focused = self.content.view.window?.firstResponder as? NSControl { focused.performClick(nil); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "r", self?.popover.isShown == true { self?.reload(); return nil }
            return event
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.ensureButtonVisible()
            if CommandLine.arguments.contains("--diagnose") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.diagnostics()
                    NSApp.terminate(nil)
                }
            } else if CommandLine.arguments.contains("--show") { self.toggle() }
        }
    }
    func configureStatusButton() {
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Скрытые значки")
            button.image?.isTemplate = true
            button.toolTip = "Скрытые значки строки меню"
            button.setAccessibilityLabel("Скрытые значки строки меню")
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    @objc func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            guard let button = status.button else { return }
            moreMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 6), in: button)
        } else { toggle() }
    }
    func moreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Обновить", action: #selector(reload), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из Menu Bar Panel", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }
    @objc func showMore(_ sender: NSButton) {
        moreMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }
    var buttonIsVisible: Bool {
        guard let window = status.button?.window, window.isVisible, let screen = window.screen else { return false }
        let area = screen.auxiliaryTopRightArea ?? screen.frame
        return window.frame.minX >= area.minX && window.frame.maxX <= area.maxX && window.frame.width > 0
    }
    func ensureButtonVisible() {
        guard !buttonIsVisible, !working else { return }
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(status)
        status = Self.makeStatusItem(rightmost: true)
        configureStatusButton()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if popover.isShown, let displayedAccess,
           displayedAccess.accessibility != StatusAccess.trusted || displayedAccess.capture != StatusAccess.canCapture {
            refresh(); focusFirstButton()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return true
    }
    func focusFirstButton() {
        let buttons = keyboardButtons(in: content.view)
        if let button = buttons.first(where: { ($0 as? NSButton)?.keyEquivalent == "\r" }) ?? buttons.first(where: { $0.action == #selector(selectItem(_:)) || $0.action == #selector(accessibility) || $0.action == #selector(capture) }) ?? buttons.first {
            content.view.window?.makeFirstResponder(button)
        }
    }
    func keyboardButtons(in view: NSView) -> [NSControl] {
        view.subviews.flatMap { child -> [NSControl] in
            if let control = child as? NSButton, control.isEnabled { return [control] }
            return keyboardButtons(in: child)
        }
    }
    func diagnostics() {
        let windows = try? StatusAccess.windows()
        let info: [String: Any] = ["accessibility": StatusAccess.trusted, "screenRecording": StatusAccess.canCapture,
            "windowServerAPI": StatusAccess.available, "statusWindowCount": windows?.count ?? -1,
            "buttonFrame": status.button?.window.map { NSStringFromRect($0.frame) } ?? "unavailable",
            "buttonVisibleOutsideNotch": buttonIsVisible,
            "buttonWindowNumber": status.button?.window?.windowNumber ?? -1,
            "buttonPrivateFrame": ownWindow().map { NSStringFromRect($0.frame) } ?? "unavailable",
            "buttonHostedWindowOnScreen": ownWindow()?.onScreen ?? false,
            "buttonRightSafeArea": status.button?.window?.screen?.auxiliaryTopRightArea.map { NSStringFromRect($0) } ?? "not needed",
            "bundlePath": Bundle.main.bundlePath,
            "popoverShown": popover.isShown,
            "screens": NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "safeTop": $0.safeAreaInsets.top, "scale": $0.backingScaleFactor] }]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
    }
    @objc func toggle() {
        traceUI("toggle")
        if popover.isShown { popover.performClose(nil); return }
        guard let button = status.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.appearance = appearanceOverride ?? NSAppearance(named: button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua)
        refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        content.view.window?.makeFirstResponder(nil)
        traceUI("shown")
    }
    func traceUI(_ event: String) {
        guard CommandLine.arguments.contains("--trace-ui") else { return }
        let line = "\(Date()) \(event) shown=\(popover.isShown) active=\(NSApp.isActive) key=\(content.viewIfLoaded?.window?.isKeyWindow ?? false)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
    func popoverDidClose(_ notification: Notification) { traceUI("closed") }
    @objc func screenChanged() {
        traceUI("screen/space changed")
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.ensureButtonVisible() }
    }
    func label(_ text: String, title: Bool = false, width: CGFloat = 320) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = title ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold) : .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = title ? .labelColor : .secondaryLabelColor
        field.preferredMaxLayoutWidth = width
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }
    func button(_ title: String, action: Selector) -> NSButton {
        let button = KeyboardButton(title: title, target: self, action: action)
        button.bezelStyle = .push
        button.controlSize = .small
        return button
    }
    func moreButton() -> NSButton {
        let more = ItemButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Ещё")!, target: self, action: #selector(showMore(_:)))
        more.isBordered = false; more.bezelStyle = .regularSquare
        more.contentTintColor = .secondaryLabelColor
        more.toolTip = "Обновить или выйти"
        more.widthAnchor.constraint(equalToConstant: 28).isActive = true
        more.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return more
    }
    func header(_ title: String) -> NSView {
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label(title, title: true, width: 280), spacer, moreButton()])
        row.orientation = .horizontal; row.alignment = .centerY
        return row
    }
    func permissionRow(granted: Bool, title: String, detail: String, action: Selector) -> NSView {
        let mark = NSImageView(image: NSImage(systemSymbolName: granted ? "checkmark.circle.fill" : "circle", accessibilityDescription: granted ? "Включено" : "Выключено")!)
        mark.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        mark.contentTintColor = granted ? .systemGreen : .tertiaryLabelColor
        mark.widthAnchor.constraint(equalToConstant: 18).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let text = NSStackView(views: [label(title, width: 190), label(detail, width: 190)])
        text.widthAnchor.constraint(equalToConstant: 190).isActive = true
        (text.views[0] as! NSTextField).font = .systemFont(ofSize: NSFont.systemFontSize)
        (text.views[0] as! NSTextField).textColor = .labelColor
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 2
        let trailing: NSView = granted ? label("Включено", width: 80) : button("Открыть настройки", action: action)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [mark, text, spacer, trailing])
        row.orientation = .horizontal; row.alignment = .top; row.spacing = 10
        row.setAccessibilityElement(true); row.setAccessibilityLabel("\(title): \(granted ? "включено" : "выключено")")
        return row
    }
    func refresh() {
        displayedAccess = (StatusAccess.trusted, StatusAccess.canCapture)
        content.loadViewIfNeeded()
        content.view.subviews.forEach { $0.removeFromSuperview() }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(stack)
        var inset: CGFloat = 16
        var width: CGFloat = 400
        if previewSetup || !StatusAccess.trusted || !StatusAccess.canCapture {
            stack.spacing = 14
            stack.addArrangedSubview(header("Дайте доступ к строке меню"))
            stack.addArrangedSubview(permissionRow(granted: StatusAccess.trusted, title: "Универсальный доступ",
                detail: "Чтобы переносить значки к кнопке в строке меню.", action: #selector(accessibility)))
            stack.addArrangedSubview(permissionRow(granted: StatusAccess.canCapture && !previewSetup, title: "Запись экрана",
                detail: "Чтобы показать настоящие значки. Снимки не покидают этот Mac.", action: #selector(capture)))
            for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        } else {
            inset = 6
            stack.spacing = 4
            var notes: [String] = []
            do {
                guard let screen = status.button?.window?.screen, let anchor = ownWindow() else {
                    throw AccessFailure.unavailable("Не удалось определить экран кнопки.")
                }
                current = StatusAccess.hidden(try StatusAccess.windows(), screen: screen, anchor: anchor.frame)
            } catch { current = []; notes.append(error.localizedDescription) }
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 0
            var failures = 0
            for (index, item) in current.enumerated() {
                guard let image = StatusAccess.image(item) else { failures += 1; continue }
                let b = ItemButton(image: image, target: self, action: #selector(selectItem(_:)))
                b.tag = index; b.bezelStyle = .regularSquare; b.isBordered = false
                b.imageScaling = .scaleProportionallyDown
                b.toolTip = item.owner
                b.setAccessibilityLabel(item.label)
                b.widthAnchor.constraint(equalToConstant: min(160, max(28, item.frame.width))).isActive = true
                b.heightAnchor.constraint(equalToConstant: 30).isActive = true
                row.addArrangedSubview(b)
            }
            if row.arrangedSubviews.isEmpty, notes.isEmpty, failures == 0 {
                let empty = label("Все значки помещаются в строку меню", width: 260)
                let pad = NSView(); pad.widthAnchor.constraint(equalToConstant: 4).isActive = true
                row.addArrangedSubview(pad); row.addArrangedSubview(empty); row.alignment = .centerY
                row.addArrangedSubview(NSView())
            }
            let rowWidth = row.fittingSize.width
            let bar = NSStackView(); bar.orientation = .horizontal; bar.spacing = 2; bar.alignment = .centerY
            if rowWidth > 640 {
                let scroll = NSScrollView(); scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
                scroll.documentView = row
                row.frame = NSRect(x: 0, y: 0, width: rowWidth, height: 30)
                scroll.heightAnchor.constraint(equalToConstant: 30).isActive = true
                scroll.widthAnchor.constraint(equalToConstant: 640).isActive = true
                bar.addArrangedSubview(scroll)
            } else { bar.addArrangedSubview(row) }
            let divider = NSBox(); divider.boxType = .separator
            divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
            if !row.arrangedSubviews.contains(where: { $0 is NSTextField }) { bar.addArrangedSubview(divider) }
            bar.addArrangedSubview(moreButton())
            stack.addArrangedSubview(bar)
            if failures > 0 { notes.append("Не удалось показать значков: \(failures). Обновите панель.") }
            if let errorText { notes.append(errorText) }
            for note in notes {
                let field = label(note, width: max(240, min(640, rowWidth)))
                let wrap = NSStackView(views: [field]); wrap.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 4, right: 6)
                stack.addArrangedSubview(wrap)
            }
            width = max(bar.fittingSize.width + inset * 2, notes.isEmpty ? 0 : 280)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.view.leadingAnchor, constant: inset),
            stack.topAnchor.constraint(equalTo: content.view.topAnchor, constant: inset)
        ])
        stack.widthAnchor.constraint(equalToConstant: width - inset * 2).isActive = true
        let size = NSSize(width: width, height: stack.fittingSize.height + inset * 2)
        content.view.setFrameSize(size)
        content.preferredContentSize = size
        popover.contentSize = size
        let buttons = keyboardButtons(in: content.view)
        for (index, button) in buttons.enumerated() { button.nextKeyView = buttons[(index + 1) % buttons.count] }
    }
    func ownWindow() -> StatusWindow? {
        guard let window = status.button?.window, let screen = window.screen else { return nil }
        if let id = CGWindowID(exactly: window.windowNumber), let frame = StatusAccess.frame(id) {
            return StatusWindow(id: id, pid: getpid(), title: "Menu Bar Panel", owner: "Menu Bar Panel", frame: frame, onScreen: window.isVisible)
        }
        let display = StatusAccess.displayBounds(screen)
        let center = CGPoint(x: display.minX + window.frame.midX - screen.frame.minX,
                             y: display.minY + screen.frame.maxY - window.frame.midY)
        let matches = (try? StatusAccess.windows())?.filter {
            abs($0.frame.midX - center.x) <= 1 && abs($0.frame.midY - center.y) <= 1 && abs($0.frame.width - window.frame.width) <= 2
        } ?? []
        return matches.count == 1 ? matches[0] : nil
    }
    @objc func reload() { errorText = nil; refresh() }
    @objc func accessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func capture() {
        SCShareableContent.getWithCompletionHandler { _, _ in }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func selectItem(_ sender: NSButton) {
        guard current.indices.contains(sender.tag), !working else { return }
        let item = current[sender.tag]
        trace("select tag \(sender.tag) item \(item.id) of \(current.map(\.id))")
        popover.performClose(nil)
        working = true
        Task { @MainActor in
            do {
                guard StatusAccess.trusted, StatusAccess.canCapture, let own = ownWindow(),
                      let screen = status.button?.window?.screen else { throw AccessFailure.unavailable("Нет доступа к значкам.") }
                guard let latest = try StatusAccess.windows().first(where: { $0.id == item.id && $0.pid == item.pid }) else { throw AccessFailure.unavailable("Значок исчез. Обновите панель.") }
                guard own.frame.minX - latest.frame.width > StatusAccess.displayBounds(screen).minX,
                      screen.auxiliaryTopRightArea.map({ own.frame.minX - latest.frame.width >= StatusAccess.displayBounds(screen).minX + $0.minX - screen.frame.minX }) ?? true else {
                    throw AccessFailure.unavailable("Рядом с кнопкой нет места. Переместите кнопку правее с Command-перетаскиванием.")
                }
                try await ItemEvents.move(latest, beside: own, left: true)
                errorText = nil
            } catch {
                trace("select failed: \(error.localizedDescription)")
                errorText = error.localizedDescription
                if popover.isShown { refresh() } else { toggle() }
            }
            working = false
        }
    }
}

if !CommandLine.arguments.contains("--diagnose"),
   NSRunningApplication.runningApplications(withBundleIdentifier: "net.thealex.menu-bar-panel").contains(where: { $0.processIdentifier != getpid() }) {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.showNotification, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

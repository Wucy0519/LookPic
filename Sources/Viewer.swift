import AppKit
import QuartzCore

enum TransitionMode: String {
    case hard
    case slide

    static func stored() -> TransitionMode {
        TransitionMode(rawValue: UserDefaults.standard.string(forKey: "transitionMode") ?? "") ?? .hard
    }

    func store() {
        UserDefaults.standard.set(rawValue, forKey: "transitionMode")
    }
}

final class ViewerController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    private let stage = SlideStage()
    private let emptyState = NSStackView()
    private let previousButton = RoundButton(symbol: "chevron.left", help: "上一张")
    private let nextButton = RoundButton(symbol: "chevron.right", help: "下一张")
    private let modeControl = NSSegmentedControl(labels: ["硬切换", "滑动"], trackingMode: .selectOne, target: nil, action: nil)
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let lockButton = NSButton()
    private let saveButton = NSButton()
    private var catalog = ImageCatalog(directory: URL(fileURLWithPath: "/"), files: [])
    private var index: Int?
    private var loadToken = 0
    private var cache: [URL: NSImage] = [:]
    private var cacheOrder: [URL] = []
    private var aspectLocked = false
    private var aspect: CGFloat = 1
    private var updatingFields = false
    private var saving = false
    private var subtitleToken = 0

    convenience init() {
        let window = GlanceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "看图"
        window.minSize = NSSize(width: 920, height: 580)
        window.setFrameAutosaveName("看图主窗口")
        window.titlebarSeparatorStyle = .line
        let root = RootView()
        window.contentView = root
        self.init(window: window)
        window.delegate = self
        root.controller = self
        buildInterface()
    }

    func open(_ url: URL) {
        let reached = url.standardizedFileURL
        let isDirectory = (try? reached.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let catalog = ImageCatalog.load(containing: isDirectory ? reached : reached)
        guard !catalog.files.isEmpty else {
            present(message: "这个位置没有可以查看的图片")
            showWindow(nil)
            return
        }
        let start: Int
        if isDirectory {
            start = 0
        } else if let found = catalog.index(of: reached) {
            start = found
        } else if ImageCatalog.extensions.contains(reached.pathExtension.lowercased()) {
            present(message: "无法打开 \(reached.lastPathComponent)")
            return
        } else {
            present(message: "请打开图片文件")
            return
        }
        self.catalog = catalog
        cache.removeAll()
        cacheOrder.removeAll()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        display(index: start, direction: 0, animated: false)
    }

    private func buildInterface() {
        guard let window, let content = window.contentView else { return }
        content.wantsLayer = true

        stage.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stage)

        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 10
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .light)
        symbol.contentTintColor = .tertiaryLabelColor
        let title = NSTextField(labelWithString: "打开一张图片")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center
        let detail = NSTextField(wrappingLabelWithString: "打开后，用键盘左右键或画面两侧的按钮，连续查看同一文件夹里的图片。")
        detail.preferredMaxLayoutWidth = 360
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        let openButton = NSButton(title: "打开图片", target: self, action: #selector(openImage(_:)))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        for view in [symbol, title, detail, openButton] {
            emptyState.addArrangedSubview(view)
        }
        emptyState.setCustomSpacing(16, after: detail)
        content.addSubview(emptyState)

        previousButton.target = self
        previousButton.action = #selector(showPrevious(_:))
        nextButton.target = self
        nextButton.action = #selector(showNext(_:))
        for button in [previousButton, nextButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(button)
        }

        NSLayoutConstraint.activate([
            stage.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stage.topAnchor.constraint(equalTo: content.topAnchor),
            stage.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: stage.widthAnchor, constant: -80),
            previousButton.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 22),
            previousButton.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 46),
            previousButton.heightAnchor.constraint(equalToConstant: 46),
            nextButton.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -22),
            nextButton.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 46),
            nextButton.heightAnchor.constraint(equalToConstant: 46)
        ])

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.selectedSegment = TransitionMode.stored() == .slide ? 1 : 0
        modeControl.setWidth(72, forSegment: 0)
        modeControl.setWidth(58, forSegment: 1)
        modeControl.controlSize = .regular
        installAccessory(modeControl, attribute: .left)

        configureField(widthField, placeholder: "宽")
        configureField(heightField, placeholder: "高")
        lockButton.bezelStyle = .texturedRounded
        lockButton.isBordered = false
        lockButton.imagePosition = .imageOnly
        lockButton.target = self
        lockButton.action = #selector(toggleLock(_:))
        updateLockButton()
        saveButton.title = "保存"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveResized(_:))
        saveButton.toolTip = "按输入的分辨率调整当前图片，并保存到所选文件夹"

        let times = NSTextField(labelWithString: "×")
        times.textColor = .secondaryLabelColor
        let caption = NSTextField(labelWithString: "调整为")
        caption.textColor = .secondaryLabelColor
        let cluster = NSStackView(views: [caption, widthField, times, heightField, lockButton, saveButton])
        cluster.orientation = .horizontal
        cluster.alignment = .centerY
        cluster.spacing = 6
        cluster.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        installAccessory(cluster, attribute: .right)
        updateChrome()
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.delegate = self
        field.toolTip = "输出分辨率，单位是像素"
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
    }

    private func installAccessory(_ view: NSView, attribute: NSLayoutConstraint.Attribute) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = attribute
        let width = max(view.fittingSize.width, 120)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        accessory.view = host
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func display(index: Int, direction: Int, animated: Bool) {
        guard catalog.files.indices.contains(index) else { return }
        self.index = index
        let url = catalog.files[index]
        loadToken += 1
        let token = loadToken
        window?.title = url.lastPathComponent
        let pixels = cachedPixels(for: url)
        window?.subtitle = positionText(pixels: pixels)
        updateChrome()
        load(url) { [weak self] image in
            guard let self, token == self.loadToken else { return }
            guard let image else {
                self.present(message: "无法打开 \(url.lastPathComponent)")
                return
            }
            let size = ImageResizer.pixelSize(of: image)
            self.aspect = size.height > 0 ? size.width / size.height : 1
            self.window?.subtitle = self.positionText(pixels: size)
            self.fillFields(with: size)
            let slide = animated && self.modeControl.selectedSegment == 1 && direction != 0
            self.stage.setImage(image, direction: direction, animated: slide)
            self.updateChrome()
            self.prefetchAround(index)
        }
    }

    private func positionText(pixels: NSSize?) -> String {
        let count = catalog.files.count
        let place = (index ?? 0) + 1
        guard count > 0 else { return "打开一张图片" }
        if let pixels, pixels.width > 0 {
            return "\(place) / \(count)  ·  当前 \(Int(pixels.width))×\(Int(pixels.height))"
        }
        return "\(place) / \(count)"
    }

    private func cachedPixels(for url: URL) -> NSSize? {
        guard let image = cache[url] else { return nil }
        return ImageResizer.pixelSize(of: image)
    }

    private func fillFields(with size: NSSize) {
        guard widthField.currentEditor() == nil, heightField.currentEditor() == nil else { return }
        updatingFields = true
        widthField.stringValue = "\(Int(size.width.rounded()))"
        heightField.stringValue = "\(Int(size.height.rounded()))"
        updatingFields = false
    }

    private func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let image = cache[url] {
            completion(image)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            let valid = image?.isValid == true ? image : nil
            DispatchQueue.main.async {
                if let valid { self.remember(valid, for: url) }
                completion(valid)
            }
        }
    }

    private func remember(_ image: NSImage, for url: URL) {
        cache[url] = image
        cacheOrder.removeAll { $0 == url }
        cacheOrder.append(url)
        while cacheOrder.count > 4 {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func prefetchAround(_ index: Int) {
        for neighbor in [index - 1, index + 1] where catalog.files.indices.contains(neighbor) {
            let url = catalog.files[neighbor]
            guard cache[url] == nil else { continue }
            load(url) { _ in }
        }
    }

    private func updateChrome() {
        let hasImage = index != nil
        emptyState.isHidden = hasImage
        previousButton.isHidden = !hasImage
        nextButton.isHidden = !hasImage
        let hasPrevious = index.flatMap { catalog.previous(before: $0) } != nil
        let hasNext = index.flatMap { catalog.next(after: $0) } != nil
        previousButton.isEnabled = hasPrevious
        nextButton.isEnabled = hasNext
        let canEdit = hasImage && !saving
        widthField.isEnabled = canEdit
        heightField.isEnabled = canEdit
        lockButton.isEnabled = canEdit
        saveButton.isEnabled = canEdit
        saveButton.title = saving ? "保存中" : "保存"
    }

    private func step(_ direction: Int, animated: Bool) {
        guard let index else { return }
        let target = direction < 0 ? catalog.previous(before: index) : catalog.next(after: index)
        guard let target else {
            stage.nudge(direction: CGFloat(direction))
            return
        }
        display(index: target, direction: direction, animated: animated)
    }

    @objc func openImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "打开"
        panel.message = "选择一张图片，即可连续查看它所在文件夹中的图片"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
    }

    @objc func showPrevious(_ sender: Any?) {
        step(-1, animated: modeControl.selectedSegment == 1)
    }

    @objc func showNext(_ sender: Any?) {
        step(1, animated: modeControl.selectedSegment == 1)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let mode: TransitionMode = sender.selectedSegment == 1 ? .slide : .hard
        mode.store()
    }

    @objc private func toggleLock(_ sender: Any?) {
        aspectLocked.toggle()
        updateLockButton()
    }

    private func updateLockButton() {
        let name = aspectLocked ? "lock" : "lock.open"
        lockButton.image = NSImage(systemSymbolName: name, accessibilityDescription: aspectLocked ? "已锁定比例" : "未锁定比例")
        lockButton.toolTip = aspectLocked ? "已锁定宽高比例" : "锁定宽高比例"
        lockButton.contentTintColor = aspectLocked ? .controlAccentColor : .secondaryLabelColor
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !updatingFields, aspectLocked, let field = notification.object as? NSTextField else { return }
        guard let value = positiveInt(field.stringValue), aspect > 0 else { return }
        updatingFields = true
        if field === widthField {
            heightField.stringValue = "\(max(1, Int((CGFloat(value) / aspect).rounded())))"
        } else if field === heightField {
            widthField.stringValue = "\(max(1, Int((CGFloat(value) * aspect).rounded())))"
        }
        updatingFields = false
    }

    @objc func saveResized(_ sender: Any?) {
        guard let index, catalog.files.indices.contains(index), let sourceImage = stage.image else { return }
        guard let width = positiveInt(widthField.stringValue), let height = positiveInt(heightField.stringValue) else {
            present(message: "请输入大于 0 的宽度和高度")
            return
        }
        guard width <= ImageResizer.maxEdge, height <= ImageResizer.maxEdge else {
            present(message: "宽和高不能超过 \(ImageResizer.maxEdge)")
            return
        }
        let source = catalog.files[index]
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "保存到这里"
        panel.message = "选择文件夹，保存为 \(width)×\(height) 的图片"
        panel.directoryURL = source.deletingLastPathComponent()
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            self?.export(sourceImage, width: width, height: height, source: source, folder: folder)
        }
    }

    private func export(_ image: NSImage, width: Int, height: Int, source: URL, folder: URL) {
        let proposed = ImageResizer.outputURL(source: source, width: width, height: height, directory: folder)
        if FileManager.default.fileExists(atPath: proposed.path) {
            let alert = NSAlert()
            alert.messageText = "已有同名文件"
            alert.informativeText = "\(proposed.lastPathComponent) 已经在这个文件夹里。"
            alert.addButton(withTitle: "保留两者")
            alert.addButton(withTitle: "替换")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: window!) { [weak self] response in
                switch response {
                case .alertFirstButtonReturn:
                    self?.write(image, width: width, height: height, to: ImageResizer.uniqueURL(for: proposed))
                case .alertSecondButtonReturn:
                    self?.write(image, width: width, height: height, to: proposed)
                default:
                    break
                }
            }
            return
        }
        write(image, width: width, height: height, to: proposed)
    }

    private func write(_ image: NSImage, width: Int, height: Int, to url: URL) {
        let opaque = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        guard let cg = ImageResizer.resizedImage(image, width: width, height: height, opaque: opaque) else {
            present(message: "无法按这个分辨率调整图片")
            return
        }
        saving = true
        updateChrome()
        flash("正在保存 \(width)×\(height)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            var message: String?
            do {
                try ImageResizer.write(cg, to: url)
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.saving = false
                self.updateChrome()
                if let message {
                    self.present(message: message)
                    self.restoreSubtitle()
                } else {
                    self.flash("已保存 \(url.lastPathComponent)")
                }
            }
        }
    }

    private func flash(_ text: String) {
        subtitleToken += 1
        let token = subtitleToken
        window?.subtitle = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, token == self.subtitleToken else { return }
            self.restoreSubtitle()
        }
    }

    private func restoreSubtitle() {
        guard let index else {
            window?.subtitle = "打开一张图片"
            return
        }
        let pixels = cache[catalog.files[index]].map { ImageResizer.pixelSize(of: $0) }
        window?.subtitle = positionText(pixels: pixels)
    }

    private func present(message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    private func positiveInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showPrevious(_:)):
            return index.flatMap { catalog.previous(before: $0) } != nil
        case #selector(showNext(_:)):
            return index.flatMap { catalog.next(after: $0) } != nil
        case #selector(saveResized(_:)):
            return index != nil && !saving
        case #selector(chooseHard(_:)):
            menuItem.state = modeControl.selectedSegment == 0 ? .on : .off
            return true
        case #selector(chooseSlide(_:)):
            menuItem.state = modeControl.selectedSegment == 1 ? .on : .off
            return true
        default:
            return true
        }
    }

    @objc func chooseHard(_ sender: Any?) {
        modeControl.selectedSegment = 0
        TransitionMode.hard.store()
    }

    @objc func chooseSlide(_ sender: Any?) {
        modeControl.selectedSegment = 1
        TransitionMode.slide.store()
    }

    func handleArrow(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            step(-1, animated: modeControl.selectedSegment == 1 && !event.isARepeat)
            return true
        case 124:
            step(1, animated: modeControl.selectedSegment == 1 && !event.isARepeat)
            return true
        default:
            return false
        }
    }

    func receiveDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let url = Self.dropURLs(from: sender).first else { return false }
        open(url)
        return true
    }

    func canDrop(_ sender: NSDraggingInfo) -> Bool {
        !Self.dropURLs(from: sender).isEmpty
    }

    private static func dropURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return [] }
        return items
    }
}

final class GlanceWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if let viewer = windowController as? ViewerController, viewer.handleArrow(event) { return }
        super.keyDown(with: event)
    }
}

final class RootView: NSView {
    weak var controller: ViewerController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.canDrop(sender) == true ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.receiveDrop(sender) ?? false
    }
}

final class SlideStage: NSView {
    private let currentView = NSImageView()
    private let incomingView = NSImageView()
    private var animationID = 0
    private(set) var image: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        for view in [currentView, incomingView] {
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignCenter
            view.imageFrameStyle = .none
            view.animates = true
            view.wantsLayer = true
            addSubview(view)
        }
        incomingView.isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    func setImage(_ image: NSImage?, direction: Int, animated: Bool) {
        let canSlide = animated && direction != 0 && self.image != nil && image != nil && bounds.width > 1
        animationID += 1
        if !canSlide {
            self.image = image
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            currentView.image = image
            currentView.frame = fittedRect(for: image)
            incomingView.image = nil
            incomingView.isHidden = true
            CATransaction.commit()
            return
        }
        let id = animationID
        let outgoing = self.image
        self.image = image
        currentView.image = outgoing
        currentView.frame = fittedRect(for: outgoing)
        incomingView.image = image
        let rest = fittedRect(for: image)
        let distance = bounds.width * CGFloat(direction)
        incomingView.frame = rest.offsetBy(dx: distance, dy: 0)
        incomingView.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            currentView.animator().frame = currentView.frame.offsetBy(dx: -distance, dy: 0)
            incomingView.animator().frame = rest
        } completionHandler: { [weak self] in
            guard let self, self.animationID == id else { return }
            self.currentView.image = image
            self.currentView.frame = self.fittedRect(for: image)
            self.incomingView.image = nil
            self.incomingView.isHidden = true
        }
    }

    func nudge(direction: CGFloat) {
        guard animationID >= 0, image != nil, direction != 0 else { return }
        animationID += 1
        let id = animationID
        let rest = fittedRect(for: image)
        currentView.frame = rest
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            currentView.animator().frame = rest.offsetBy(dx: -direction * 14, dy: 0)
        } completionHandler: { [weak self] in
            guard let self, self.animationID == id else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                self.currentView.animator().frame = rest
            }
        }
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = stageColor.cgColor
        guard incomingView.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentView.frame = fittedRect(for: image)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    private func fittedRect(for image: NSImage?) -> NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let available = bounds.insetBy(dx: 88, dy: 36)
        guard available.width > 1, available.height > 1 else { return bounds }
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
}

private let stageColor = NSColor(name: NSColor.Name("stage")) { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return dark
        ? NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
        : NSColor(srgbRed: 0.945, green: 0.945, blue: 0.953, alpha: 1)
}

final class RoundButton: NSView {
    let button = NSButton()
    var target: AnyObject? {
        get { button.target }
        set { button.target = newValue }
    }
    var action: Selector? {
        get { button.action }
        set { button.action = newValue }
    }
    var isEnabled: Bool {
        get { button.isEnabled }
        set {
            button.isEnabled = newValue
            alphaValue = newValue ? 1 : 0.38
        }
    }

    init(symbol: String, help: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 23
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: 2)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        image?.isTemplate = true
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.image = image?.withSymbolConfiguration(config)
        button.contentTintColor = .labelColor
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyChrome()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    private func applyChrome() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.8).cgColor
    }
}

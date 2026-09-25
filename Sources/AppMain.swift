import AppKit

@main
enum GlanceMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            _ = NSApplication.shared
            ImageCatalog.runSelfTest()
            ImageResizer.runSelfTest()
            print("self-test ok")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewer = ViewerController()
    private var pending: [URL] = []
    private var ready = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        ready = true
        viewer.showWindow(nil)
        let launched = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let urls = pending + launched.map { URL(fileURLWithPath: $0) }
        pending.removeAll()
        if let first = urls.first(where: isOpenable) {
            viewer.open(first)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if ready {
            if let first = urls.first(where: isOpenable) { viewer.open(first) }
        } else {
            pending.append(contentsOf: urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { viewer.showWindow(nil) }
        return true
    }

    private func isOpenable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue { return true }
        return ImageCatalog.extensions.contains(url.pathExtension.lowercased())
    }

    private func configureMenu() {
        let main = NSMenu()
        main.addItem(menu("看图", items: [
            item("关于看图", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("退出看图", action: #selector(NSApplication.terminate(_:)), key: "q")
        ]))
        main.addItem(menu("文件", items: [
            item("打开…", action: #selector(ViewerController.openImage(_:)), key: "o", target: viewer),
            item("保存调整后的图片…", action: #selector(ViewerController.saveResized(_:)), key: "s", target: viewer)
        ]))
        main.addItem(menu("显示", items: [
            item("硬切换", action: #selector(ViewerController.chooseHard(_:)), target: viewer),
            item("滑动", action: #selector(ViewerController.chooseSlide(_:)), target: viewer)
        ]))
        main.addItem(menu("前往", items: [
            item("上一张", action: #selector(ViewerController.showPrevious(_:)), target: viewer),
            item("下一张", action: #selector(ViewerController.showNext(_:)), target: viewer)
        ]))
        NSApp.mainMenu = main
    }

    private func menu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func item(_ title: String, action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? NSApp
        return item
    }
}

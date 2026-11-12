import AppKit

/// Per-row application selection. Removing the last app from an allowlist
/// intentionally leaves an empty allowlist, which matches no application.
@objc final class RuleScopeMenu: NSObject {
    private static func label(_ en: String, _ zh: String) -> String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? zh : en
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return url.deletingPathExtension().lastPathComponent
    }

    @objc static func summary(_ scope: NSDictionary?) -> String {
        guard let mode = scope?["mode"] as? String else { return "" }
        let ids = scope?["bundleIdentifiers"] as? [String] ?? []
        let names = ids.isEmpty ? label("None", "无") : ids.map(appName).joined(separator: ", ")
        return (mode == "only" ? label("Only ", "仅限 ") : label("Except ", "排除 ")) + names
    }

    @objc static var hint: String { label("Right-click to set the application scope", "右键设置应用范围") }

    @objc(menuForScope:window:save:)
    static func menu(for scope: NSDictionary?, window: NSWindow, save: @escaping (NSDictionary?) -> Void) -> NSMenu {
        let ids = scope?["bundleIdentifiers"] as? [String] ?? []
        let mode = scope?["mode"] as? String
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = menu.addItem(withTitle: label("Application Scope", "应用范围"), action: nil, keyEquivalent: "")
        title.isEnabled = false

        func update(_ next: String, _ list: [String]) {
            save(["mode": next, "bundleIdentifiers": Array(Set(list)).sorted()])
        }
        func choose(_ next: String) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.allowedFileTypes = ["app"]
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            panel.beginSheetModal(for: window) { response in
                guard response == .OK else { return }
                let chosen = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
                if !chosen.isEmpty { update(next, ids + chosen) }
            }
        }
        func add(_ text: String, checked: Bool = false, to parent: NSMenu, action: @escaping () -> Void) {
            let item = ScopeMenuItem(title: text, action: #selector(ScopeMenuItem.run), keyEquivalent: "")
            item.target = item
            item.performAction = action
            item.state = checked ? .on : .off
            parent.addItem(item)
        }
        add(label("All Applications", "所有应用"), checked: mode == nil, to: menu) { save(nil) }
        for (next, text) in [("only", label("Only in These Applications", "仅在这些应用")),
                             ("except", label("Exclude These Applications", "排除这些应用"))] {
            add(text, checked: mode == next, to: menu) {
                if ids.isEmpty { choose(next) } else { update(next, ids) }
            }
        }
        if let mode = mode {
            menu.addItem(.separator())
            add(label("Add Applications…", "添加应用…"), to: menu) { choose(mode) }
            if !ids.isEmpty {
                let remove = menu.addItem(withTitle: label("Remove Application", "移除应用"), action: nil, keyEquivalent: "")
                let list = NSMenu()
                remove.submenu = list
                for id in ids {
                    add(appName(id), to: list) { update(mode, ids.filter { $0 != id }) }
                    list.items.last?.toolTip = id
                }
            }
        }
        return menu
    }
}

private final class ScopeMenuItem: NSMenuItem {
    var performAction: (() -> Void)?
    @objc func run() { performAction?() }
}

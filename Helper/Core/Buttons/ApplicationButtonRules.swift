import Foundation

/// Kept on the button event tap's main run loop. A change of focus or configuration
/// takes effect after the last button-up, so an application receives a complete click.
@objc final class ApplicationButtonRules: NSObject {
    @objc static let shared = ApplicationButtonRules()

    private struct Press: Hashable { let device: UInt64; let button: Int }
    private var pressed: Set<Press> = []
    private var configured: [NSDictionary] = []
    private var requestedApp: String?
    private var pending = false
    private var nativeButtons: Set<Int> = []
    @objc private(set) var rows: [NSDictionary] = []
    @objc private(set) var enabled = false

    @objc func load(_ rows: [NSDictionary], frontmost: String?) {
        configured = rows
        requestedApp = frontmost
        pending = true
        _ = applyIfReady()
    }

    @objc func activate(_ bundleID: String?) -> Bool {
        guard bundleID != requestedApp else { return false }
        requestedApp = bundleID
        pending = true
        return applyIfReady()
    }

    private func applyIfReady() -> Bool {
        guard pending, pressed.isEmpty else { return false }
        pending = false
        let previousRows = rows
        enabled = configured.contains { $0["applicationScope"] != nil }
        rows = configured.filter { row in
            guard let scope = row["applicationScope"] else { return true }
            guard let record = scope as? NSDictionary, let mode = record["mode"] as? String,
                  let ids = record["bundleIdentifiers"] as? [String] else { return false }
            let included = requestedApp.map(ids.contains) ?? false
            switch mode {
            case "only": return included
            case "except": return !included
            default: return false
            }
        }
        nativeButtons = enabled ? buttons(in: configured).subtracting(buttons(in: rows)) : []
        return previousRows != rows
    }

    private func buttons(in rows: [NSDictionary]) -> Set<Int> {
        var result: Set<Int> = []
        for row in rows {
            if let number = (row["trigger"] as? NSDictionary)?["button"] as? Int { result.insert(number) }
            let modifiers = (row["modifiers"] as? NSDictionary)?["buttonModifiers"] as? [NSDictionary] ?? []
            result.formUnion(modifiers.compactMap { $0["button"] as? Int })
        }
        return result
    }

    @objc func passesThrough(_ button: Int) -> Bool { nativeButtons.contains(button) }
    @objc func press(_ device: UInt64, button: Int) { pressed.insert(Press(device: device, button: button)) }
    @objc func release(_ device: UInt64, button: Int) -> Bool {
        pressed.remove(Press(device: device, button: button))
        return applyIfReady()
    }
    @objc func disconnect(_ device: UInt64) -> Bool {
        pressed = pressed.filter { $0.device != device }
        return applyIfReady()
    }
    @objc func resetPresses() -> Bool {
        pressed.removeAll()
        return applyIfReady()
    }
}

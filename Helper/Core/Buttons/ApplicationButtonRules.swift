// Application-specific button rules for the Mac Mouse Fix fork. See License.
import AppKit

private enum Rule: Decodable, Equatable {
    case passThrough, missionControl, threeFingerDrag
    case shortcut(Int, Int)

    private enum Keys: String, CodingKey { case keyCode, flags }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let name = try? value.decode(String.self) {
            switch name {
            case "passThrough": self = .passThrough
            case "missionControl": self = .missionControl
            case "threeFingerDrag": self = .threeFingerDrag
            default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown action: \(name)")
            }
        } else {
            let keys = try decoder.container(keyedBy: Keys.self)
            let code = try keys.decode(Int.self, forKey: .keyCode)
            let flags = try keys.decodeIfPresent(Int.self, forKey: .flags) ?? 0
            guard (0...127).contains(code), (0...Int(UInt32.max)).contains(flags) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid keyboard shortcut")
            }
            self = .shortcut(code, flags)
        }
    }

    func row(button: Int) -> NSDictionary? {
        var effect: [String: Any]
        switch self {
        case .passThrough: return nil
        case .threeFingerDrag:
            return ["trigger": "dragTrigger", "effect": ["modifiedDragType": "threeFingerSwipe"],
                    "modifiers": ["buttonModifiers": [["button": button, "level": 1]]]]
        case .missionControl: effect = ["type": "symbolicHotkey", "variant": 32]
        case let .shortcut(code, flags): effect = ["type": "keyboardShortcut", "keycode": code, "flags": flags]
        }
        return ["trigger": ["button": button, "level": 1, "duration": "click"], "modifiers": [:], "effect": effect]
    }
}

private struct FileRules: Decodable {
    let defaults: [String: Rule]?
    let applications: [String: [String: Rule]]?
}

// The event tap, workspace observer and config reloads run on the main run loop.
@objc final class ApplicationButtonRules: NSObject {
    @objc static let shared = ApplicationButtonRules()
    private var file = FileRules(defaults: nil, applications: nil)
    private var active: [String: Rule] = [:]
    private var requestedApp: String?
    private var pressed: Set<Press> = []
    private struct Press: Hashable { let device: UInt64; let button: Int }

    @objc var enabled: Bool { !(file.defaults ?? [:]).isEmpty || !(file.applications ?? [:]).isEmpty }

    @objc func load(_ url: URL) {
        do {
            let candidate = try JSONDecoder().decode(FileRules.self, from: Data(contentsOf: url))
            let groups = [candidate.defaults ?? [:]] + Array((candidate.applications ?? [:]).values)
            guard groups.allSatisfy({ $0.keys.allSatisfy { key in
                guard let n = Int(key) else { return false }
                return (3...32).contains(n) && String(n) == key
            } }) else {
                NSLog("Invalid button number in %@", url.path)
                return
            }
            file = candidate
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            file = FileRules(defaults: nil, applications: nil)
        } catch {
            NSLog("Cannot load %@: %@", url.path, error.localizedDescription)
            return
        }
        _ = activate(requestedApp)
    }

    // Return true only when the native button table needs to be rebuilt.
    @objc func activate(_ bundleID: String?) -> Bool {
        requestedApp = bundleID
        guard pressed.isEmpty else { return false }
        let next = (file.defaults ?? [:]).merging(file.applications?[bundleID ?? ""] ?? [:]) { _, override in override }
        guard next != active else { return false }
        active = next
        return true
    }

    @objc func rows(_ base: [NSDictionary]) -> [NSDictionary] {
        guard !active.isEmpty else { return base }
        let unmodified = base.filter { row in
            let trigger = (row["trigger"] as? NSDictionary)?["button"] as? Int
            let modifiers = (row["modifiers"] as? NSDictionary)?["buttonModifiers"] as? [NSDictionary] ?? []
            let buttons = modifiers.compactMap { $0["button"] as? Int } + [trigger].compactMap { $0 }
            return buttons.allSatisfy { active[String($0)] == nil }
        }
        return unmodified + active.keys.sorted().compactMap { active[$0]?.row(button: Int($0)!) }
    }

    @objc func press(_ device: UInt64, button: Int) {
        if enabled { pressed.insert(Press(device: device, button: button)) }
    }

    @objc func passesThrough(_ button: Int) -> Bool { active[String(button)] == .passThrough }

    @objc func release(_ device: UInt64, button: Int) -> Bool {
        guard pressed.remove(Press(device: device, button: button)) != nil else { return false }
        return activate(requestedApp)
    }

    @objc func resetPresses() { pressed.removeAll() }
}

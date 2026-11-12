import Foundation

let rules = ApplicationButtonRules()
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let game = "org.example.native-input"
let unrelated: NSDictionary = ["trigger": ["button": 6], "modifiers": [:], "effect": ["type": "smartZoom"]]
let replaced: NSDictionary = ["trigger": "scrollTrigger", "modifiers": ["buttonModifiers": [["button": 3]]]]
let base = [unrelated, replaced]
precondition(rules.rows(base) == base)
rules.load(source)
precondition(rules.enabled)
let desktop = rules.rows(base)
precondition(desktop.count == 4 && desktop.contains(unrelated) && !desktop.contains(replaced))
func effect(_ rows: [NSDictionary], button: Int) -> NSDictionary? {
    rows.first { ($0["trigger"] as? NSDictionary)?["button"] as? Int == button }?["effect"] as? NSDictionary
}
precondition(effect(desktop, button: 3)?["variant"] as? Int == 32)
precondition(effect(desktop, button: 5)?["keycode"] as? Int == 12)
precondition(desktop.contains { $0["trigger"] as? String == "dragTrigger" })

rules.press(1, button: 3)
rules.press(2, button: 4)
precondition(!rules.activate(game))
precondition(!rules.release(1, button: 3))
precondition(!rules.passesThrough(3))
precondition(rules.release(2, button: 4))
precondition(rules.passesThrough(3) && !rules.passesThrough(4))
precondition(effect(rules.rows(base), button: 3) == nil)
precondition(effect(rules.rows(base), button: 5) == effect(desktop, button: 5))
rules.press(1, button: 3)
precondition(!rules.activate("com.apple.finder"))
precondition(rules.passesThrough(3))
precondition(rules.release(1, button: 3))
precondition(rules.rows(base) == desktop)

rules.press(2, button: 3)
precondition(!rules.activate(game))
precondition(rules.disconnect(2))
precondition(rules.passesThrough(3))

let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try #"{"defaults":{"3":"missionControl"},"applications":{"com.example.editor":{"3":{"keyCode":6,"flags":0}}}}"#.write(to: temp, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: temp) }
rules.load(temp)
precondition(rules.activate("com.example.editor"))
precondition(effect(rules.rows(base), button: 3)?["keycode"] as? Int == 6)
try #"{"defaults":{"2":"passThrough"}}"#.write(to: temp, atomically: true, encoding: .utf8)
rules.load(temp)
precondition(effect(rules.rows(base), button: 3)?["keycode"] as? Int == 6)
try FileManager.default.removeItem(at: temp)
rules.load(temp)
precondition(!rules.enabled && rules.rows(base) == base)
print("Passed button rule resolution, native row generation, focus changes, and config reload checks.")

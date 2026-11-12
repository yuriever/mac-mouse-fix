import Foundation

let middle: NSDictionary = ["trigger": ["button": 3, "duration": "click", "level": 1],
                            "effect": ["type": "keyboardShortcut", "keycode": 103, "flags": 8388864],
                            "modifiers": [:]]
let drag: NSDictionary = ["trigger": "dragTrigger", "effect": ["modifiedDragType": "threeFingerSwipe"],
                          "modifiers": ["buttonModifiers": [["button": 4, "level": 1]]]]
let side: NSDictionary = ["trigger": ["button": 5, "duration": "click", "level": 1], "modifiers": [:]]
let game = "example.game"
func scoped(_ row: NSDictionary, _ mode: String, _ ids: [String]) -> NSDictionary {
    let copy = row.mutableCopy() as! NSMutableDictionary
    copy["applicationScope"] = ["mode": mode, "bundleIdentifiers": ids] as [String: Any]
    return copy
}

let rules = ApplicationButtonRules()
let exceptGame = scoped(middle, "except", [game])
let onlyGame = scoped(drag, "only", [game])
rules.load([exceptGame, onlyGame, side], frontmost: "example.desktop")
precondition(rules.enabled && rules.rows == [exceptGame, side])
precondition(!rules.passesThrough(3) && rules.passesThrough(4))
rules.press(1, button: 3)
rules.press(2, button: 5)
precondition(!rules.activate(game) && !rules.release(1, button: 3))
precondition(rules.disconnect(2) && rules.rows == [onlyGame, side])
precondition(rules.passesThrough(3) && !rules.passesThrough(4) && !rules.passesThrough(5))

// Hold a native button across focus and config changes until its native up.
rules.press(1, button: 3)
precondition(!rules.activate(nil))
rules.load([middle, drag, side], frontmost: nil)
precondition(rules.passesThrough(3) && rules.release(1, button: 3))
precondition(!rules.enabled && rules.rows == [middle, drag, side])

// A scoped-out drag must never disable a separate active rule for that button.
let drag3: NSDictionary = ["trigger": "dragTrigger", "modifiers": ["buttonModifiers": [["button": 3, "level": 1]]]]
rules.load([exceptGame, drag3], frontmost: game)
precondition(!rules.passesThrough(3) && rules.rows == [drag3])
rules.load([scoped(side, "only", [])], frontmost: nil)
precondition(rules.rows.isEmpty && rules.passesThrough(5))
rules.press(1, button: 5)
rules.load([side], frontmost: game)
precondition(rules.resetPresses() && !rules.enabled && rules.rows == [side])
print("Passed rule scopes, native clicks, modifiers, focus changes, reload and disconnect checks.")

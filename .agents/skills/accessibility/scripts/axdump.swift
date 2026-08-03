// Dump de l'arbre d'accessibilité d'une app, pour mesurer ce que VoiceOver voit
// vraiment plutôt que le supposer. Usage : axdump <pid> [profondeur]
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func describe(_ element: AXUIElement) -> String {
    let role = string(element, kAXRoleAttribute) ?? "?"
    var parts = [role]
    if let sub = string(element, kAXSubroleAttribute) { parts.append("(\(sub))") }
    if let roleDesc = string(element, kAXRoleDescriptionAttribute) { parts.append("« \(roleDesc) »") }
    for (label, key) in [("desc", kAXDescriptionAttribute), ("title", kAXTitleAttribute), ("help", kAXHelpAttribute)] {
        if let v = string(element, key), v.isEmpty == false { parts.append("\(label)=\"\(v)\"") }
    }
    if attribute(element, "AXTitleUIElement") != nil { parts.append("titleUIElement=oui") }
    return parts.joined(separator: " ")
}

func walk(_ element: AXUIElement, depth: Int, maxDepth: Int) {
    print(String(repeating: "  ", count: depth) + describe(element))
    guard depth < maxDepth else { return }
    for child in children(element) {
        walk(child, depth: depth + 1, maxDepth: maxDepth)
    }
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write("NON AUTORISÉ : ce binaire n'a pas l'accès Accessibilité.\n".data(using: .utf8)!)
    exit(2)
}
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? 0
let maxDepth = Int(CommandLine.arguments.dropFirst(2).first ?? "6") ?? 6
guard pid > 0 else { FileHandle.standardError.write("usage: axdump <pid> [profondeur]\n".data(using: .utf8)!); exit(1) }
let app = AXUIElementCreateApplication(pid)
for window in (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
    print("=== FENÊTRE : \(string(window, kAXTitleAttribute) ?? "sans titre") ===")
    walk(window, depth: 0, maxDepth: maxDepth)
    print()
}

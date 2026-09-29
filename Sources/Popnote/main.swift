import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar app: no dock icon. (Info.plist sets LSUIElement too; this covers `swift run`.)
app.setActivationPolicy(.accessory)
app.run()

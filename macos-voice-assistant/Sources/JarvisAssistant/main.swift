import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

let controller = JarvisController()
let statusBar = StatusBarController(assistant: controller)
controller.attach(statusBar: statusBar)
controller.start()

app.run()

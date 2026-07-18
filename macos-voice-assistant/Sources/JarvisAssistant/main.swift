import AppKit

// Two ways to run:
//   --mcp : run as a Model Context Protocol server over stdio (for Claude Desktop etc.) so an
//           MCP client can drive the Mac through Jarvis's tools. No menu bar, no microphone.
//   (default): the wake-word voice assistant with a menu bar icon.
if CommandLine.arguments.contains("--mcp") {
    MCPServer().run() // blocking stdio loop; returns only when stdin closes
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

    let controller = JarvisController()
    let statusBar = StatusBarController(assistant: controller)
    controller.attach(statusBar: statusBar)
    controller.start()

    app.run()
}

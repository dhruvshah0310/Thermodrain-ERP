import AppKit

final class StatusBarController {
    enum State {
        case idleListening
        case capturing
        case thinking
        case speaking
        case error
    }

    private let statusItem: NSStatusItem
    private let assistant: JarvisController

    init(assistant: JarvisController) {
        self.assistant = assistant
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Jarvis idle")
        buildMenu()
    }

    func setState(_ state: State) {
        let symbol: String
        let description: String
        switch state {
        case .idleListening:
            symbol = "waveform.circle"
            description = "Jarvis idle, listening for wake word"
        case .capturing:
            symbol = "mic.circle.fill"
            description = "Jarvis capturing your command"
        case .thinking:
            symbol = "ellipsis.circle"
            description = "Jarvis thinking"
        case .speaking:
            symbol = "speaker.wave.2.circle.fill"
            description = "Jarvis speaking"
        case .error:
            symbol = "exclamationmark.circle"
            description = "Jarvis error"
        }
        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Jarvis Assistant", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let hasKey = KeychainStore.loadAPIKey() != nil
        let apiKeyItem = NSMenuItem(
            title: hasKey ? "Change Anthropic API Key… (saved)" : "Set Anthropic API Key…",
            action: #selector(setAPIKey),
            keyEquivalent: ""
        )
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)

        let shellItem = NSMenuItem(title: "Allow Shell Commands", action: #selector(toggleShell), keyEquivalent: "")
        shellItem.target = self
        shellItem.state = assistant.config.allowShellCommands ? .on : .off
        menu.addItem(shellItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = assistant.config.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let workspaceItem = NSMenuItem(title: "Reveal Workspace Folder", action: #selector(revealWorkspace), keyEquivalent: "")
        workspaceItem.target = self
        menu.addItem(workspaceItem)

        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let configItem = NSMenuItem(title: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Jarvis", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func setAPIKey() {
        // Showing a blocking modal while the recognition task keeps running has been observed to
        // leave it in a broken state, so stop listening for the duration of the dialog.
        assistant.pauseListening()
        defer { assistant.resumeListening() }

        let alert = NSAlert()
        alert.messageText = "Anthropic API Key"
        alert.informativeText = "Paste your key from console.anthropic.com. It's stored in the macOS Keychain, never written to disk in plaintext."
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKey()
        input.becomeFirstResponder()

        if alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty {
            KeychainStore.saveAPIKey(input.stringValue)
            assistant.reloadAPIKey()
            buildMenu()

            let confirmation = NSAlert()
            confirmation.messageText = "Saved"
            confirmation.informativeText = "API key stored in the Keychain."
            confirmation.runModal()
        }
    }

    @objc private func toggleShell() {
        assistant.config.allowShellCommands.toggle()
        assistant.config.save()
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        assistant.config.launchAtLogin.toggle()
        assistant.config.save()
        if assistant.config.launchAtLogin {
            LaunchAgent.install(binaryPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        } else {
            LaunchAgent.uninstall()
        }
        buildMenu()
    }

    @objc private func revealWorkspace() {
        NSWorkspace.shared.activateFileViewerSelecting([assistant.config.workspaceURL])
    }

    @objc private func openLog() {
        let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JarvisAssistant/jarvis.log")
        NSWorkspace.shared.open(logURL)
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.configFileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

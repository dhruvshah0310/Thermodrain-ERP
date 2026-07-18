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

    /// Selectable Claude models (friendly name, API model ID). Verify current IDs at
    /// https://docs.anthropic.com/en/docs/about-claude/models — you can also type any model string
    /// directly into config.json if a newer one ships before this list is updated.
    private static let availableModels: [(name: String, id: String)] = [
        ("Opus 4.8 — most capable", "claude-opus-4-8"),
        ("Opus 4.7", "claude-opus-4-7"),
        ("Opus 4.6", "claude-opus-4-6"),
        ("Sonnet 5 — fast + capable (default)", "claude-sonnet-5"),
        ("Sonnet 4.6", "claude-sonnet-4-6"),
        ("Haiku 4.5 — fastest, cheapest", "claude-haiku-4-5"),
        ("Fable 5 — most powerful (premium)", "claude-fable-5")
    ]

    init(assistant: JarvisController) {
        self.assistant = assistant
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = JarvisIcon.reactor()
        buildMenu()
    }

    func setState(_ state: State) {
        // Idle shows the Iron-Man arc-reactor glyph; the active states use expressive SF Symbols so
        // you can still read what Jarvis is doing at a glance from the menu bar.
        let image: NSImage?
        switch state {
        case .idleListening:
            image = JarvisIcon.reactor()
        case .capturing:
            image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Jarvis capturing your command")
        case .thinking:
            image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Jarvis thinking")
        case .speaking:
            image = NSImage(systemSymbolName: "speaker.wave.2.circle.fill", accessibilityDescription: "Jarvis speaking")
        case .error:
            image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Jarvis error")
        }
        DispatchQueue.main.async {
            self.statusItem.button?.image = image
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

        let conversationItem = NSMenuItem(title: "Conversation Mode (reply then keep listening)", action: #selector(toggleConversation), keyEquivalent: "")
        conversationItem.target = self
        conversationItem.state = assistant.config.conversationMode ? .on : .off
        menu.addItem(conversationItem)

        let greetItem = NSMenuItem(title: "Greet Me at Launch", action: #selector(toggleGreet), keyEquivalent: "")
        greetItem.target = self
        greetItem.state = assistant.config.greetOnLaunch ? .on : .off
        menu.addItem(greetItem)

        // Model picker submenu.
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelSubmenu = NSMenu()
        var currentIsKnown = false
        for entry in Self.availableModels {
            let item = NSMenuItem(title: entry.name, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            if entry.id == assistant.config.model {
                item.state = .on
                currentIsKnown = true
            }
            modelSubmenu.addItem(item)
        }
        // If the config holds a custom/newer model string not in the list, show it too.
        if !currentIsKnown {
            modelSubmenu.addItem(.separator())
            let custom = NSMenuItem(title: "\(assistant.config.model) (from config)", action: nil, keyEquivalent: "")
            custom.state = .on
            custom.isEnabled = false
            modelSubmenu.addItem(custom)
        }
        modelItem.submenu = modelSubmenu
        menu.addItem(modelItem)

        // Voice picker submenu (male / female).
        let voiceItem = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        let voiceSubmenu = NSMenu()
        for (label, value) in [("Male", "male"), ("Female", "female")] {
            let item = NSMenuItem(title: label, action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (assistant.config.voiceGender.lowercased() == value) ? .on : .off
            voiceSubmenu.addItem(item)
        }
        voiceItem.submenu = voiceSubmenu
        menu.addItem(voiceItem)

        let overlayItem = NSMenuItem(title: "Show Siri-style Window", action: #selector(toggleOverlay), keyEquivalent: "")
        overlayItem.target = self
        overlayItem.state = assistant.config.showOverlay ? .on : .off
        menu.addItem(overlayItem)

        let screenItem = NSMenuItem(title: "Allow Screen Control (see & click)", action: #selector(toggleScreenControl), keyEquivalent: "")
        screenItem.target = self
        screenItem.state = assistant.config.allowScreenControl ? .on : .off
        menu.addItem(screenItem)

        let fullFileItem = NSMenuItem(title: "Allow Full File Access (whole Mac)", action: #selector(toggleFullFileAccess), keyEquivalent: "")
        fullFileItem.target = self
        fullFileItem.state = assistant.config.allowFullFileAccess ? .on : .off
        menu.addItem(fullFileItem)

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
        // A menu-bar-only (accessory) app doesn't reliably receive keyboard events — including
        // Cmd+V — in a modal dialog. Temporarily become a regular foreground app so typing and
        // paste work, then drop back to accessory afterward.
        NSApp.setActivationPolicy(.regular)
        defer {
            NSApp.setActivationPolicy(.accessory)
            assistant.resumeListening()
        }

        let alert = NSAlert()
        alert.messageText = "Anthropic API Key"
        alert.informativeText = """
        Paste or type your key from console.anthropic.com. It must start with "sk-ant-". The field \
        is shown in full so you can check it's complete and typo-free. It's stored in the macOS \
        Keychain.
        """

        // Visible (not secure) field so the user can verify the whole key while debugging
        // invalid-key errors, pre-filled from the clipboard so no paste is even required.
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "sk-ant-..."
        if let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
            input.stringValue = clip
        }
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        if !key.hasPrefix("sk-ant-") {
            let warn = NSAlert()
            warn.messageText = "That doesn't look like an Anthropic API key"
            warn.informativeText = """
            Anthropic keys start with "sk-ant-". What you entered starts with \
            "\(String(key.prefix(7)))…". Double-check you copied the key value itself (not the key's \
            name or a URL) from console.anthropic.com, then try again. Saving it anyway.
            """
            warn.runModal()
        }

        KeychainStore.saveAPIKey(key)
        assistant.reloadAPIKey()
        buildMenu()

        let confirmation = NSAlert()
        confirmation.messageText = "Saved"
        confirmation.informativeText = "Key stored (\(key.count) characters). Say \"Jarvis, how are you?\" to test it."
        confirmation.runModal()
    }

    @objc private func toggleConversation() {
        assistant.config.conversationMode.toggle()
        assistant.config.save()
        buildMenu()
    }

    @objc private func toggleGreet() {
        assistant.config.greetOnLaunch.toggle()
        assistant.config.save()
        buildMenu()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        assistant.config.model = id
        assistant.config.save()
        buildMenu()
        Logger.shared.log("Model switched to \(id) (takes effect on the next command).")

        assistant.pauseListening()
        defer { assistant.resumeListening() }
        let info = NSAlert()
        info.messageText = "Model set to \(sender.title)"
        info.informativeText = "New commands will use this model. If it's a model your account can't access, you'll hear an error — pick another from the Model menu."
        info.runModal()
    }

    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        assistant.config.voiceGender = value
        // A custom voiceIdentifier would override the gender choice, so clear it when the user
        // explicitly picks male/female from the menu.
        assistant.config.voiceIdentifier = nil
        assistant.config.save()
        buildMenu()
    }

    @objc private func toggleOverlay() {
        assistant.config.showOverlay.toggle()
        assistant.config.save()
        buildMenu()
    }

    @objc private func toggleScreenControl() {
        assistant.config.allowScreenControl.toggle()
        assistant.config.save()
        buildMenu()
    }

    @objc private func toggleFullFileAccess() {
        assistant.config.allowFullFileAccess.toggle()
        assistant.config.save()
        buildMenu()
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

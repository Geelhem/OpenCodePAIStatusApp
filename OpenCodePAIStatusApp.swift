import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var timer: Timer?
    private var isServerRunning = false
    private var isInterceptorRunning = false

    private let serverPort = 3000
    private let interceptorDaemonPath = NSHomeDirectory() + "/Projects/interceptor/daemon/index.ts"
    private let refreshScriptPath = NSHomeDirectory() + "/bin/refresh-ollama-models"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "OpenCode PAI")
            button.image?.isTemplate = true
        }

        setupMenu()

        // Start checking status periodically
        checkAllStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkAllStatus()
        }

        // Auto-start on launch
        autoStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // OpenCode Server Status
        statusMenuItem = NSMenuItem(title: "OpenCode Server: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Interceptor Status
        let interceptorMenuItem = NSMenuItem(title: "Interceptor: Checking...", action: nil, keyEquivalent: "")
        interceptorMenuItem.isEnabled = false
        menu.addItem(interceptorMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh Ollama Models
        let refreshModelsItem = NSMenuItem(title: "🔄 Refresh Ollama Models", action: #selector(refreshOllamaModels), keyEquivalent: "r")
        refreshModelsItem.target = self
        menu.addItem(refreshModelsItem)

        menu.addItem(NSMenuItem.separator())

        // Start/Stop Server
        let startStopItem = NSMenuItem(title: "Start Server", action: #selector(toggleServer), keyEquivalent: "s")
        startStopItem.target = self
        menu.addItem(startStopItem)

        // Restart Server
        let restartItem = NSMenuItem(title: "Restart Server", action: #selector(restartServer), keyEquivalent: "t")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        // Open Web UI
        let openItem = NSMenuItem(title: "Open Web UI (localhost:3000)", action: #selector(openWebUI), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit OpenCode PAI", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func autoStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if !self.isServerRunning {
                self.startServer()
            }
        }
    }

    private func checkAllStatus() {
        let serverRunning = isServerRunningOnPort()
        let interceptorRunning = isInterceptorRunningCheck()

        isServerRunning = serverRunning
        isInterceptorRunning = interceptorRunning

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update server status
            if serverRunning {
                self.statusMenuItem.title = "OpenCode Server: Running (port \(self.serverPort))"
                if let button = self.statusItem.button {
                    button.image = NSImage(systemSymbolName: "cpu.fill", accessibilityDescription: "OpenCode PAI Running")
                    button.image?.isTemplate = true
                }
            } else {
                self.statusMenuItem.title = "OpenCode Server: Stopped"
                if let button = self.statusItem.button {
                    button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "OpenCode PAI Stopped")
                    button.image?.isTemplate = true
                }
            }

            // Update interceptor status (find the menu item)
            if let menu = self.statusItem.menu {
                for item in menu.items {
                    if item.title.hasPrefix("Interceptor:") {
                        if interceptorRunning {
                            item.title = "Interceptor: Running"
                        } else {
                            item.title = "Interceptor: Stopped"
                        }
                        break
                    }
                }
            }
        }
    }

    private func isServerRunningOnPort() -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", ":\(serverPort)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func isInterceptorRunningCheck() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "interceptor.*daemon"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    @objc private func refreshOllamaModels() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [refreshScriptPath]
        task.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            DispatchQueue.main.async { [weak self] in
                let alert = NSAlert()
                if task.terminationStatus == 0 {
                    alert.messageText = "✅ Ollama Models Refreshed"
                    alert.informativeText = output
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = "❌ Refresh Failed"
                    alert.informativeText = error.isEmpty ? output : error
                    alert.alertStyle = .critical
                }
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "❌ Failed to run refresh script"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func toggleServer() {
        if isServerRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    private func startServer() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let homePath = NSHomeDirectory()
            let opencodePath = "\(homePath)/.opencode/bin/opencode"

            var env = ProcessInfo.processInfo.environment
            let additionalPaths = [
                "\(homePath)/.bun/bin",
                "\(homePath)/.local/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin"
            ]
            env["PATH"] = additionalPaths.joined(separator: ":") + ":/usr/bin:/bin"
            env["HOME"] = homePath

            let task = Process()
            task.executableURL = URL(fileURLWithPath: opencodePath)
            task.arguments = ["serve", "--port", "\(self.serverPort)", "--cors"]
            task.environment = env
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
            } catch {
                // Silently fail
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.checkAllStatus()
            }
        }
    }

    private func stopServer() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-f", "opencode serve.*port \(serverPort)"]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Ignore
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAllStatus()
        }
    }

    @objc private func restartServer() {
        stopServer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.startServer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.checkAllStatus()
            }
        }
    }

    @objc private func openWebUI() {
        if let url = URL(string: "http://localhost:\(serverPort)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        setLaunchAtLogin(enabled: newState)
        sender.state = newState ? .on : .off
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.pai.opencode-status.plist"
        return FileManager.default.fileExists(atPath: launchAgentPath)
    }

    private func setLaunchAtLogin(enabled: Bool) {
        let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.pai.opencode-status.plist"
        let appPath = Bundle.main.bundlePath

        if enabled {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.pai.opencode-status</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>-a</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """

            do {
                let launchAgentsDir = NSHomeDirectory() + "/Library/LaunchAgents"
                try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
                try plistContent.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)

                let task = Process()
                task.launchPath = "/bin/launchctl"
                task.arguments = ["load", launchAgentPath]
                try task.run()
                task.waitUntilExit()
            } catch {
                // Ignore errors
            }
        } else {
            do {
                let task = Process()
                task.launchPath = "/bin/launchctl"
                task.arguments = ["unload", launchAgentPath]
                try task.run()
                task.waitUntilExit()

                try FileManager.default.removeItem(atPath: launchAgentPath)
            } catch {
                // Ignore errors
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
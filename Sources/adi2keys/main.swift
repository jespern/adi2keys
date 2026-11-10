import AppKit
import ServiceManagement
import os

private let log = Logger(subsystem: "org.noehr.adi2keys", category: "agent")

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // Start at login when running as an app bundle.
    if Bundle.main.bundleIdentifier != nil {
        do { try SMAppService.mainApp.register() } catch { log.error("login item registration failed: \(error)") }
    }

    do {
        let agent = try Agent()
        agent.start()
        withExtendedLifetime(agent) { app.run() }
    } catch {
        log.error("startup failed: \(error)")
        FileHandle.standardError.write(Data("adi2keys: \(error)\n".utf8))
        exit(1)
    }
}

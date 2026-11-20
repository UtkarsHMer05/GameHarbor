import Foundation

enum SteamInstaller {
    enum Status: Equatable {
        case notInstalled
        case installed
        case outdated(bundled: String, deployed: String)
        case steamMissing
        case foreign
    }

    struct PermissionDenied: Error {}

    static func status() -> Status {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.steamApp.path) else { return .steamMissing }
        if fm.fileExists(atPath: Paths.steamAppInjectedDylib.path),
           insertedLibraries().contains(Paths.steamAppInjectedDylib.path) {
            if let bundled = bundledDylibVersion(), let deployed = deployedDylibVersion(), bundled != deployed {
                return .outdated(bundled: bundled, deployed: deployed)
            }
            return .installed
        }
        return lsEnvironmentInsert() == nil ? .notInstalled : .foreign
    }

    static func bundledDylibVersion() -> String? {
        guard let url = Bundle.main.url(forResource: "macsteam.dylib", withExtension: "version") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deployedDylibVersion() -> String? {
        try? String(contentsOf: Paths.configDir.appendingPathComponent("dylib.version"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func install(sourceDylib: URL) throws {
        guard FileManager.default.fileExists(atPath: Paths.steamApp.path) else {
            throw StepFailure(step: "Locate Steam", detail: "/Applications/Steam.app not found.")
        }
        switch MacCrab.status() {
        case .supported: break
        case .unsupported(let version):
            throw StepFailure(step: "Check Steam version", detail: "Steam build \(version) has no matching macSteam profile. Steam was not changed.")
        case .unknown, .steamMissing:
            throw StepFailure(step: "Check Steam version", detail: "The active Steam build could not be determined. Steam was not changed.")
        }
        try ensureModifiable()
        try deploySignatures()
        try Subprocess.stopSteam()
        try updateBundle(Paths.steamApp, sourceDylib: sourceDylib)
        if let version = bundledDylibVersion() {
            try Paths.ensureDir(Paths.configDir)
            try version.write(to: Paths.configDir.appendingPathComponent("dylib.version"), atomically: true, encoding: .utf8)
        }
        registerBundle()
    }

    static func uninstall() throws {
        try ensureModifiable()
        try Subprocess.stopSteam()
        try updateBundle(Paths.steamApp, sourceDylib: nil)
        registerBundle()
    }

    // Stage and sign a full copy before touching the working Steam bundle.
    static func updateBundle(_ app: URL, sourceDylib: URL?) throws {
        let fm = FileManager.default
        let work = app.deletingLastPathComponent().appendingPathComponent(".macsteam-\(UUID().uuidString)", isDirectory: true)
        let staged = work.appendingPathComponent("Steam.app", isDirectory: true)
        let backup = work.appendingPathComponent("Steam.previous.app", isDirectory: true)
        var keepBackup = false
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { if !keepBackup { try? fm.removeItem(at: work) } }
        try fm.copyItem(at: app, to: staged)

        let plist = staged.appendingPathComponent("Contents/Info.plist")
        let original = try Data(contentsOf: plist)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var root = try PropertyListSerialization.propertyList(from: original, format: &format) as? [String: Any] else {
            throw StepFailure(step: "Read Steam configuration", detail: "Info.plist is not a dictionary.")
        }
        if root["LSEnvironment"] != nil && !(root["LSEnvironment"] is [String: Any]) {
            throw StepFailure(step: "Read Steam configuration", detail: "LSEnvironment is not a dictionary.")
        }
        var environment = root["LSEnvironment"] as? [String: Any] ?? [:]
        if environment["DYLD_INSERT_LIBRARIES"] != nil && !(environment["DYLD_INSERT_LIBRARIES"] is String) {
            throw StepFailure(step: "Read Steam configuration", detail: "The existing library list is invalid.")
        }
        let installedPath = app.appendingPathComponent("Contents/MacOS/macsteam.dylib").path
        var libraries = (environment["DYLD_INSERT_LIBRARIES"] as? String ?? "")
            .split(separator: ":").map(String.init).filter { $0 != installedPath }
        let stagedDylib = staged.appendingPathComponent("Contents/MacOS/macsteam.dylib")
        if fm.fileExists(atPath: stagedDylib.path) { try fm.removeItem(at: stagedDylib) }
        if let sourceDylib {
            try fm.copyItem(at: sourceDylib, to: stagedDylib)
            try adhocSign(stagedDylib)
            libraries.append(installedPath)
        }
        if libraries.isEmpty { environment.removeValue(forKey: "DYLD_INSERT_LIBRARIES") }
        else { environment["DYLD_INSERT_LIBRARIES"] = libraries.joined(separator: ":") }
        root["LSEnvironment"] = environment
        try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0).write(to: plist, options: .atomic)
        try adhocSign(staged.appendingPathComponent("Contents/MacOS/steam_osx"))
        try adhocSign(staged)
        let verified = Subprocess.run("/usr/bin/codesign", ["--verify", "--strict", staged.path])
        guard verified.code == 0 else { throw StepFailure(step: "Verify Steam", detail: verified.stderr) }

        try fm.moveItem(at: app, to: backup)
        do {
            try fm.moveItem(at: staged, to: app)
        } catch {
            do { try fm.moveItem(at: backup, to: app) }
            catch {
                keepBackup = true
                throw StepFailure(step: "Restore Steam", detail: "The original Steam app is at \(backup.path): \(error.localizedDescription)")
            }
            throw error
        }
    }

    static func lsEnvironmentInsert() -> String? {
        guard let data = try? Data(contentsOf: Paths.steamAppInfoPlist),
              let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let env = root["LSEnvironment"] as? [String: Any],
              let value = env["DYLD_INSERT_LIBRARIES"] as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func insertedLibraries() -> [String] {
        lsEnvironmentInsert()?.split(separator: ":").map(String.init) ?? []
    }

    static func updateBlockEnabled() -> Bool {
        guard let text = try? String(contentsOf: Paths.steamCfgRoot, encoding: .isoLatin1) else { return false }
        return updateSetting(in: text) == "enable"
    }

    private static func updateSetting(in text: String) -> String? {
        text.components(separatedBy: "\n").compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "BootStrapperInhibitUpdateOnLaunch" else { return nil }
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }.last
    }

    static func updateConfig(_ text: String, blocked: Bool) -> String {
        var lines = text.components(separatedBy: "\n").filter { line in
            let key = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return key.trimmingCharacters(in: .whitespacesAndNewlines) != "BootStrapperInhibitUpdateOnLaunch"
        }
        if blocked {
            if lines.last == "" { lines.removeLast() }
            lines.append("BootStrapperInhibitUpdateOnLaunch=enable")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func setUpdateBlock(_ blocked: Bool) throws {
        let fm = FileManager.default
        for url in [Paths.steamCfgRoot, Paths.steamCfgInner] {
            guard url == Paths.steamCfgRoot || fm.fileExists(atPath: url.deletingLastPathComponent().path) else { continue }
            let text = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .isoLatin1) : ""
            let updated = updateConfig(text, blocked: blocked)
            guard let data = updated.data(using: .isoLatin1) else { throw StepFailure(step: "Update steam.cfg", detail: "Could not encode the existing file.") }
            try Paths.ensureDir(url.deletingLastPathComponent())
            if updated.isEmpty && fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            else if !updated.isEmpty { try data.write(to: url, options: .atomic) }
        }
    }

    static func writeUpdateBlock() throws { try setUpdateBlock(true) }
    static func enableUpdateBlock() throws { try setUpdateBlock(true) }
    static func disableUpdateBlock() throws { try setUpdateBlock(false) }

    private static func adhocSign(_ url: URL) throws {
        let result = Subprocess.run("/usr/bin/codesign", ["-f", "-s", "-", url.path])
        guard result.code == 0 else { throw StepFailure(step: "Sign \(url.lastPathComponent)", detail: result.stderr) }
    }

    private static func registerBundle() {
        let tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        _ = Subprocess.run(tool, ["-f", Paths.steamApp.path])
    }

    private static func deploySignatures() throws {
        guard let source = Bundle.main.url(forResource: "signatures", withExtension: nil),
              let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw StepFailure(step: "Deploy signatures", detail: "Bundled signatures are missing.")
        }
        let fm = FileManager.default
        while let url = enumerator.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(source.path.count + 1))
            let target = Paths.signaturesDir.appendingPathComponent(relative)
            try Paths.ensureDir(target.deletingLastPathComponent())
            if fm.fileExists(atPath: target.path) {
                guard try Data(contentsOf: url) == Data(contentsOf: target) else {
                    throw StepFailure(step: "Deploy signatures", detail: "An existing profile differs: \(target.path)")
                }
            } else { try fm.copyItem(at: url, to: target) }
        }
    }

    static func ensureModifiable() throws {
        let probe = Paths.steamApp.appendingPathComponent("Contents/MacOS/.macsteam-write-probe")
        do {
            try Data().write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileWriteNoPermissionError || error.code == NSFileWriteVolumeReadOnlyError) {
            throw PermissionDenied()
        } catch { throw StepFailure(step: "Check Steam.app access", detail: error.localizedDescription) }
    }
}

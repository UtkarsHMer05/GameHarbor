// Config store
import Foundation

final class ConfigStore {
    private(set) var config = SteamPlayMacConfig()

    private let configFile: URL
    private let backupDir: URL

    init(configFile: URL = Paths.configFile, backupDir: URL = Paths.configBackupDir) {
        self.configFile = configFile
        self.backupDir = backupDir
    }

    static let headerText: String? = nil

    private static let backupsToKeep = 10
    private static let defaults = SteamPlayMacConfig(packageIds: [Paths.defaultInjectionPackage])

    func load() {
        config = (try? readConfig()) ?? Self.defaults
    }

    func mutate(_ change: (inout SteamPlayMacConfig) -> Void) throws {
        let onDisk = try readConfig()
        var next = onDisk ?? Self.defaults
        change(&next)
        try FileManager.default.createDirectory(
            at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if onDisk != nil { try backupCurrentFile() }
        try next.serialize(header: Self.headerText).write(to: configFile, atomically: true, encoding: .utf8)
        config = next
        pruneBackups(in: backupDir)
    }

    func removeApps(_ ids: [Int]) throws {
        try mutate { $0.removeApps(ids) }
    }

    func setHideWhatsNew(_ on: Bool) throws {
        try mutate { $0.hideWhatsNew = on }
    }

    // MARK: - conflict + backup internals

    private func readConfig() throws -> SteamPlayMacConfig? {
        do {
            return SteamPlayMacConfig.parse(try String(contentsOf: configFile, encoding: .utf8))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func backupCurrentFile() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let ts = Int(Date().timeIntervalSince1970)
        var dest = backupDir.appendingPathComponent("config.yaml.\(ts).bak")
        var n = 1
        while fm.fileExists(atPath: dest.path) {
            dest = backupDir.appendingPathComponent("config.yaml.\(ts)-\(n).bak")
            n += 1
        }
        try fm.copyItem(at: configFile, to: dest)
    }

    private func pruneBackups(in dir: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let backups = entries.filter {
            $0.lastPathComponent.hasPrefix("config.yaml.") && $0.pathExtension == "bak"
        }
        guard backups.count > Self.backupsToKeep else { return }
        let sorted = backups.sorted {
            let a = fileModified($0) ?? .distantPast
            let b = fileModified($1) ?? .distantPast
            if a != b { return a > b }
            return $0.lastPathComponent > $1.lastPathComponent
        }
        for old in sorted.dropFirst(Self.backupsToKeep) { try? fm.removeItem(at: old) }
    }

    private func fileModified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

// Canonical filesystem locations shared by the dylib and this app.

import Foundation

enum Paths {
    static var configDir: URL {
        configDirectory(in: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func configDirectory(in home: URL) -> URL {
        let files = FileManager.default
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let current = support.appendingPathComponent("SteamPlayMac", isDirectory: true)
        let legacy = support.appendingPathComponent("macsteam", isDirectory: true)
        if !files.fileExists(atPath: current.path), files.fileExists(atPath: legacy.path) {
            do {
                try files.moveItem(at: legacy, to: current)
            } catch {
                if !files.fileExists(atPath: current.path) { return legacy }
            }
        }
        return current
    }

    static var configFile: URL {
        configDir.appendingPathComponent("config.yaml")
    }

    static var configBackupDir: URL {
        configDir.appendingPathComponent("backups", isDirectory: true)
    }

    static var signaturesDir: URL {
        configDir.appendingPathComponent("signatures", isDirectory: true)
    }

    static var steamRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
    }

    static var depotCache: URL {
        steamRoot.appendingPathComponent("depotcache", isDirectory: true)
    }

    static var steamApp: URL {
        URL(fileURLWithPath: "/Applications/Steam.app", isDirectory: true)
    }
    static var steamAppExecutable: URL {
        steamApp.appendingPathComponent("Contents/MacOS/steam_osx")
    }
    static var steamAppInfoPlist: URL {
        steamApp.appendingPathComponent("Contents/Info.plist")
    }
    static var steamAppInjectedDylib: URL {
        steamApp.appendingPathComponent("Contents/MacOS/SteamPlayMac.dylib")
    }

    static var innerClientMacOS: URL {
        steamRoot.appendingPathComponent("Steam.AppBundle/Steam/Contents/MacOS", isDirectory: true)
    }

    static var packageDir: URL {
        innerClientMacOS.appendingPathComponent("package", isDirectory: true)
    }

    static var steamCfgRoot: URL {
        steamRoot.appendingPathComponent("steam.cfg")
    }
    static var steamCfgInner: URL {
        innerClientMacOS.appendingPathComponent("steam.cfg")
    }

    static let defaultInjectionPackage = 20200

    static func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

import Foundation
import CryptoKit

@main
struct SafetyChecks {
    static func main() throws {
        let fm = FileManager.default
        let args = CommandLine.arguments
        precondition(args.count == 3 || args.count == 4)
        let root = fm.temporaryDirectory.appendingPathComponent("steamplaymac-safety-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let legacyConfig = root.appendingPathComponent("Library/Application Support/macsteam")
        try fm.createDirectory(at: legacyConfig, withIntermediateDirectories: true)
        try "original".write(to: legacyConfig.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let config = Paths.configDirectory(in: root)
        precondition(config.lastPathComponent == "SteamPlayMac" && !fm.fileExists(atPath: legacyConfig.path))
        let migrated = try String(contentsOf: config.appendingPathComponent("config.yaml"), encoding: .utf8)
        precondition(migrated == "original" && Paths.configDirectory(in: root) == config)

        let package = root.appendingPathComponent("Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/package")
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        func put(_ name: String, _ value: String) throws {
            try value.write(to: package.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func checkBuild(_ expected: String?) {
            precondition(MacCrab.detectedVersion(packageDir: package) == expected)
            let c = Subprocess.run(args[1], [root.path])
            precondition(c.code == 0 && c.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == (expected ?? "0"))
        }
        checkBuild(nil)
        try put("steam_client_osx.manifest", "\"version\" \"111\"\n")
        checkBuild("111")
        try put("beta", "publicbeta")
        checkBuild(nil)
        try put("steam_client_publicbeta_osx.manifest", "\"version\" \"222\"\n")
        checkBuild("222")
        try put("steam_client_publicbeta_osx.manifest", "\"version\" \"oops\"\n")
        try put("steam_client_publicbeta_signed-2_osx.manifest", "\"version\" \"223\"\n")
        checkBuild(nil)
        try fm.removeItem(at: package.appendingPathComponent("steam_client_publicbeta_osx.manifest"))
        checkBuild("223")
        try put("steam_client_publicbeta_osx.manifest", "\"version\" \"222\"\n")
        try put("steam_client_publicbeta_osx.installed", "legacy")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: package.appendingPathComponent("steam_client_publicbeta_osx.installed").path)
        try put("steam_client_publicbeta_signed-2_osx.installed", "current")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: package.appendingPathComponent("steam_client_publicbeta_signed-2_osx.installed").path)
        checkBuild("223")
        try put("steam_client_publicbeta_signed-2_osx.manifest", "\"version\" \"oops\"\n")
        checkBuild(nil)
        try put("steam_client_publicbeta_signed-2_osx.manifest", "\"version\" \"223\"\n")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 300)], ofItemAtPath: package.appendingPathComponent("steam_client_publicbeta_osx.installed").path)
        checkBuild("222")
        try put("beta", "../invalid")
        checkBuild(nil)

        let signatures = root.appendingPathComponent("signatures")
        try fm.createDirectory(at: signatures, withIntermediateDirectories: true)
        try "{\"steam_build\":\"223\"}".write(to: signatures.appendingPathComponent("223.json"), atomically: true, encoding: .utf8)
        precondition(MacCrab.supports(version: "223", in: signatures))
        precondition(!MacCrab.supports(version: "224", in: signatures))
        precondition(!MacCrab.supports(version: "../223", in: signatures))

        let thin = Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01, 1, 2, 3, 4])
        let digest = SHA256.hash(data: thin).map { String(format: "%02x", $0) }.joined()
        let client = root.appendingPathComponent("client.dylib")
        try thin.write(to: client)
        try "{\"steam_build\":\"223\",\"steamclient_sha256_arm64\":\"\(digest)\"}".write(to: signatures.appendingPathComponent("223.json"), atomically: true, encoding: .utf8)
        precondition(MacCrab.supports(version: "223", in: signatures, client: client))
        precondition(!MacCrab.supports(version: "223", in: signatures))
        var fat = Data()
        func word(_ value: UInt32) { fat.append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
        word(0xcafebabe); word(2)
        word(0x01000007); word(0); word(0); word(0); word(0)
        word(0x0100000c); word(0); word(48); word(UInt32(thin.count)); word(0)
        fat.append(thin)
        try fat.write(to: client)
        precondition(MacCrab.supports(version: "223", in: signatures, client: client))
        fat[fat.count - 1] ^= 1
        try fat.write(to: client)
        precondition(!MacCrab.supports(version: "223", in: signatures, client: client))
        try Data([0xca, 0xfe, 0xba, 0xbe]).write(to: client)
        precondition(!MacCrab.supports(version: "223", in: signatures, client: client))
        if args.count == 4 {
            let liveClient = URL(fileURLWithPath: args[3])
            let version = MacCrab.detectedVersion(packageDir: liveClient.deletingLastPathComponent().appendingPathComponent("package"))!
            precondition(MacCrab.supports(version: version, in: URL(fileURLWithPath: "signatures/macos.arm64"), client: liveClient))
        }

        let manifestSource = root.appendingPathComponent("incoming")
        let manifestDest = root.appendingPathComponent("depotcache")
        try fm.createDirectory(at: manifestSource, withIntermediateDirectories: true)
        try fm.createDirectory(at: manifestDest, withIntermediateDirectories: true)
        let incoming = manifestSource.appendingPathComponent("123.manifest")
        let existing = manifestDest.appendingPathComponent("123.manifest")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        try "different".write(to: incoming, atomically: true, encoding: .utf8)
        do { _ = try ZipImporter.copyManifests([incoming], into: manifestDest); preconditionFailure("existing manifest replaced") }
        catch { let text = try String(contentsOf: existing, encoding: .utf8); precondition(text == "existing") }
        try "existing".write(to: incoming, atomically: true, encoding: .utf8)
        let alreadyPresent = try ZipImporter.copyManifests([incoming], into: manifestDest)
        precondition(alreadyPresent == 0)
        let newManifest = manifestSource.appendingPathComponent("456.manifest")
        try "new".write(to: newManifest, atomically: true, encoding: .utf8)
        let copied = try ZipImporter.copyManifests([newManifest], into: manifestDest)
        precondition(copied == 1)
        let copiedText = try String(contentsOf: manifestDest.appendingPathComponent("456.manifest"), encoding: .utf8)
        precondition(copiedText == "new")

        let cfg = "OtherSetting=value\nBootStrapperInhibitUpdateOnLaunch=enable\nLastSetting=2\n"
        let unblocked = SteamInstaller.updateConfig(cfg, blocked: false)
        precondition(unblocked == "OtherSetting=value\nLastSetting=2\n")
        precondition(SteamInstaller.updateConfig(unblocked, blocked: true).contains("OtherSetting=value\nLastSetting=2\nBootStrapperInhibitUpdateOnLaunch=enable\n"))

        let app = root.appendingPathComponent("Steam.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/usr/bin/true", toPath: macos.appendingPathComponent("steam_osx").path)
        let notproton = macos.appendingPathComponent("notproton.dylib")
        try fm.copyItem(atPath: args[2], toPath: notproton.path)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let legacy = macos.appendingPathComponent("macsteam.dylib")
        try fm.copyItem(atPath: args[2], toPath: legacy.path)
        let env: [String: Any] = ["DYLD_INSERT_LIBRARIES": "\(legacy.path):\(notproton.path)", "SDL_JOYSTICK_BLACKLIST_DEVICES": "keep"]
        let info: [String: Any] = ["CFBundleIdentifier": "example.steam.test", "CFBundleExecutable": "steam_osx", "LSEnvironment": env]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        func readEnv() throws -> [String: Any] {
            let root = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
            return root["LSEnvironment"] as! [String: Any]
        }
        let payload = URL(fileURLWithPath: args[2])
        try SteamInstaller.updateBundle(app, sourceDylib: payload)
        var result = try readEnv()
        let own = macos.appendingPathComponent("SteamPlayMac.dylib").path
        precondition(result["DYLD_INSERT_LIBRARIES"] as? String == "\(own):\(notproton.path)")
        precondition(result["SDL_JOYSTICK_BLACKLIST_DEVICES"] as? String == "keep")
        precondition(!fm.fileExists(atPath: legacy.path))
        precondition(fm.fileExists(atPath: notproton.path) && fm.fileExists(atPath: own))
        try SteamInstaller.updateBundle(app, sourceDylib: payload)
        result = try readEnv()
        precondition(result["DYLD_INSERT_LIBRARIES"] as? String == "\(own):\(notproton.path)")
        try SteamInstaller.updateBundle(app, sourceDylib: nil)
        result = try readEnv()
        precondition(result["DYLD_INSERT_LIBRARIES"] as? String == notproton.path)
        precondition(fm.fileExists(atPath: notproton.path) && !fm.fileExists(atPath: own))

        try fm.removeItem(at: macos.appendingPathComponent("steam_osx"))
        let before = try Data(contentsOf: plist)
        do { try SteamInstaller.updateBundle(app, sourceDylib: payload); preconditionFailure("invalid bundle accepted") }
        catch { let after = try Data(contentsOf: plist); precondition(after == before) }
        precondition(fm.fileExists(atPath: notproton.path) && !fm.fileExists(atPath: own))
        print("Steam build detection, profile checks, settings preservation, staged install/uninstall and rollback passed")
    }
}

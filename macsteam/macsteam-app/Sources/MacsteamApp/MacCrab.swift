import Foundation
import CryptoKit

enum MacCrab {
    enum Status: Equatable {
        case supported
        case unsupported(String)
        case unknown
        case steamMissing
    }

    static func status() -> Status {
        guard FileManager.default.fileExists(atPath: Paths.packageDir.path) else { return .steamMissing }
        guard let version = detectedVersion() else { return .unknown }
        let signatures = Bundle.main.resourceURL?.appendingPathComponent("signatures/macos.arm64")
        let client = Paths.innerClientMacOS.appendingPathComponent("steamclient.dylib")
        return signatures.map { supports(version: version, in: $0, client: client) } == true
            ? .supported : .unsupported(version)
    }

    static func detectedVersion(packageDir: URL = Paths.packageDir) -> String? {
        let beta = (try? String(contentsOf: packageDir.appendingPathComponent("beta"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard beta.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 45 }) else { return nil }
        let prefix = beta.isEmpty ? "steam_client" : "steam_client_\(beta)"
        var suffixes = ["_osx.manifest", "_signed-2_osx.manifest", "_signed_osx.manifest"]
        // Steam leaves older signing-channel manifests behind after an update.
        let installed = suffixes.compactMap { suffix -> (String, Date)? in
            let marker = packageDir.appendingPathComponent(prefix + suffix.replacingOccurrences(of: ".manifest", with: ".installed"))
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: marker.path),
                  let date = attrs[.modificationDate] as? Date else { return nil }
            return (suffix, date)
        }.max { $0.1 < $1.1 }
        if let installed { suffixes = [installed.0] }
        for suffix in suffixes {
            guard let text = try? String(contentsOf: packageDir.appendingPathComponent(prefix + suffix), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "\"", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if parts.count == 2, parts[0] == "version", !parts[1].isEmpty,
                   parts[1].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) { return parts[1] }
            }
            return nil
        }
        return nil
    }

    static func supports(version: String, in signatures: URL, client: URL? = nil) -> Bool {
        guard !version.isEmpty, version.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let data = try? Data(contentsOf: signatures.appendingPathComponent("\(version).json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        guard String(describing: json["steam_build"] ?? "") == version else { return false }
        guard let expected = json["steamclient_sha256_arm64"] as? String else { return true }
        guard expected.count == 64, let client, let actual = arm64Hash(client) else { return false }
        return actual == expected.lowercased()
    }

    private static func arm64Hash(_ client: URL) -> String? {
        guard let data = try? Data(contentsOf: client, options: .mappedIfSafe) else { return nil }
        func number(_ offset: Int, _ length: Int) -> UInt64? {
            guard offset >= 0, length <= 8, offset <= data.count, length <= data.count - offset else { return nil }
            return data[offset..<(offset + length)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        guard let magic = number(0, 4) else { return nil }
        var slice: Range<Int>?
        if magic == 0xcffaedfe, number(4, 4) == 0x0c000001 {
            slice = 0..<data.count
        } else if magic == 0xcafebabe || magic == 0xcafebabf {
            let wide = magic == 0xcafebabf
            let stride = wide ? 32 : 20
            guard data.count >= 8 else { return nil }
            guard let count = number(4, 4), count <= UInt64((data.count - 8) / stride) else { return nil }
            for index in 0..<Int(count) {
                let base = 8 + index * stride
                guard number(base, 4) == 0x0100000c else { continue }
                let width = wide ? 8 : 4
                guard let start = number(base + 8, width), let size = number(base + 8 + width, width),
                      start <= UInt64(data.count), size > 0, size <= UInt64(data.count) - start else { return nil }
                slice = Int(start)..<Int(start + size)
                break
            }
        }
        guard let slice else { return nil }
        return SHA256.hash(data: data[slice]).map { String(format: "%02x", $0) }.joined()
    }
}

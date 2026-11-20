import Foundation

enum ManifestFetcher {
    struct Report: Sendable {
        var fetched = 0
        var unavailable = 0
    }

    private static let archive = URL(string: "https://manifest.luastools.xyz/m")!
    private static let maxBytes = 64 * 1024 * 1024
    private static let maxRefs = 512

    static func fetch(_ refs: [LuaManifestRef], into directory: URL = Paths.depotCache,
                      session: URLSession = .shared) async -> Report {
        var report = Report()
        var seen = Set<LuaManifestRef>()
        let unique = refs.filter { seen.insert($0).inserted }
        report.unavailable = max(0, unique.count - maxRefs)
        let selected = Array(unique.prefix(maxRefs))
        return await withTaskGroup(of: Result.self, returning: Report.self) { group in
            var next = 0
            while next < min(4, selected.count) {
                let ref = selected[next]
                group.addTask { await fetchOne(ref, into: directory, session: session) }
                next += 1
            }
            while let result = await group.next() {
                if result == .fetched { report.fetched += 1 }
                if result == .unavailable { report.unavailable += 1 }
                if next < selected.count {
                    let ref = selected[next]
                    group.addTask { await fetchOne(ref, into: directory, session: session) }
                    next += 1
                }
            }
            return report
        }
    }

    private enum Result { case fetched, present, unavailable }
    private enum FetchError: Error { case invalid, tooLarge }

    private static func fetchOne(_ ref: LuaManifestRef, into directory: URL,
                                 session: URLSession) async -> Result {
        guard ref.depotID > 0, ref.depotID <= Int(UInt32.max),
              let gid = UInt64(ref.manifestGID), gid > 0 else { return .unavailable }
        let name = "\(ref.depotID)_\(gid).manifest"
        let dest = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            return validExisting(dest, ref: ref) ? .present : .unavailable
        }

        do {
            let url = archive.appendingPathComponent(String(ref.depotID))
                .appendingPathComponent(String(gid))
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.setValue("macSteam/1.0", forHTTPHeaderField: "User-Agent")
            let (stream, response) = try await session.bytes(for: request)
            defer { stream.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.url?.scheme?.lowercased() == "https",
                  response.expectedContentLength <= Int64(maxBytes) else { return .unavailable }
            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in stream {
                guard data.count < maxBytes else { throw FetchError.tooLarge }
                data.append(byte)
            }
            guard matches(data, ref: ref) else { throw FetchError.invalid }

            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("macsteam-manifest-\(UUID().uuidString)", isDirectory: true)
            try Paths.ensureDir(temp)
            defer { try? FileManager.default.removeItem(at: temp) }
            let staged = temp.appendingPathComponent(name)
            try data.write(to: staged, options: .atomic)
            return try ZipImporter.copyManifests([staged], into: directory) > 0 ? .fetched : .present
        } catch {
            return .unavailable
        }
    }

    private static func validExisting(_ url: URL, ref: LuaManifestRef) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              v.isRegularFile == true, v.isSymbolicLink != true,
              let size = v.fileSize, size > 0, size <= maxBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return matches(data, ref: ref)
    }

    // The metadata IDs must match the requested depot and version before caching.
    static func matches(_ data: Data, ref: LuaManifestRef) -> Bool {
        guard let gid = UInt64(ref.manifestGID), ref.depotID > 0 else { return false }
        var cursor = 0
        var payload = false, metadata = false, signature = false
        while let magic = word(data, &cursor) {
            if magic == 0x32c415ab {
                return cursor == data.count && payload && metadata && signature
            }
            guard let size = word(data, &cursor), Int(size) <= data.count - cursor else { return false }
            let end = cursor + Int(size)
            switch magic {
            case 0x71f617d0:
                guard !payload, size > 0 else { return false }
                payload = true
            case 0x1f4812be:
                guard !metadata, metadataMatches(data, start: cursor, end: end,
                                                 depot: UInt64(ref.depotID), gid: gid) else { return false }
                metadata = true
            case 0x1b81b817:
                guard !signature else { return false }
                signature = true
            default: return false
            }
            cursor = end
        }
        return false
    }

    private static func word(_ data: Data, _ cursor: inout Int) -> UInt32? {
        guard cursor <= data.count, data.count - cursor >= 4 else { return nil }
        let value = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(data[cursor + $1]) << (8 * $1)) }
        cursor += 4
        return value
    }

    private static func varint(_ data: Data, _ cursor: inout Int, end: Int) -> UInt64? {
        var value: UInt64 = 0
        for index in 0..<10 {
            guard cursor < end else { return nil }
            let byte = data[cursor]
            cursor += 1
            if index == 9 && byte > 1 { return nil }
            value |= UInt64(byte & 0x7f) << (index * 7)
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }

    private static func metadataMatches(_ data: Data, start: Int, end: Int,
                                        depot: UInt64, gid: UInt64) -> Bool {
        var cursor = start
        var foundDepot: UInt64?, foundGID: UInt64?
        while cursor < end {
            guard let tag = varint(data, &cursor, end: end), tag >> 3 > 0 else { return false }
            let field = tag >> 3
            switch tag & 7 {
            case 0:
                guard let value = varint(data, &cursor, end: end) else { return false }
                if field == 1 {
                    guard foundDepot == nil else { return false }
                    foundDepot = value
                } else if field == 2 {
                    guard foundGID == nil else { return false }
                    foundGID = value
                }
            case 1:
                guard end - cursor >= 8 else { return false }
                cursor += 8
            case 2:
                guard let size = varint(data, &cursor, end: end), size <= UInt64(end - cursor) else { return false }
                cursor += Int(size)
            case 5:
                guard end - cursor >= 4 else { return false }
                cursor += 4
            default: return false
            }
        }
        return foundDepot == depot && foundGID == gid
    }
}

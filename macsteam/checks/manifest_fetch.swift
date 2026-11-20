import Foundation

final class StubManifestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        Self.lock.unlock()
        let parts = request.url!.pathComponents
        let depot = Int(parts[parts.count - 2])!
        let gid = UInt64(parts.last!)!
        let status = depot == 404 ? 404 : 200
        let body = manifest(depot: depot == 102 ? 999 : depot, gid: gid)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func varint(_ input: UInt64) -> [UInt8] {
    var value = input, bytes: [UInt8] = []
    while value >= 128 {
        bytes.append(UInt8(value & 127) | 128)
        value >>= 7
    }
    bytes.append(UInt8(value))
    return bytes
}

private func manifest(depot: Int, gid: UInt64) -> Data {
    var data = Data()
    func word(_ n: UInt32) {
        for i in 0..<4 { data.append(UInt8(truncatingIfNeeded: n >> (8 * i))) }
    }
    let metadata = [UInt8(8)] + varint(UInt64(depot)) + [UInt8(16)] + varint(gid)
    word(0x71f617d0); word(2); data.append(contentsOf: [0x0a, 0])
    word(0x1f4812be); word(UInt32(metadata.count)); data.append(contentsOf: metadata)
    word(0x1b81b817); word(0)
    word(0x32c415ab)
    return data
}

@main
struct ManifestFetchChecks {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("macsteam-fetch-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubManifestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let good = LuaManifestRef(depotID: 101, manifestGID: "1001")
        let wrong = LuaManifestRef(depotID: 102, manifestGID: "1002")
        let missing = LuaManifestRef(depotID: 404, manifestGID: "1004")
        let existing = LuaManifestRef(depotID: 103, manifestGID: "1003")
        let original = Data("do not overwrite".utf8)
        try original.write(to: root.appendingPathComponent("103_1003.manifest"))

        let lua = root.appendingPathComponent("game.lua")
        try "addappid(100)\nsetManifestid(101, \"1001\")\n".write(to: lua, atomically: true, encoding: .utf8)
        let plan = try ZipImporter.buildPlan(fromLua: lua)
        precondition(plan.mainAppID == 100 && plan.manifestRefs == [good])

        let valid = manifest(depot: 101, gid: 1001)
        precondition(ManifestFetcher.matches(valid, ref: good))
        precondition(!ManifestFetcher.matches(valid.dropLast(), ref: good))
        precondition(!ManifestFetcher.matches(valid, ref: wrong))
        var corrupt = valid
        corrupt[4] = 255
        precondition(!ManifestFetcher.matches(corrupt, ref: good))

        let report = await ManifestFetcher.fetch([good, good, wrong, missing, existing],
                                                 into: root, session: session)
        precondition(report.fetched == 1 && report.unavailable == 3)
        precondition(StubManifestProtocol.requests == 3)
        let fetched = try Data(contentsOf: root.appendingPathComponent("101_1001.manifest"))
        let preserved = try Data(contentsOf: root.appendingPathComponent("103_1003.manifest"))
        precondition(fetched == valid && preserved == original)
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("102_1002.manifest").path))
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("404_1004.manifest").path))
        let again = await ManifestFetcher.fetch([good], into: root, session: session)
        precondition(again.fetched == 0 && again.unavailable == 0 && StubManifestProtocol.requests == 3)
        print("Manifest import and fetching checks passed: Lua references, valid, missing, malformed, duplicates and preserved existing files.")
    }
}

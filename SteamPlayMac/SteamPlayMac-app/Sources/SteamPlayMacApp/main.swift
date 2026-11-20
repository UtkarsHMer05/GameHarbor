import AppKit

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--cache-manifest" {
    guard let depot = Int(CommandLine.arguments[2]), depot > 0, depot <= Int(UInt32.max),
          let gid = UInt64(CommandLine.arguments[3]), gid > 0 else { exit(2) }
    Task.detached {
        let report = await ManifestFetcher.fetch([LuaManifestRef(depotID: depot, manifestGID: String(gid))])
        exit(report.unavailable == 0 ? 0 : 1)
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
if #available(macOS 14, *) {
    app.activate()
} else {
    app.activate(ignoringOtherApps: true)
}
app.run()

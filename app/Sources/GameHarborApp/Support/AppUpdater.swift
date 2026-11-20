import Foundation
import Sparkle

@MainActor
final class AppUpdater {

    private let controller: SPUStandardUpdaterController?
    var isConfigured: Bool { controller != nil }

    init() {
        #if DEBUG
        controller = nil
        #else
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feed.isEmpty,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty
        else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    func check() {
        controller?.checkForUpdates(nil)
    }
}

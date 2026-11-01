import Foundation

/// hyprmac — github.com/kcarroll88/hyprmac, hyprland.conf benzeri sözdizimi
final class HyprmacModule: AppModule {
    init() {
        super.init(id: "hyprmac", name: "hyprmac", kind: .wm, badge: "H", symbol: "rectangle.3.group",
                   bundleID: "dev.keenancarroll.wispos", appPath: "/Applications/hyprmac.app",
                   installHint: "github.com/kcarroll88/hyprmac → Releases'tan .dmg")
    }

    override var configPath: URL? { homeURL(".config/wisp/hyprmac.conf") }
}

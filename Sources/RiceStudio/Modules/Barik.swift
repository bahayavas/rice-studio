import Foundation

/// Barik — config ~/.barik-config.toml (ya da ~/.config/barik/config.toml); ilk açılışta kendisi oluşturur
final class BarikModule: AppModule {
    init() {
        super.init(id: "barik", name: "Barik", kind: .bar, badge: "BK", symbol: "rectangle.topthird.inset.filled",
                   bundleID: "Pansy.Barik", appPath: "/Applications/Barik.app",
                   installHint: "brew install --cask mocki-toki/formulae/barik")
    }

    override var configPath: URL? {
        let alt = homeURL(".config/barik/config.toml")
        return FileManager.default.fileExists(atPath: alt.path) ? alt : homeURL(".barik-config.toml")
    }
}

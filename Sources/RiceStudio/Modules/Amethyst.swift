import Foundation

/// Amethyst — ayarlar `com.amethyst.Amethyst` defaults domain'inde; ~/.config/amethyst/amethyst.yml
/// içindeki anahtarlar onları geçersiz kılar. Amethyst yml'i yalnızca açılışta okur.
final class AmethystModule: AppModule {
    init() {
        super.init(id: "amethyst", name: "Amethyst", kind: .wm, badge: "M", symbol: "rectangle.split.3x1",
                   bundleID: "com.amethyst.Amethyst", appPath: "/Applications/Amethyst.app",
                   installHint: "brew install --cask amethyst")
    }

    override var configPath: URL? { homeURL(".config/amethyst/amethyst.yml") }
}

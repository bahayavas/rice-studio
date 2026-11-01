import Foundation

/// Zebar — config klasörü ~/.glzr/zebar/ (settings.json: açılışta başlayacak widget pack'leri)
final class ZebarModule: AppModule {
    init() {
        super.init(id: "zebar", name: "Zebar", kind: .bar, badge: "ZB", symbol: "rectangle.on.rectangle",
                   bundleID: "com.glzr.zebar", appPath: "/Applications/Zebar.app",
                   installHint: "github.com/glzr-io/zebar → Releases'tan .dmg")
    }

    static let dir = homeURL(".glzr/zebar")

    override var configPath: URL? { Self.dir.appendingPathComponent("settings.json") }
    override var backupPaths: [URL] { [Self.dir] }

    override func validateConfig(_ text: String) -> ValidationResult {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8))
            return .valid
        } catch {
            return .invalid("settings.json geçerli JSON değil: \(error.localizedDescription)")
        }
    }
}

import Foundation

/// Tüm modüller. Yeni bir modül: dosyasını yaz, buraya bir satır ekle. Sıra = varsayılan sidebar ve kısayol sırası.
enum Registry {
    static let all: [RiceModule] = [
        AeroSpaceModule(),
        AmethystModule(),
        HyprmacModule(),
        SketchyBarModule(),
        BarikModule(),
        SimpleBarModule(),
        UbersichtModule(),
        ZebarModule(),
        BordersModule(),
    ]

    static func module(_ id: String) -> RiceModule? { all.first { $0.id == id } }
    static func modules(_ kind: ModuleKind) -> [RiceModule] { all.filter { $0.kind == kind } }
}

extension RiceModule {
    /// Aynı süreci paylaşan modüller (simple-bar + Übersicht) aynı grupta: biri seçilince diğeri kapatılmaz
    var processGroup: String { self is UbersichtFamily ? "ubersicht" : id }
}

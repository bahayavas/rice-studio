import Foundation

/// `rice` komutu — uygulama binary'sinin kendisi (rice → …/Rice Studio.app/Contents/MacOS/RiceStudio symlink'i).
enum CLI {
    static let usage = """
    kullanım: rice <komut>

      rice status                  aktif WM, bar ve tüm modüllerin durumu
      rice wm <id|none|next>       pencere yöneticisi seç (diğerleri kapanır)
      rice bar <id|none|next>      bar seç (diğerleri kapanır, menü barı ayarlanır)
      rice off                     WM ve barı kapat (normal macOS)
      rice start|stop|restart <id> tek modül
      rice reload <id>             config'i yeniden yükle (çalışıyorsa)
      rice restore                 kayıtlı WM + barı geri yükle
      rice config <id>             config dosyasının yolu
      rice profile <ad>            profili uygula (aşama 5)
      rice list                    modül id'leri

    WM: \(Registry.modules(.wm).map(\.id).joined(separator: ", "))
    Bar: \(Registry.modules(.bar).map(\.id).joined(separator: ", "))
    Ekstra: \(Registry.modules(.extra).map(\.id).joined(separator: ", "))
    """

    static let commands: Set<String> = ["status", "wm", "bar", "off", "start", "stop", "restart", "reload",
                                        "restore", "config", "profile", "list", "help", "-h", "--help"]

    /// argv'den CLI modunda mı çalışıyoruz: `rice …` adıyla çağrıldıysa ya da ilk argüman bir komutsa
    static func isCLI(_ args: [String]) -> Bool {
        (args.first.map { ($0 as NSString).lastPathComponent } == "rice") || (args.count > 1 && commands.contains(args[1]))
    }

    static func main(_ args: [String]) -> Int32 {
        Log.echo = true
        Log.trim()
        let a = Array(args.dropFirst())
        do {
            switch (a.first ?? "help", a.count) {
            case ("status", _):
                printStatus()
            case ("list", _):
                for m in Registry.all { print("\(m.id)\t\(m.kind.rawValue)\t\(m.name)") }
            case ("wm", 2), ("bar", 2):
                let kind: ModuleKind = a[0] == "wm" ? .wm : .bar
                if a[1] == "next" {
                    print(try Engine.next(kind))
                } else {
                    let r = try Engine.switchTo(kind, a[1])
                    print(r == .alreadyActive ? "\(a[1]) zaten aktif" : "aktif: \(a[1])")
                }
            case ("off", _):
                try Engine.stopAll()
            case ("start", 2): try Engine.start(a[1])
            case ("stop", 2): try Engine.stop(a[1])
            case ("restart", 2): try Engine.restart(a[1])
            case ("reload", 2):
                guard let m = Registry.module(a[1]) else { throw RiceError.unknownModule(a[1]) }
                try m.reload()
            case ("restore", _):
                try Engine.restore()
            case ("config", 2):
                guard let m = Registry.module(a[1]) else { throw RiceError.unknownModule(a[1]) }
                print(m.configPath?.path ?? "(yok)")
            case ("profile", 2):
                throw RiceError.failed("profiller aşama 5'te geliyor")
            default:
                print(usage)
                return a.isEmpty || ["help", "-h", "--help"].contains(a[0]) ? 0 : 1
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("rice: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    static func printStatus() {
        let s = RiceState.load()
        print("WM:  \(Engine.activeID(.wm))   (kayıtlı: \(s.wm))")
        print("Bar: \(Engine.activeID(.bar))   (kayıtlı: \(s.bar))")
        if let p = s.profile { print("Profil: \(p)") }
        print("Menü barı otomatik gizli: \(Engine.menuBarHidden.map { $0 ? "evet" : "hayır" } ?? "ayarsız")")
        print("")
        for kind in ModuleKind.allCases {
            print(kind.title)
            for m in Registry.modules(kind) {
                let st = m.status
                let mark = st == .running ? "●" : (st == .stopped ? "○" : "✗")
                let pad = m.name.padding(toLength: 14, withPad: " ", startingAt: 0)
                var line = "  \(mark) \(pad) \(st.label)"
                if st == .notInstalled { line += "  → \(m.installHint)" }
                print(line)
            }
        }
    }
}

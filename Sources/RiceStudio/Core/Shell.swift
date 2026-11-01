import AppKit
import Darwin

/// Dış komutlar ve süreç yönetimi. Modüller shell'e doğrudan değil, buradan dokunur.
enum Shell {
    /// Uygulama launchd'den açılınca PATH çıplak gelir; brew araçları (sketchybar eklentileri, aerospace CLI) burada
    static let path = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    struct Result {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
        /// Hata mesajı için: stderr, yoksa stdout'un son satırı
        var message: String {
            let e = err.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? out.trimmingCharacters(in: .whitespacesAndNewlines) : e
        }
    }

    /// Komutu çalıştırıp bitmesini bekler. timeout aşılırsa TERM gönderilir (status 124).
    @discardableResult
    static func run(_ exe: String, _ args: [String] = [], input: String? = nil, timeout: TimeInterval = 15) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe.hasPrefix("/") ? exe : "/usr/bin/env")
        p.arguments = exe.hasPrefix("/") ? args : [exe] + args
        p.environment = environment
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        if let input {
            let inp = Pipe()
            p.standardInput = inp
            inp.fileHandleForWriting.write(Data(input.utf8))
            try? inp.fileHandleForWriting.close()
        } else {
            p.standardInput = FileHandle.nullDevice
        }
        do { try p.run() } catch { return Result(status: -1, out: "", err: "\(exe) çalıştırılamadı: \(error.localizedDescription)") }
        // Boruları süreç bitmeden oku: dolarsa süreç takılır
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        var timedOut = false
        if p.isRunning { p.terminate(); timedOut = true }
        p.waitUntilExit()
        _ = group.wait(timeout: .now() + 2)
        return Result(status: timedOut ? 124 : p.terminationStatus,
                      out: String(decoding: outData, as: UTF8.self), err: String(decoding: errData, as: UTF8.self))
    }

    static func sh(_ script: String, timeout: TimeInterval = 15) -> Result { run("/bin/sh", ["-c", script], timeout: timeout) }

    /// Tamamen ayrılmış başlatma (yeni oturum, stdio /dev/null): terminal kapanınca ya da
    /// Rice Studio çıkınca ölmez, kimsenin borusunu açık tutmaz.
    static func spawnDetached(_ exe: String, _ args: [String] = []) throws {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in [0, 1, 2] {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        posix_spawn_file_actions_addchdir_np(&actions, NSHomeDirectory())
        let argv = ([exe] + args).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0)=\($1)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, &actions, &attr, argv, envp)
        if rc != 0 { throw RiceError.failed("\(exe) başlatılamadı: \(String(cString: strerror(rc)))") }
    }

    /// `open -g -a` — uygulamayı arka planda aç (LaunchServices, Rice Studio'ya bağlı kalmaz)
    static func openApp(_ path: String) throws {
        let r = run("/usr/bin/open", ["-g", "-a", path])
        if !r.ok { throw RiceError.failed("\((path as NSString).lastPathComponent) açılamadı: \(r.message)") }
    }

    static func openInFinderOrEditor(_ path: String) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        run("/usr/bin/open", isDir.boolValue ? [path] : ["-t", path])
    }

    // MARK: Süreçler (libproc — pgrep'in Swift karşılığı; CLI'da da güncel, NSWorkspace gibi run loop istemez)

    struct Proc {
        let pid: pid_t
        let name: String
        let path: String
    }

    static func processes() -> [Proc] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [] }
        var nameBuf = [CChar](repeating: 0, count: 256)
        var pathBuf = [CChar](repeating: 0, count: 4096)
        var out: [Proc] = []
        for pid in pids.prefix(Int(n)) where pid > 0 {
            let name = proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 ? String(cString: nameBuf) : ""
            let path = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 ? String(cString: pathBuf) : ""
            out.append(Proc(pid: pid, name: name, path: path))
        }
        return out
    }

    /// Süreç adına göre (pgrep -x)
    static func pids(named name: String) -> [pid_t] {
        processes().filter { $0.name == name }.map(\.pid)
    }

    /// Yolu bu önekle başlayan süreçler. Swift String karşılaştırması NFC/NFD farkını (Übersicht'teki Ü) yok sayar.
    static func pids(pathPrefix: String) -> [pid_t] {
        processes().filter { $0.path.hasPrefix(pathPrefix) }.map(\.pid)
    }

    static func signal(_ pids: [pid_t], _ sig: Int32) {
        for p in pids { kill(p, sig) }
    }

    /// cond true olana kadar bekle (en fazla seconds)
    @discardableResult
    static func wait(_ seconds: TimeInterval, until cond: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return true }
            usleep(150_000)
        }
        return cond()
    }

    // MARK: AppleScript / JXA

    @discardableResult
    static func jxa(_ script: String, _ args: [String] = [], timeout: TimeInterval = 30) -> Result {
        run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script] + args, timeout: timeout)
    }
}

enum RiceError: LocalizedError {
    case failed(String)
    case notInstalled(String)
    case unknownModule(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .failed(let s): return s
        case .notInstalled(let s): return "\(s) kurulu değil"
        case .unknownModule(let s): return "bilinmeyen modül: \(s)"
        case .busy: return "başka bir geçiş sürüyor"
        }
    }
}

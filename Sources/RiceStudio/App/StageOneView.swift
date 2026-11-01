import SwiftUI

/// Aşama 1 geçici görünüm: modüller + durum + "Aktif yap". Aşama 2'de sidebar'lı ana pencereyle değişecek.
struct StageOneView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Rice Studio").font(.title2.bold())
                Spacer()
                Text("WM: \(name(model.activeWM))  ·  Bar: \(name(model.activeBar))")
                    .foregroundStyle(.secondary)
            }
            ForEach(ModuleKind.allCases, id: \.self) { kind in
                GroupBox(kind.title) {
                    VStack(spacing: 6) {
                        ForEach(model.rows(kind)) { row in
                            ModuleRowView(row: row)
                        }
                        if kind != .extra {
                            HStack {
                                Spacer()
                                Button("Hiçbiri") { model.activate(kind, "none") }
                                    .disabled(model.busy != nil)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            if let e = model.error {
                Text(e).foregroundStyle(.red).font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 400)
    }

    private func name(_ id: String) -> String { Registry.module(id)?.name ?? "yok" }
}

struct ModuleRowView: View {
    @EnvironmentObject var model: AppModel
    let row: AppModel.Row

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol).frame(width: 22)
            Text(row.name).frame(width: 120, alignment: .leading)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(row.status.label).foregroundStyle(.secondary).font(.callout)
            Spacer()
            if model.busy == row.id { ProgressView().controlSize(.small) }
            if row.kind == .extra {
                Button(row.status == .running ? "Durdur" : "Başlat") {
                    let id = row.id, running = row.status == .running
                    model.perform(id) { running ? try Engine.stop(id) : try Engine.start(id) }
                }
                .disabled(row.status == .notInstalled || model.busy != nil)
            } else {
                Button("Aktif yap") { model.activate(row.kind, row.id) }
                    .disabled(row.status == .notInstalled || isActive || model.busy != nil)
            }
        }
        .opacity(row.status == .notInstalled ? 0.45 : 1)
    }

    private var isActive: Bool { (row.kind == .wm ? model.activeWM : model.activeBar) == row.id }

    private var color: Color {
        switch row.status {
        case .running: return .green
        case .stopped: return .secondary
        case .notInstalled: return .red.opacity(0.5)
        }
    }
}

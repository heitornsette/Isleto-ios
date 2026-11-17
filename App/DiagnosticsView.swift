import IsletoCore
import SwiftUI
import UIKit

/// App Group status, a widget preview and the text to copy into a bug report.
struct DiagnosticsView: View {
    let model: TodayModel
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("App Group") {
                    switch model.status {
                    case .ready(let id, _):
                        Label("OK", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("Grupo", value: id)
                    case .missingGroupID:
                        Label("Info.plist sem App Group", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    case .unavailable(let id):
                        Label("Indisponível", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        LabeledContent("Grupo", value: id)
                        LabeledContent("Concedidos", value: TodayModel.describe(model.appProfile))
                    }
                }
                Section {
                    TodayWidgetView(summary: model.summary, message: model.errorText)
                        .padding()
                        .frame(width: 338, height: 158)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Prévia do widget")
                } footer: {
                    Text("Mesma interface do widget médio \"Hoje\" da Tela de Início.")
                }
                Section("Relatório") {
                    Text(model.diagnostics())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button(copied ? "Copiado" : "Copiar diagnóstico") {
                        UIPasteboard.general.string = model.diagnostics()
                        copied = true
                    }
                }
            }
            .navigationTitle("Diagnóstico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

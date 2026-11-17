import IsletoCore
import SwiftUI
import UIKit

/// Feasibility test screen: App Group, shared counter, widget preview and Live Activity.
struct ProbeView: View {
    @State private var model = ProbeModel()
    @State private var copied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                appGroupSection
                counterSection
                widgetSection
                activitySection
                diagnosticsSection
            }
            .navigationTitle("Isleto · teste")
        }
        .task {
            model.reload()
            model.runDemo(arguments: ProcessInfo.processInfo.arguments)
        }
        .onChange(of: scenePhase) { _, phase in
            // The widget may have changed the counter while the app was in the background.
            if phase == .active { model.reload() }
        }
    }

    private var appGroupSection: some View {
        Section("App Group") {
            switch model.status {
            case .ready(let id, _):
                Label("OK", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                LabeledContent("Grupo", value: id)
            case .missingGroupID:
                Label("Info.plist sem App Group", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
            case .unavailable(let id):
                Label("Indisponível", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                LabeledContent("Grupo", value: id)
                Text("A assinatura não concedeu este App Group. Me envie o diagnóstico abaixo.")
                    .font(.footnote)
            }
            if let version = model.schemaVersion {
                LabeledContent("Banco", value: "isleto.db, esquema v\(version)")
            }
        }
    }

    private var counterSection: some View {
        Section("Contador (gravado no App Group)") {
            HStack {
                Text(model.counter.map(String.init) ?? "—")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Button("+1") { withAnimation { model.increment() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("increment")
            }
            if let error = model.counterError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Button("Zerar contador", role: .destructive) { model.reset() }
        }
    }

    private var widgetSection: some View {
        Section {
            CounterWidgetView(value: model.counter, message: model.counterError == nil ? nil : "Sem dados")
                .padding()
                .frame(width: 170, height: 170)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } header: {
            Text("Prévia do widget")
        } footer: {
            Text("Mesma interface do widget real. O widget de verdade fica na Tela de Início e lê o mesmo arquivo.")
        }
    }

    private var activitySection: some View {
        Section {
            HStack {
                Button("1 min") { model.startTimer(minutes: 1) }
                Button("25 min") { model.startTimer(minutes: 25) }
                Spacer()
                Button("Encerrar", role: .destructive) { model.endAllTimers() }
            }
            .buttonStyle(.bordered)
            Text(model.activityMessage).font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("Live Activity")
        } footer: {
            Text("O timer conta sozinho na Dynamic Island e na tela bloqueada, mesmo com o app fechado.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnóstico") {
            Text(model.diagnostics())
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Button(copied ? "Copiado" : "Copiar diagnóstico") {
                UIPasteboard.general.string = model.diagnostics()
                copied = true
            }
        }
    }
}

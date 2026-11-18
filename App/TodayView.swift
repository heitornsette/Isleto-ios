import IsletoCore
import SwiftUI

/// "Hoje": water and focus. Habits have their own tab.
struct TodayView: View {
    @State private var model = TodayModel()
    @State private var showingDiagnostics = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if let error = model.errorText {
                        Section {
                            Label(error, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.footnote)
                            Button("Ver diagnóstico") { showingDiagnostics = true }
                        }
                    }
                    if let summary = model.summary {
                        waterSection(summary)
                        focusSection(summary)
                    }
                }
                .navigationTitle("Hoje")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("Diagnóstico", systemImage: "stethoscope")
                        }
                    }
                }
                .sheet(isPresented: $showingDiagnostics) {
                    DiagnosticsView(model: model)
                }
                .task {
                    model.reload()
                    let arguments = ProcessInfo.processInfo.arguments
                    model.runDemo(arguments: arguments)
                    // CI screenshots only.
                    if arguments.contains("--demo-diagnostics") {
                        showingDiagnostics = true
                    }
                    if let index = arguments.firstIndex(of: "--demo-scroll"), index + 1 < arguments.count {
                        try? await Task.sleep(for: .milliseconds(500))
                        proxy.scrollTo(arguments[index + 1], anchor: .top)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The widget may have changed the data while the app was in the background.
            if phase == .active { model.reload() }
        }
    }

    // MARK: Water

    private func waterSection(_ summary: DaySummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.waterMl)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ \(summary.waterGoalMl) ml")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if summary.waterMl >= summary.waterGoalMl {
                        Label("Meta", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.isletoWater)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ProgressView(value: summary.waterProgress)
                    .tint(Color.isletoWater)
                HStack {
                    Button {
                        withAnimation { model.addWater() }
                    } label: {
                        Label("+\(WaterStore.glassMl) ml", systemImage: "drop.fill")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.isletoWater)
                    Spacer()
                    Button("Desfazer") { withAnimation { model.undoWater() } }
                        .buttonStyle(.bordered)
                        .disabled(summary.waterMl == 0)
                }
            }
            .padding(.vertical, 4)
            .id("water")
        } header: {
            Label("Água", systemImage: "drop.fill")
        }
    }

    // MARK: Focus

    private func focusSection(_ summary: DaySummary) -> some View {
        Section {
            if let active = summary.activeFocus {
                VStack(alignment: .leading, spacing: 10) {
                    Text(timerInterval: active.range, countsDown: true)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    ProgressView(timerInterval: active.range, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(Color.isletoFocus)
                    Button("Cancelar foco", role: .destructive) { model.cancelFocus() }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
                .id("focus")
            } else {
                Button {
                    model.startFocus()
                } label: {
                    Label("Iniciar foco de \(FocusStore.minutes) min", systemImage: "play.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.isletoFocus)
                .id("focus")
            }
            if let message = model.focusMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Label("Foco", systemImage: "timer")
        } footer: {
            Text("\(summary.focusSessions) foco(s) concluído(s) hoje. O tempo segue na Dynamic Island e na tela bloqueada com o app fechado.")
        }
    }
}

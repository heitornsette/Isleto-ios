@preconcurrency import ActivityKit
import Foundation
import IsletoCore
import Observation
import WidgetKit

/// State of the feasibility test screen. All logic lives in IsletoCore; this only
/// calls it and keeps what the screen shows.
@MainActor
@Observable
final class ProbeModel {
    private(set) var status: SharedContainer.Status = .missingGroupID
    private(set) var counter: Int?
    private(set) var counterError: String?
    private(set) var schemaVersion: Int?
    private(set) var activityMessage = "Nenhum timer iniciado."
    /// Groups the signature really granted, per bundle (nil: no embedded profile).
    private(set) var appProfile: ProvisioningProfile?
    private(set) var widgetProfile: ProvisioningProfile?

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var runningActivities: Int { Activity<TimerActivityAttributes>.activities.count }

    func reload() {
        status = SharedData.status()
        appProfile = ProvisioningProfile.load(bundleURL: Bundle.main.bundleURL)
        widgetProfile = Bundle.main.builtInPlugInsURL.flatMap {
            ProvisioningProfile.load(bundleURL: $0.appending(path: "IsletoWidgets.appex"))
        }
        do {
            let url = try SharedData.databaseURL()
            let database = try IsletoDatabase.open(at: url)
            counter = try ProbeCounter(database: database).value()
            schemaVersion = try database.read { try Schema.version($0) }
            counterError = nil
        } catch {
            counter = nil
            schemaVersion = nil
            counterError = error.localizedDescription
        }
    }

    func increment() {
        perform { _ = try $0.increment() }
    }

    func reset() {
        perform { try $0.reset() }
    }

    private func perform(_ change: (ProbeCounter) throws -> Void) {
        do {
            try change(SharedData.counter())
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            counterError = error.localizedDescription
        }
        reload()
    }

    func startTimer(minutes: Int) {
        guard activitiesEnabled else {
            activityMessage = "Live Activities desativadas para o Isleto em Ajustes."
            return
        }
        let range = FocusTimer.interval(startingAt: .now, minutes: minutes)
        let state = TimerActivityAttributes.ContentState(start: range.lowerBound, end: range.upperBound)
        do {
            _ = try Activity.request(
                attributes: TimerActivityAttributes(title: "Timer de teste"),
                content: ActivityContent(state: state, staleDate: range.upperBound),
                pushType: nil // free Apple ID: no APNs
            )
            activityMessage = "Timer de \(minutes) min iniciado."
        } catch {
            activityMessage = "Falha ao iniciar: \(error.localizedDescription)"
        }
    }

    func endAllTimers() {
        Task {
            for activity in Activity<TimerActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            activityMessage = "Timers encerrados."
        }
    }

    /// Text the user copies into a bug report. No personal data: only identifiers
    /// of this app, versions and statuses.
    func diagnostics() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let statusText: String = switch status {
        case .ready(let id, _): "OK (\(id))"
        case .missingGroupID: "SEM ID NO INFO.PLIST"
        case .unavailable(let id): "INDISPONÍVEL (\(id))"
        }
        return """
        Isleto \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))
        Commit: \(info["IsletoCommit"] as? String ?? "?")
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "?")
        iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App Group: \(statusText)
        Grupos concedidos (app): \(Self.describe(appProfile))
        Grupos concedidos (widget): \(Self.describe(widgetProfile))
        Perfil expira: \(appProfile?.expirationDate?.formatted(date: .abbreviated, time: .shortened) ?? "?")
        Banco: \(schemaVersion.map { "esquema v\($0)" } ?? "não abriu")
        Contador: \(counter.map(String.init) ?? "—")
        Erro: \(counterError ?? "nenhum")
        Live Activities: \(activitiesEnabled ? "permitidas" : "bloqueadas"), \(runningActivities) ativa(s)
        Último timer: \(activityMessage)
        """
    }

    static func describe(_ profile: ProvisioningProfile?) -> String {
        guard let profile else { return "sem perfil embutido" }
        return profile.appGroups.isEmpty ? "nenhum" : profile.appGroups.joined(separator: ", ")
    }

    /// Launch arguments used only by the CI screenshot script.
    func runDemo(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--demo-increment"),
           index + 1 < arguments.count, let times = Int(arguments[index + 1]) {
            for _ in 0..<times { increment() }
        }
        if arguments.contains("--demo-timer") {
            startTimer(minutes: 25)
        }
    }
}

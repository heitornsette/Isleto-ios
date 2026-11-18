import IsletoCore
import SwiftUI

/// "Nuvem": connect this iPhone to the isleto-cloud project once, then see the status.
struct CloudView: View {
    private let cloud = CloudSync.shared
    @State private var url = ""
    @State private var key = ""
    @State private var email = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var errorText: String?
    @State private var confirmingDisconnect = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if cloud.isConnected {
                    connectedSections
                } else {
                    connectSections
                }
            }
            .navigationTitle("Nuvem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .confirmationDialog("Desconectar da nuvem?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Desconectar", role: .destructive) { cloud.disconnect() }
            } message: {
                Text("Os dados continuam neste iPhone e na nuvem. Para voltar a sincronizar, conecte de novo.")
            }
        }
    }

    // MARK: Connected

    @ViewBuilder
    private var connectedSections: some View {
        Section("Conta") {
            LabeledContent("E-mail", value: cloud.email ?? "—")
            LabeledContent("Estado", value: statusText)
            if let report = cloud.lastReport {
                LabeledContent("Última troca", value: "\(report.pulled) recebidas, \(report.pushed) enviadas")
            }
            Button {
                Task { await cloud.syncNow() }
            } label: {
                if cloud.status == .syncing {
                    HStack {
                        ProgressView()
                        Text("Sincronizando…")
                    }
                } else {
                    Label("Sincronizar agora", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(cloud.status == .syncing)
        }
        Section {
            Button("Desconectar", role: .destructive) { confirmingDisconnect = true }
        } footer: {
            Text("O app sincroniza sozinho ao abrir e alguns segundos depois de cada mudança. O widget mostra o que já está neste iPhone.")
        }
    }

    private var statusText: String {
        switch cloud.status {
        case .disconnected: "Desconectado"
        case .syncing: "Sincronizando"
        case .idle: cloud.lastSync.map { "Sincronizado às \($0.formatted(date: .omitted, time: .shortened))" } ?? "Conectado"
        case .failed(let message): message
        }
    }

    // MARK: Not connected

    @ViewBuilder
    private var connectSections: some View {
        if case .failed(let message) = cloud.status {
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }
        Section {
            TextField("https://xxxx.supabase.co", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Chave publicável (sb_publishable_…)", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Projeto")
        } footer: {
            Text("No painel do Supabase: Project Settings > API Keys. Use a chave publicável, nunca a secreta.")
        }
        Section("Administrador") {
            TextField("E-mail", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Senha", text: $password)
                .textContentType(.password)
        }
        Section {
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if connecting { ProgressView() }
                    Text(connecting ? "Conectando…" : "Conectar")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(connecting || url.isEmpty || key.isEmpty || email.isEmpty || password.isEmpty)
        } footer: {
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else {
                Text("A senha é usada só agora e não fica guardada. O endereço, a chave e a sessão ficam no Keychain deste iPhone. Na primeira sincronização, hábitos de mesmo nome viram um só.")
            }
        }
    }

    private func connect() async {
        connecting = true
        errorText = nil
        defer { connecting = false }
        do {
            try await cloud.connect(url: url, key: key, email: email, password: password)
            password = ""
        } catch {
            errorText = error.localizedDescription
        }
    }
}

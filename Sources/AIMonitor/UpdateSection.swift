import SwiftUI
import Observation
import AIMonitorCore

@Observable @MainActor final class UpdateStore {
    private(set) var isChecking = false
    private(set) var message: String?
    private(set) var downloadURL: URL?
    private(set) var failed = false
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unbekannt"

    func check() {
        guard !isChecking else { return }
        isChecking = true; failed = false; message = "GitHub-Version wird geprüft …"; downloadURL = nil
        Task {
            defer { isChecking = false }
            do {
                switch try await ReleaseChecker().check(currentVersion: currentVersion) {
                case .upToDate: message = "Du verwendest die aktuelle Version."
                case .noRelease: message = "Noch keine veröffentlichte Version verfügbar."
                case .available(let version, let url):
                    message = "Version \(version) ist verfügbar."; downloadURL = url
                }
            } catch {
                failed = true
                message = (error as? URLError) != nil ? "Updateprüfung fehlgeschlagen. Bitte prüfe deine Internetverbindung und versuche es erneut." : error.localizedDescription
            }
        }
    }
}

struct UpdateSection: View {
    @State private var updates = UpdateStore()

    var body: some View {
        Section("Updates") {
            HStack {
                Text("Installiert: \(updates.currentVersion)").foregroundStyle(.secondary)
                Spacer()
                if updates.isChecking { ProgressView().controlSize(.small) }
                Button("Nach Updates suchen") { updates.check() }.disabled(updates.isChecking)
            }
            if let message = updates.message {
                Text(message).font(.caption).foregroundStyle(updates.failed ? Color.orange : Color.secondary)
            }
            if let url = updates.downloadURL {
                Link("Update auf GitHub herunterladen", destination: url)
            }
            Text("Prüft auf Knopfdruck GitHub Releases. Updates werden manuell heruntergeladen und installiert.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

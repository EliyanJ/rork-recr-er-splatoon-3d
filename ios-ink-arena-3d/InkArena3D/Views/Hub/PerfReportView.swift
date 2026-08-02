import SwiftUI
import UIKit

/// Viewer for the last recorded performance trace. Plain monospaced text with
/// copy + share actions: a TestFlight build has no console, so the report has
/// to leave the device through the player's own clipboard.
struct PerfReportView: View {
    let onClose: () -> Void

    @State private var recorder = PerfRecorder.shared
    @State private var didCopy = false
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                header

                if let report = recorder.lastReport {
                    ScrollView(showsIndicators: true) {
                        Text(report)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))

                    actions(report: report)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .alert("Effacer le rapport ?", isPresented: $showClearConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Effacer", role: .destructive) { recorder.clearReport() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onClose()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(PressableStyle())

            Text("RAPPORT DE PERFORMANCES")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            if recorder.isRecording {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("EN COURS")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aucun rapport enregistré")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("""
            Active « ENREGISTREUR DE PERFORMANCES » juste au-dessus, lance une partie \
            et joue normalement au moins 30 secondes (tire, cours, affronte les bots). \
            Le rapport est écrit dès que la partie se termine ou que tu la quittes, \
            puis il apparaît ici.
            """)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(report: String) -> some View {
        HStack(spacing: 8) {
            Button {
                UIPasteboard.general.string = report
                didCopy = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { didCopy = false }
            } label: {
                Label(didCopy ? "COPIÉ" : "COPIER", systemImage: didCopy ? "checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(didCopy ? Color.green : Color.menuAccent))
            }
            .buttonStyle(PressableStyle())

            ShareLink(item: report) {
                Label("PARTAGER", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)))
            }

            Button {
                showClearConfirm = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
            }
            .buttonStyle(PressableStyle())
        }
    }
}

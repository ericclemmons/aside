import SwiftUI
import AppKit
import AsideCore

/// Permissions checklist — shown during onboardingPermissions phase.
/// Single screen with all permissions visible at once.
struct SetupView: View {
    @ObservedObject var store: AppStore
    let permissionService: PermissionService
    @StateObject private var micMonitor = MicLevelMonitor()

    var body: some View {
        VStack(spacing: 0) {
            WaveformBanner(
                audioLevel: micMonitor.audioLevel,
                liveMode: store.context.permissions.microphone
            )
            .frame(height: 96)

            Spacer(minLength: 20)

            Text("Welcome to Aside")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 6)

            Text("Aside needs a few permissions to work. Grant them below, then get started.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            // Permission rows
            VStack(spacing: 8) {
                permissionRow("Screen Recording", icon: "rectangle.dashed.badge.record", permission: .screenRecording)
                permissionRow("Microphone", icon: "mic.fill", permission: .microphone)
                permissionRow("Speech Recognition", icon: "waveform", permission: .speechRecognition)
                permissionRow("Accessibility", icon: "keyboard", permission: .accessibility)
                openCodeRow
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)

            // Get Started button — only enabled when all permissions granted
            Button(action: { store.send(.allPermissionsGranted) }) {
                Text("Get Started")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.context.permissions.allGranted)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
        .frame(width: 420)
        .onAppear {
            store.send(.appLaunched)
            updateMicMonitor()
        }
        .onChange(of: store.context.permissions.microphone) { _, granted in
            if granted { micMonitor.start() } else { micMonitor.stop() }
        }
        .onDisappear { micMonitor.stop() }
    }

    private func updateMicMonitor() {
        if store.context.permissions.microphone {
            micMonitor.start()
        }
    }

    private func permissionRow(_ label: String, icon: String, permission: Permission) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))

            Spacer()

            if store.context.permissions[permission] {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
            } else {
                Button("Grant") {
                    Task {
                        _ = await permissionService.request(permission)
                        let status = permissionService.checkAll()
                        store.send(.permissionsChecked(status))
                    }
                    // Also open System Settings for permissions that need manual toggle
                    if permission == .screenRecording || permission == .accessibility {
                        openSystemSettings(for: permission)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func openSystemSettings(for permission: Permission) {
        let urlString: String
        switch permission {
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private var openCodeRow: some View {
        HStack(spacing: 12) {
            Group {
                if let url = Bundle.module.url(forResource: "opencode.logo", withExtension: "svg"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 14))
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 16)

            Text("OpenCode Desktop")
                .font(.system(size: 13))

            Spacer()

            if store.context.openCodeConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
            } else {
                Button("Open") {
                    let appURL = URL(fileURLWithPath: "/Applications/OpenCode.app")
                    if FileManager.default.fileExists(atPath: appURL.path) {
                        NSWorkspace.shared.open(appURL)
                    } else {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        process.arguments = ["-a", "OpenCode"]
                        try? process.run()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

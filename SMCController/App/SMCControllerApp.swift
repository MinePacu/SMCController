//
//  SMCControllerApp.swift
//  SMCController
//

import SwiftUI
import AppKit
import Darwin

private let aboutWindowID = "about-window"

@main
struct SMCControllerApp: App {
    @State private var fanControlViewModel = FanControlViewModel()
    @State private var languageSettings = AppLanguageSettings()
    
    init() {
        if Self.isXPCCheckMode {
            runXPCCheckAndExit()
        } else {
            checkPrivileges()
        }
    }

    var body: some Scene {
        WindowGroup {
            if Self.isXPCCheckMode {
                // Do not construct the monitoring UI in diagnostic mode. In particular,
                // this keeps all user-action-only privilege controls out of the process.
                EmptyView()
            } else {
                ContentView()
                    .environment(fanControlViewModel)
                    .environment(languageSettings)
                    .environment(\.locale, languageSettings.selectedLanguage.locale)
                    .id(languageSettings.selectedLanguage.id)
                    .modifier(AppIconAppearanceObserver())
            }
        }
        Window(L10n.string("About SMC Controller"), id: aboutWindowID) {
            AboutView()
                .environment(languageSettings)
                .environment(\.locale, languageSettings.selectedLanguage.locale)
                .id(languageSettings.selectedLanguage.id)
                .modifier(AppIconAppearanceObserver())
                .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 420)
        }
        .windowResizability(.contentSize)
        Settings {
            AppSettingsView(languageSettings: languageSettings)
                .environment(\.locale, languageSettings.selectedLanguage.locale)
                .id(languageSettings.selectedLanguage.id)
        }
        // 윈도우/툴바 스타일: 구분선 최소화, 배경을 시각적으로 투명하게 보이도록
        //.windowStyle(.hiddenTitleBar)              // 타이틀바를 숨겨 상단 라인 제거
        //.windowToolbarStyle(.unifiedCompact)       // 윈도우 도구 막대 스타일을 최소화
        .commands {
            AboutCommands()
        }
    }
    
    private func checkPrivileges() {
        Task { @MainActor in
            let helper = PrivilegeHelper.shared
            await helper.refreshStatus()
            print("[App] Helper installed: \(helper.helperInstalled), daemon running: \(helper.daemonRunning)")
        }
    }

    /// A deliberately non-interactive diagnostic entry point for the signed app.
    /// It is consumed by check_daemon.sh to prove that the XPC peer-requirement
    /// handshake accepts this exact app build. It never reaches installation APIs.
    private static let isXPCCheckMode = CommandLine.arguments.contains("--xpc-check")

    private func runXPCCheckAndExit() {
        Task {
            let availability = await DaemonClient.shared.helperAvailability()
            let result: String
            let status: Int32

            switch availability {
            case .ready:
                result = "ready"
                status = EXIT_SUCCESS
            case .notInstalled:
                result = "notInstalled"
                status = EXIT_FAILURE
            case .updateRequired:
                result = "updateRequired"
                status = EXIT_FAILURE
            case .failed:
                result = "failed"
                status = EXIT_FAILURE
            }

            print("XPC_CHECK: \(result)")
            fflush(stdout)
            exit(status)
        }
    }
}

private struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.string("About SMC Controller")) {
                openWindow(id: aboutWindowID)
            }
        }
    }
}

private struct AppIconAppearanceObserver: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppIconUpdater.apply(for: colorScheme)
            }
            .onChange(of: colorScheme) { _, newValue in
                AppIconUpdater.apply(for: newValue)
            }
    }
}

private enum AppIconUpdater {
    @MainActor
    static func apply(for colorScheme: ColorScheme) {
        let imageName = colorScheme == .dark ? "DarkModeAppIcon" : "LightModeAppIcon"
        NSApplication.shared.applicationIconImage = NSImage(named: imageName)
    }
}

// NSWindow 수준에서 타이틀바를 투명하게 보이게 하는 헬퍼 뷰
private struct TransparentTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

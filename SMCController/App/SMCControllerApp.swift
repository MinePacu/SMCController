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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences: AppPreferences
    @State private var fanControlViewModel: FanControlViewModel
    @State private var languageSettings = AppLanguageSettings()
    // Same key AppPreferences writes; AppStorage makes the scene react to changes.
    @AppStorage(AppPreferences.Key.showMenuBarExtra) private var showMenuBarExtra = true
    
    init() {
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _fanControlViewModel = State(initialValue: FanControlViewModel(preferences: preferences))
        if Self.isXPCCheckMode {
            runXPCCheckAndExit()
        } else {
            checkPrivileges()
        }
    }

    var body: some Scene {
        WindowGroup(id: mainWindowID) {
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
                    .onAppear {
                        appDelegate.attach(fanControlViewModel)
                    }
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
        MenuBarExtra(isInserted: menuBarInsertedBinding) {
            MenuBarContent(viewModel: fanControlViewModel)
                .environment(\.locale, languageSettings.selectedLanguage.locale)
        } label: {
            MenuBarLabel(viewModel: fanControlViewModel)
                .onAppear {
                    guard !Self.isXPCCheckMode else { return }
                    appDelegate.attach(fanControlViewModel)
                }
        }
        .menuBarExtraStyle(.menu)
        Settings {
            AppSettingsView(languageSettings: languageSettings, preferences: preferences)
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
    
    /// Hidden in diagnostic mode so `--xpc-check` never builds monitoring UI.
    private var menuBarInsertedBinding: Binding<Bool> {
        Binding(
            get: { !Self.isXPCCheckMode && showMenuBarExtra },
            set: { preferences.showMenuBarExtra = $0 }
        )
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

/// Makes sure manual fan control never outlives the app or survives a sleep cycle.
/// The helper's lease watchdog is the last line of defense; this restores automatic
/// mode right away instead of waiting for the lease to expire.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Upper bound on how long quitting may wait for the helper to answer.
    private static let terminationTimeoutNanoseconds: UInt64 = 3_000_000_000

    private weak var fanControlViewModel: FanControlViewModel?
    // Kept for the app's lifetime; the delegate is never deallocated while running.
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isTerminating = false
    private var hasRepliedToTermination = false

    func attach(_ viewModel: FanControlViewModel) {
        guard fanControlViewModel !== viewModel else { return }
        fanControlViewModel = viewModel
        installWorkspaceObservers()
        viewModel.performLaunchActions()
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let viewModel = self?.fanControlViewModel else { return }
                Task { @MainActor in await viewModel.handleSystemWillSleep() }
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fanControlViewModel?.handleSystemDidWake()
            }
        })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel = fanControlViewModel, viewModel.needsTerminationCleanup else {
            return .terminateNow
        }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true

        // Whichever finishes first wins: a restored automatic mode, or the timeout.
        // The timeout runs independently so a hung helper call cannot block quitting;
        // the helper lease still returns the fans to automatic mode in that case.
        let timeout = Self.terminationTimeoutNanoseconds
        Task { @MainActor [weak self] in
            await viewModel.prepareForTermination()
            self?.replyToTermination(sender)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            self?.replyToTermination(sender)
        }
        return .terminateLater
    }

    private func replyToTermination(_ sender: NSApplication) {
        guard !hasRepliedToTermination else { return }
        hasRepliedToTermination = true
        sender.reply(toApplicationShouldTerminate: true)
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

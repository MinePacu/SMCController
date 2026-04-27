//
//  SMCControllerApp.swift
//  SMCController
//

import SwiftUI
import AppKit

private let aboutWindowID = "about-window"

@main
struct SMCControllerApp: App {
    @State private var fanControlViewModel = FanControlViewModel()
    
    init() {
        checkPrivileges()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(fanControlViewModel)
                // 타이틀바를 투명하게: 상단 구분선 느낌 제거에 핵심
                //.background(TransparentTitlebar())
        }
        Window("About SMC Controller", id: aboutWindowID) {
            AboutView()
                .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 420)
        }
        .windowResizability(.contentSize)
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
            helper.refreshStatus()
            print("[App] Helper installed: \(helper.helperInstalled), daemon running: \(helper.daemonRunning)")
        }
    }
}

private struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About SMC Controller") {
                openWindow(id: aboutWindowID)
            }
        }
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

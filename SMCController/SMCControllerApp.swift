//
//  SMCControllerApp.swift
//  SMCController
//

import SwiftUI
import AppKit

@main
struct SMCControllerApp: App {
    @StateObject private var navigator = Navigator()
    @State private var fanControlViewModel = FanControlViewModel()
    
    init() {
        // Check privileges on startup and auto-elevate if needed
        checkAndRequestPrivileges()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigator)
                .environment(fanControlViewModel)
                // 타이틀바를 투명하게: 상단 구분선 느낌 제거에 핵심
                //.background(TransparentTitlebar())
        }
        // 윈도우/툴바 스타일: 구분선 최소화, 배경을 시각적으로 투명하게 보이도록
        //.windowStyle(.hiddenTitleBar)              // 타이틀바를 숨겨 상단 라인 제거
        //.windowToolbarStyle(.unifiedCompact)       // 윈도우 도구 막대 스타일을 최소화
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Back") {
                    navigator.pop()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!navigator.canPop)
            }
        }
    }
    
    private func checkAndRequestPrivileges() {
        // If already running as root, nothing to do
        if PrivilegeHelper.isRunningAsRoot() {
            print("[App] ✅ Running with root privileges (euid=\(geteuid()))")
            return
        }
        
        print("[App] ⚠️ Not running as root (euid=\(geteuid()))")
        
        #if DEBUG
        print("[App] ⚠️ Debug mode detected - privilege elevation disabled")
        print("[App] To test with privileges, run from terminal:")
        if let path = Bundle.main.executablePath {
            print("[App]   sudo \"\(path)\"")
        }
        return
        #else
        print("[App] Release mode - will request elevation on first access")
        
        // Schedule privilege request after UI loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task { @MainActor in
                let helper = PrivilegeHelper.shared
                print("[App] Checking privileges... hasPrivileges=\(helper.hasPrivileges)")
                
                if !helper.hasPrivileges && !helper.elevationAttempted {
                    print("[App] Requesting privilege elevation...")
                    helper.requestPrivilegesAndRelaunch()
                } else if helper.elevationAttempted {
                    print("[App] Elevation already attempted, skipping")
                } else {
                    print("[App] Already has privileges")
                }
            }
        }
        #endif
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

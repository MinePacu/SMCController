//
//  ContentView.swift
//  SMCController
//

import SwiftUI

private enum SidebarItem: String, CaseIterable, Identifiable {
    case fanControl = "Fan Control"
    case privileges = "Privileges"
    case hidDebug = "HID Sensors"
    case smcDebug = "SMC Sensors"
    case profile = "Profile"
    case about = "About"

    var id: String { rawValue }

    @ViewBuilder
    var label: some View {
        switch self {
        case .fanControl:
            Label("Fan Control", systemImage: "wind")
        case .privileges:
            Label("Privileges", systemImage: "lock.shield")
        case .hidDebug:
            Label("HID Sensors", systemImage: "cpu")
        case .smcDebug:
            Label("SMC Sensors", systemImage: "memorychip")
        case .profile:
            Label("Profile", systemImage: "person.crop.circle")
        case .about:
            Label("About", systemImage: "info.circle")
        }
    }
}

// 네비게이션 라우팅용 타입
private enum Route: Hashable {
    case detail(title: String, message: String)
}

struct ContentView: View {
    @EnvironmentObject private var navigator: Navigator
    @Environment(FanControlViewModel.self) private var fanControlViewModel

    @State private var selection: SidebarItem? = .fanControl {
        didSet {
            // 사이드바로 루트 전환 시, 기존 스택을 초기화하여
            // 다른 루트로 넘어가도 Back 상태가 꼬이지 않도록 함
            navigator.popToRoot()
        }
    }


    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        item.label
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SMC Controller")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            NavigationStack(path: $navigator.path) {
                Group {
                    switch selection {
                    case .fanControl, .none:
                        FanControlView(viewModel: fanControlViewModel) { title, message in
                            navigator.push(Route.detail(title: title, message: message))
                        }
                        .navigationTitle("")
                    
                    case .privileges:
                        PrivilegeStatusView()
                            .navigationTitle("")
                    
                    case .hidDebug:
                        HIDSensorDebugView()
                            .environment(fanControlViewModel)
                            .navigationTitle("")
                    
                    case .smcDebug:
                        SMCSensorDebugView()
                            .environment(fanControlViewModel)
                            .navigationTitle("")

                    case .profile:
                        ProfileView { title, message in
                            navigator.push(Route.detail(title: title, message: message))
                        }
                        .navigationTitle("")

                    case .about:
                        AboutView { title, message in
                            navigator.push(Route.detail(title: title, message: message))
                        }
                        .navigationTitle("")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Route -> 실제 화면 매핑
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .detail(title, message):
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title)
                                .font(.title2.weight(.semibold))
                            Text(message)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding()
                        .navigationTitle("") // 타이틀은 빈 문자열
                    }
                }
                // macOS: 뒤로 가기 버튼은 경로가 있을 때만 보이도록 .automatic 위치에 1개만 배치
                .toolbar {
                    if navigator.canPop {
                        ToolbarItem(placement: .automatic) {
                            Button {
                                navigator.pop()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .help("뒤로 가기 (⌘+[)")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 1200, idealWidth: 1280, minHeight: 600, idealHeight: 800)
        .onChange(of: selection) {
            navigator.popToRoot()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(Navigator())
}

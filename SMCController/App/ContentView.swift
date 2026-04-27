//
//  ContentView.swift
//  SMCController
//

import SwiftUI

private enum SidebarItem: String, CaseIterable, Identifiable {
    case fanControl = "Fan Control"
    case privileges = "Privileges"
    case presets = "Presets"
    case hidDebug = "HID Sensors"
    case smcDebug = "SMC Sensors"

    var id: String { rawValue }

    @ViewBuilder
    var label: some View {
        switch self {
        case .fanControl:
            Label("Fan Control", systemImage: "wind")
        case .privileges:
            Label("Privileges", systemImage: "lock.shield")
        case .presets:
            Label("Presets", systemImage: "square.stack")
        case .hidDebug:
            Label("HID Sensors", systemImage: "cpu")
        case .smcDebug:
            Label("SMC Sensors", systemImage: "memorychip")
        }
    }
}

private enum SidebarSection: String, CaseIterable, Identifiable {
    case main = "Control"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var items: [SidebarItem] {
        switch self {
        case .main:
            [.fanControl, .privileges, .presets]
        case .diagnostics:
            [.hidDebug, .smcDebug]
        }
    }
}

struct ContentView: View {
    @Environment(FanControlViewModel.self) private var fanControlViewModel
    @State private var selection: SidebarItem? = .fanControl
    @State private var diagnosticsExpanded = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Section(SidebarSection.main.rawValue) {
                    ForEach(SidebarSection.main.items) { item in
                        NavigationLink(value: item) {
                            item.label
                        }
                    }
                }

                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    ForEach(SidebarSection.diagnostics.items) { item in
                        NavigationLink(value: item) {
                            item.label
                        }
                    }
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SMC Controller")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            NavigationStack {
                switch selection {
                case .fanControl, .none:
                    FanControlView(viewModel: fanControlViewModel)
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

                case .presets:
                    ProfileView()
                        .navigationTitle("")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1200, idealWidth: 1280, minHeight: 600, idealHeight: 800)
    }
}

#Preview {
    ContentView()
}

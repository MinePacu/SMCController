//
//  AboutView.swift
//  SMCController
//

import SwiftUI

struct AboutView: View {
    // 외부로 푸시를 요청하기 위한 콜백
    var onNavigate: ((String, String) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            // 내부 진입 버튼
            HStack {
                Button {
                    onNavigate?("About Detail", "Pushed from About.")
                } label: {
                    Label("Open Detail", systemImage: "arrow.right.square")
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            Image(systemName: "info.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("SMC Controller")
                .font(.title)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .foregroundStyle(.secondary)
            }
            Text("Control fan speeds via SMC on macOS.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    AboutView()
        .frame(width: 600, height: 400)
}

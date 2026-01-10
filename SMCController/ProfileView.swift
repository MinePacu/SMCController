//
//  ProfileView.swift
//  SMCController
//

import SwiftUI

struct ProfileView: View {
    // 외부로 푸시를 요청하기 위한 콜백
    var onNavigate: ((String, String) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // 내부 진입 버튼
            HStack {
                Button {
                    onNavigate?("Profile Detail", "Pushed from Profile.")
                } label: {
                    Label("Open Detail", systemImage: "arrow.right.square")
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            Image(systemName: "person.crop.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Profile")
                .font(.title)
            Text("Manage your profile or presets here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ProfileView()
        .frame(width: 600, height: 400)
}

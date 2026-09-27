import SwiftUI

// REQ-2026-002 T-3（AC-1，Q1「首启配置页」）：未配置时唯一页面。
// 输入即用户显式配置，保存经 CoreKit 校验；校验失败原样标错，无任何兜底。

struct ConfigView: View {
    let session: AppSession

    @State private var baseURL = ""
    @State private var token = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("后端地址") {
                    TextField("https://…", text: $baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("访问令牌") {
                    SecureField("Bearer token", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button("保存并进入") {
                        do {
                            errorMessage = nil
                            try session.save(baseURL: baseURL, token: token)
                        } catch {
                            errorMessage = String(describing: error)
                        }
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                        || token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("连接配置")
        }
    }
}

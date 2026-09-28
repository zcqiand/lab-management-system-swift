import SwiftUI

// REQ-2026-003 T-2（配置页瘦身）：只收后端地址——token 改由登录页换发
// （M01.F05.I06），不再手工粘贴。输入即用户显式配置，保存经 CoreKit 校验；
// 校验失败原样标错，无任何兜底。

struct ConfigView: View {
    let session: AppSession

    @State private var baseURL = ""
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
                Section {
                    Button("保存并进入") {
                        do {
                            errorMessage = nil
                            try session.saveBaseURL(baseURL)
                        } catch {
                            errorMessage = String(describing: error)
                        }
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
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

import SwiftUI

// REQ-2026-003 T-2（配置页瘦身）：只收后端地址——token 改由登录页换发
// （M01.F05.I06），不再手工粘贴。输入即用户显式配置，保存经 CoreKit 校验；
// 校验失败原样标错，无任何兜底。

struct ConfigView: View {
    let session: AppSession

    @State private var baseURL = ""
    @State private var ssoClientId = ""
    @State private var ssoCallbackScheme = ""
    @State private var errorMessage: String?
    @State private var ssoMessage: String?

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
                // SSO 配置（M01.F05.I03，REQ-2026-010）：用户显式填写，缺失
                // 登录页 fail-fast，不兜底字面量（ADR-0019）。scheme 须与
                // Info.plist 注册的 CFBundleURLSchemes 一致（系统按它回跳 App），
                // 且后端 saas oauth_client 白名单须登记同款 redirect_uri（Q2 人裁）。
                Section {
                    TextField("SSO client_id（如 lab-management）", text: $ssoClientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("SSO 回调 scheme（如 labman）", text: $ssoCallbackScheme)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存 SSO 配置") {
                        do {
                            ssoMessage = nil
                            try session.store.saveSsoConfig(
                                clientId: ssoClientId, callbackScheme: ssoCallbackScheme
                            )
                            ssoMessage = "已保存"
                        } catch {
                            ssoMessage = String(describing: error)
                        }
                    }
                } header: {
                    Text("SSO 配置")
                } footer: {
                    Text("回调 scheme 须与本 App 注册的 URL scheme 一致")
                }
                if let ssoMessage {
                    Section {
                        Text(ssoMessage)
                            .font(.footnote)
                    }
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
            .onAppear {
                baseURL = session.store.baseURL ?? ""
                ssoClientId = session.store.ssoClientId ?? ""
                ssoCallbackScheme = session.store.ssoCallbackScheme ?? ""
            }
        }
    }
}

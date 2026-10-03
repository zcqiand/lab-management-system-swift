import CoreKit
import SwiftUI

// REQ-2026-003 T-3（M01.F05.I06）：原生登录页——用户名+密码 → native-login 换
// lab JWT，不再手工粘贴 token。网络缝走 APIGlue（生成物唯一入口），
// 状态机在 CoreKit.AuthViewModel；成功经 session.refresh() 进业务页。

// @entry M01.F05.I06 — 原生登录页（非浏览器表单本体）
struct LoginView: View {
    let session: AppSession

    @StateObject private var vm: AuthViewModel
    @StateObject private var ssoVM: SsoViewModel
    @State private var username = ""
    @State private var password = ""

    init(session: AppSession) {
        self.session = session
        let store = session.store
        _vm = StateObject(wrappedValue: AuthViewModel(
            store: store,
            seams: .init(
                nativeLogin: APIGlue.nativeLogin,
                switchTenant: APIGlue.switchTenant,
                logout: {
                    // 本地无 token（401 失效后重登中）就没啥可吊销的。
                    if let token = store.token {
                        try await APIGlue.logout(token)
                    }
                }
            )
        ))
        // SSO（M01.F05.I03）：三缝注入——网络两缝走生成物，浏览器会话缝绑
        // ASWebAuthenticationSession。配置缺失由 VM fail-fast（ADR-0019）。
        _ssoVM = StateObject(wrappedValue: SsoViewModel(
            store: store,
            seams: .init(
                authorize: APIGlue.ssoAuthorize,
                exchange: APIGlue.ssoCallback,
                openWebSession: WebAuthSession.open
            )
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("登录") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }
                Section {
                    Button("登录") {
                        Task {
                            if await vm.login(
                                username: username.trimmingCharacters(in: .whitespaces),
                                password: password
                            ) {
                                session.refresh()
                            }
                        }
                    }
                    .disabled(
                        username.trimmingCharacters(in: .whitespaces).isEmpty
                            || password.isEmpty
                            || vm.phase == .busy
                    )
                }
                if case .failed(let message) = vm.phase {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                // SSO 登录（M01.F05.I03）：授权码流走系统浏览器会话，成功
                // 同样 adoptLogin → ready 直进（settle 复用 REQ-2026-009）。
                // 配置缺失点按后 fail-fast 报引导文案，不兜底。
                Section {
                    Button("SSO 登录") {
                        Task {
                            if await ssoVM.login(
                                clientId: session.store.ssoClientId ?? "",
                                callbackScheme: session.store.ssoCallbackScheme ?? ""
                            ) {
                                session.refresh()
                            }
                        }
                    }
                }
                if case .failed(let message) = ssoVM.phase {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("登录")
        }
    }
}

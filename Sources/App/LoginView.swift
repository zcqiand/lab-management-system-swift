import CoreKit
import SwiftUI

// REQ-2026-003 T-3（M01.F05.I06）：原生登录页——用户名+密码 → native-login 换
// lab JWT，不再手工粘贴 token。网络缝走 APIGlue（生成物唯一入口），
// 状态机在 CoreKit.AuthViewModel；成功经 session.refresh() 进业务页。

struct LoginView: View {
    let session: AppSession

    @StateObject private var vm: AuthViewModel
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
            }
            .navigationTitle("登录")
        }
    }
}

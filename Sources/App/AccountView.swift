import CoreKit
import SwiftUI

// REQ-2026-003 T-3：账户页——当前用户 + 会话（M00.F01）+ 租户切换
// （M00.F02.I01，switch-tenant 换发新 token 后列表整表刷新）+ 登出
// （M01.F05.I04，清 Keychain 回登录页）。数据全来自 SessionStore 快照。

struct AccountView: View {
    let session: AppSession

    @StateObject private var vm: AuthViewModel
    @State private var selectedTenantId: String
    @Environment(\.dismiss) private var dismiss

    init(session: AppSession) {
        self.session = session
        let store = session.store
        _vm = StateObject(wrappedValue: AuthViewModel(
            store: store,
            seams: .init(
                nativeLogin: APIGlue.nativeLogin,
                switchTenant: APIGlue.switchTenant,
                logout: {
                    if let token = store.token {
                        try await APIGlue.logout(token)
                    }
                }
            )
        ))
        // 登录响应不带 currentTenantId，快照取首位租户作当前项。
        _selectedTenantId = State(initialValue: store.tenants.first?.tenantId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("当前用户") {
                    if let user = session.store.user {
                        LabeledContent("用户名", value: user.username)
                        if let name = user.displayName, name.isEmpty == false {
                            LabeledContent("姓名", value: name)
                        }
                        if let role = user.roleCode, role.isEmpty == false {
                            LabeledContent("角色", value: role)
                        }
                    } else {
                        Text("会话信息不可用").foregroundStyle(.secondary)
                    }
                }
                Section("切换租户") {
                    Picker("目标租户", selection: $selectedTenantId) {
                        ForEach(session.store.tenants, id: \.tenantId) { tenant in
                            Text(tenant.name).tag(tenant.tenantId)
                        }
                    }
                    Button("切换并刷新") {
                        Task {
                            if await vm.switchTenant(to: selectedTenantId) {
                                session.refresh()
                                dismiss() // 回列表触发整表刷新（onDismiss 重载）
                            }
                        }
                    }
                    .disabled(selectedTenantId.isEmpty || vm.phase == .busy)
                }
                Section {
                    Button("登出", role: .destructive) {
                        Task {
                            await vm.logout()
                            session.refresh() // state→needsLogin，根路由自动换登录页
                        }
                    }
                }
                if case .failed(let message) = vm.phase {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("账户")
        }
    }
}

import CoreKit
import SwiftUI

// REQ-2026-003 T-3：App 入口三态路由。
// needsSetup → 配置页（只配 baseURL，AC：零 API 调用）；
// needsLogin → 登录页（M01.F05.I06 原生登录；401 失效/登出也落这，I02/I04）；
// ready → 接样列表。CoreKit.SessionStore 管状态，本层只做 SwiftUI 绑定。

@main
struct LabManagementApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            switch session.state {
            case .needsSetup:
                ConfigView(session: session)
            case .needsLogin:
                LoginView(session: session)
            case .ready:
                ReceiptListView(session: session)
            }
        }
    }
}

/// SessionStore 的 SwiftUI 壳：state 变化驱动根视图切换。
final class AppSession: ObservableObject {
    let store: SessionStore
    @Published private(set) var state: SessionStore.SessionState

    init(store: SessionStore = SessionStore(defaults: .standard, secrets: KeychainTokenStore())) {
        self.store = store
        state = store.state
        // 401 拦截缝（I02）：与登出同语义——清会话留 baseURL 回登录页。
        APIGlue.onUnauthorized = { [weak self] in self?.expire() }
    }

    /// 配置页保存（T-2 瘦身：只收 baseURL）。
    func saveBaseURL(_ raw: String) throws {
        try store.saveBaseURL(raw)
        state = store.state
    }

    /// 登录/切换/登出后由页面调：重读 store 三态驱动根路由。
    func refresh() {
        state = store.state
    }

    /// 401 失效缝（I02）。
    func expire() {
        store.logout()
        state = store.state
    }
}

import CoreKit
import SwiftUI

// REQ-2026-002 T-3：App 入口。未配置 → 配置页（AC-1，零 API 调用）；
// 已配置 → 接样列表。CoreKit.SessionStore 管状态，本层只做 SwiftUI 绑定。

@main
struct LabManagementApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            switch session.state {
            case .needsSetup:
                ConfigView(session: session)
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

    init(store: SessionStore = SessionStore()) {
        self.store = store
        state = store.state
    }

    func save(baseURL: String, token: String) throws {
        try store.save(baseURL: baseURL, token: token)
        state = store.state
    }

    func clear() {
        store.clear()
        state = store.state
    }
}

import XCTest
@testable import CoreKit

/// REQ-2026-002 T-2（AC-1，Q1 人裁「首启配置页」）：SessionStore 配置状态机。
/// fail-fast 口径 = 未配置绝不发 API 请求；UserDefaults 是用户显式输入的持久化，
/// 不是代码默认值兜底（REQ-2026-002 风险 R2 口径）。
final class SessionStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "SessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFreshStoreNeedsSetupWithNoPersistedConfig() {
        let store = SessionStore(defaults: makeDefaults())
        XCTAssertEqual(store.state, .needsSetup)
        XCTAssertNil(store.baseURL)
        XCTAssertNil(store.token)
    }

    func testSaveRejectsBadInputFailFastAndPersistsNothing() {
        let defaults = makeDefaults()
        let store = SessionStore(defaults: defaults)
        XCTAssertThrowsError(try store.save(baseURL: "  ", token: "tk-1"))
        XCTAssertThrowsError(try store.save(baseURL: "https://api.example.invalid", token: " "))
        XCTAssertThrowsError(try store.save(baseURL: "not a url", token: "tk-1"))
        XCTAssertEqual(store.state, .needsSetup, "失败保存不许改状态")
        XCTAssertNil(store.baseURL)
        XCTAssertNil(store.token)
    }

    func testSavePersistsAndReadies() throws {
        let defaults = makeDefaults()
        let store = SessionStore(defaults: defaults)
        try store.save(baseURL: "https://api.example.invalid/", token: "tk-1")
        XCTAssertEqual(store.state, .ready)
        // 尾斜杠被 bootstrap 规则归一化；持久化值读回应一致
        XCTAssertEqual(store.baseURL, "https://api.example.invalid")
        XCTAssertEqual(store.token, "tk-1")
        // 新实例（模拟重启）从 UserDefaults 恢复为 ready
        let reborn = SessionStore(defaults: defaults)
        XCTAssertEqual(reborn.state, .ready)
        XCTAssertEqual(reborn.token, "tk-1")
    }

    func testClearReturnsToNeedsSetupAndWipesKeys() throws {
        let defaults = makeDefaults()
        let store = SessionStore(defaults: defaults)
        try store.save(baseURL: "https://api.example.invalid", token: "tk-1")
        store.clear()
        XCTAssertEqual(store.state, .needsSetup)
        XCTAssertNil(store.baseURL)
        XCTAssertNil(store.token)
    }
}

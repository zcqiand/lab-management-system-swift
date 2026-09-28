import XCTest
import LabSharedGenerated
@testable import CoreKit

/// REQ-2026-003 T-2：SessionStore Keychain 化后的状态机。
/// 存储缝 TokenStoring 注入（风险 R3：swift test 只用 InMemoryTokenStore fake，
/// KeychainTokenStore 实现在 App target 绑定层，单测不碰 Keychain）。
/// fail-fast 口径不变：非法输入 throw 且不改状态；token/refreshToken 走密态缝，
/// baseURL/会话快照（user/tenants，非密）走 UserDefaults——都是用户显式登录的
/// 持久化，不是代码默认值兜底（ADR-0019 口径）。
final class SessionStoreTests: XCTestCase {

    private func makeDeps() -> (UserDefaults, InMemoryTokenStore) {
        let suite = "SessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, InMemoryTokenStore())
    }

    private func makeLoginResponse(
        token: String, tenantCode: String = "city-lab"
    ) -> LoginResponse {
        LoginResponse(
            token: token,
            refreshToken: "rt-\(token)",
            user: CurrentUser(id: "USER-A", username: "alice", displayName: "管理员", roleCode: "admin"),
            tenants: [
                MyTenant(tenantId: "TENANT-001", code: tenantCode, name: "市住建工程质量检测中心", roleIds: ["admin"]),
                MyTenant(tenantId: "TENANT-002", code: "district-lab", name: "区检测站", roleIds: ["technician"]),
            ]
        )
    }

    func testFreshStoreNeedsSetupWithNothingPersisted() {
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(store.state, .needsSetup)
        XCTAssertNil(store.baseURL)
        XCTAssertNil(store.token)
        XCTAssertNil(store.user)
        XCTAssertTrue(store.tenants.isEmpty)
    }

    func testSaveBaseURLValidatesFailFastThenNeedsLogin() throws {
    // fn: M01.F05.I02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertThrowsError(try store.saveBaseURL("   "))
        XCTAssertThrowsError(try store.saveBaseURL("not a url"))
        XCTAssertEqual(store.state, .needsSetup, "失败保存不许改状态")

        try store.saveBaseURL("https://api.example.invalid/")
        XCTAssertEqual(store.state, .needsLogin, "只配 baseURL 没登录 = needsLogin")
        XCTAssertEqual(store.baseURL, "https://api.example.invalid", "尾斜杠归一")
        XCTAssertNil(store.token)

        // 重启恢复：baseURL 从 UserDefaults 回来，仍 needsLogin
        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.state, .needsLogin)
        XCTAssertEqual(reborn.baseURL, "https://api.example.invalid")
    }

    func testAdoptLoginPersistsSecretsAndReadiesAcrossRebirth() throws {
    // fn: M01.F05.I02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeLoginResponse(token: "tk-1"))

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.token, "tk-1")
        XCTAssertEqual(store.refreshToken, "rt-tk-1")
        // 密态真落在注入缝里（Keychain 化的缝契约），不是 UserDefaults
        XCTAssertEqual(secrets.read("corekit.token"), "tk-1")
        XCTAssertNil(defaults.string(forKey: "corekit.token"), "token 不许落 UserDefaults")

        // 重启恢复：token+会话快照齐活，直接 ready
        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.state, .ready)
        XCTAssertEqual(reborn.token, "tk-1")
        XCTAssertEqual(reborn.user?.username, "alice")
        XCTAssertEqual(reborn.tenants.count, 2)
    }

    func testAdoptLoginSnapshotRoundTripSurvivesRebirth() throws {
    // fn: M00.F01
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeLoginResponse(token: "tk-2"))

        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.user?.id, "USER-A")
        XCTAssertEqual(reborn.user?.displayName, "管理员")
        XCTAssertEqual(reborn.tenants.first?.name, "市住建工程质量检测中心")
        XCTAssertEqual(reborn.tenants.first?.roleIds, ["admin"])
    }

    func testLogoutClearsSecretsKeepsBaseURLAndSurvivesRebirth() throws {
    // fn: M01.F05.I04
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeLoginResponse(token: "tk-3"))
        store.logout()

        XCTAssertEqual(store.state, .needsLogin, "登出只清会话，留 baseURL 直接回登录页")
        XCTAssertNil(store.token)
        XCTAssertNil(store.refreshToken)
        XCTAssertNil(store.user)
        XCTAssertTrue(store.tenants.isEmpty)
        XCTAssertNil(secrets.read("corekit.token"), "密态必须真删")

        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.state, .needsLogin)
        XCTAssertNil(reborn.token)
    }

    func testClearWipesEverythingBackToNeedsSetup() throws {
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeLoginResponse(token: "tk-4"))
        store.clear()
        XCTAssertEqual(store.state, .needsSetup)
        XCTAssertNil(store.baseURL)
        XCTAssertNil(secrets.read("corekit.token"))
    }

    func testExpirePathEqualsLogoutSemanticsOnRebirth() throws {
    // fn: M01.F05.I02
        // 401 拦截缝与登出共用本地清空语义：token 没了就回登录页，baseURL 留着。
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeLoginResponse(token: "tk-5"))
        secrets.delete("corekit.token")
        secrets.delete("corekit.refreshToken")

        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.state, .needsLogin, "密态缺失但 baseURL 在 = 回登录页而非配置页")
        XCTAssertNil(reborn.token)
        XCTAssertNil(reborn.user, "无 token 时不许呈现上一任会话快照")
        XCTAssertTrue(reborn.tenants.isEmpty)
    }
}

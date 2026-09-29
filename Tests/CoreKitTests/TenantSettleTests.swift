import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-009 T-1：登录选租户直进（M00.F02）红先行。
// settle 语义镜像家族 auth-context settleLogin（2026-09-23 裁定）：
// remembered（activeTenantId 记忆 ∩ 本次 tenants）?? 单租户 ?? 首位，
// 无选租户阻塞页；switchTenant 显式择定进记忆；awaiting_tenant 空列表
// 阻塞态非范围（家族注释自述仅空租户列表可达）。

final class TenantSettleTests: XCTestCase {

    private func makeDeps() -> (UserDefaults, InMemoryTokenStore) {
        let suite = "TenantSettleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, InMemoryTokenStore())
    }

    private func makeTenant(_ id: String, code: String) -> MyTenant {
        MyTenant(tenantId: id, code: code, name: "租户-\(code)", roleIds: ["admin"])
    }

    private func makeResponse(
        token: String, tenants: [MyTenant]
    ) -> LoginResponse {
        LoginResponse(
            token: token, refreshToken: "rt-\(token)",
            user: CurrentUser(id: "USER-A", username: "alice", displayName: "管理员", roleCode: "admin"),
            tenants: tenants
        )
    }

    private func twoTenantResponse(token: String) -> LoginResponse {
        makeResponse(token: token, tenants: [
            makeTenant("TENANT-001", code: "city-lab"),
            makeTenant("TENANT-002", code: "district-lab"),
        ])
    }

    // MARK: settle 直进

    func testAdoptLoginDirectEntersFirstTenantWhenNoMemory() throws {
    // fn: M00.F02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(twoTenantResponse(token: "tk-1"))
        XCTAssertEqual(store.activeTenantId, "TENANT-001", "无记忆多租户直进首位（家族裁定）")
        XCTAssertEqual(store.activeTenant?.code, "city-lab")
        XCTAssertNil(defaults.string(forKey: "corekit.token"), "activeTenantId 非密态，token 仍只落密缝")
    }

    func testAdoptLoginDirectEntersSingleTenant() throws {
    // fn: M00.F02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeResponse(token: "tk-2", tenants: [
            makeTenant("TENANT-009", code: "solo-lab"),
        ]))
        XCTAssertEqual(store.activeTenantId, "TENANT-009", "单租户直进该租户")
    }

    func testAdoptLoginRemembersPreviousChoiceOverFirst() throws {
    // fn: M00.F02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(twoTenantResponse(token: "tk-3"))
        XCTAssertEqual(store.activeTenantId, "TENANT-001")

        // 重登（不登出）：记忆租户仍是候选且在列 → 压过新响应首位
        let again = makeResponse(token: "tk-3b", tenants: [
            makeTenant("TENANT-002", code: "district-lab"),
            makeTenant("TENANT-001", code: "city-lab"),
        ])
        store.adoptLogin(again)
        XCTAssertEqual(store.activeTenantId, "TENANT-001", "remembered 压过首位")
    }

    func testRememberedStaleTenantFallsToFirst() throws {
    // fn: M00.F02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(twoTenantResponse(token: "tk-4"), preferredTenantId: "TENANT-002")
        XCTAssertEqual(store.activeTenantId, "TENANT-002")

        // 记忆租户已不在本次 tenants（被移出）→ 回落首位
        let shrunk = makeResponse(token: "tk-4b", tenants: [
            makeTenant("TENANT-001", code: "city-lab"),
        ])
        store.adoptLogin(shrunk)
        XCTAssertEqual(store.activeTenantId, "TENANT-001", "记忆失效回落首位")
    }

    // MARK: 切租户显式择定（M00.F02.I01 既有路径收尾）

    func testPreferredTenantExplicitChoiceWinsAndSurvivesRebirth() throws {
    // fn: M00.F02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(twoTenantResponse(token: "tk-5"), preferredTenantId: "TENANT-002")
        XCTAssertEqual(store.activeTenantId, "TENANT-002", "显式择定压过记忆与首位")

        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.state, .ready)
        XCTAssertEqual(reborn.activeTenantId, "TENANT-002", "重启恢复记忆租户")
        XCTAssertEqual(reborn.activeTenant?.code, "district-lab")
    }

    // MARK: 清除

    func testLogoutClearsActiveTenantMemory() throws {
    // fn: M00.F02
        let (defaults, secrets) = makeDeps()
        let store = SessionStore(defaults: defaults, secrets: secrets)
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(twoTenantResponse(token: "tk-6"), preferredTenantId: "TENANT-002")
        store.logout()
        XCTAssertNil(store.activeTenantId, "登出清记忆租户（会话级状态不跨登录）")

        let reborn = SessionStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reborn.state, .needsLogin)
        XCTAssertNil(reborn.activeTenantId, "重启后也不残留上一任记忆")
    }
}

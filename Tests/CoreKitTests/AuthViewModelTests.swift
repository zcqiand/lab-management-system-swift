import XCTest
import LabSharedGenerated
@testable import CoreKit

/// REQ-2026-003 T-3：认证流 ViewModel（登录/切换租户/登出）。
/// 网络缝 Seams 全注入——单测不发真网络；成功/失败对 SessionStore 状态机的影响
/// 与 App 层 APIGlue 无关（App 层只供缝实现）。
@MainActor
final class AuthViewModelTests: XCTestCase {

    private struct SeamedFailure: Error {}

    private func makeStore() -> SessionStore {
        let suite = "AuthViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SessionStore(defaults: defaults, secrets: InMemoryTokenStore())
    }

    private func makeResponse(token: String) -> LoginResponse {
        LoginResponse(
            token: token,
            refreshToken: "rt-\(token)",
            user: CurrentUser(id: "USER-A", username: "alice", displayName: "管理员", roleCode: "admin"),
            tenants: [
                MyTenant(tenantId: "TENANT-001", code: "city-lab", name: "市住建工程质量检测中心", roleIds: ["admin"]),
                MyTenant(tenantId: "TENANT-002", code: "district-lab", name: "区检测站", roleIds: ["technician"]),
            ]
        )
    }

    private func makeVM(
        store: SessionStore,
        nativeLogin: @escaping (String, String) async throws -> LoginResponse,
        switchTenant: @escaping (String) async throws -> LoginResponse,
        logout: @escaping () async throws -> Void
    ) -> AuthViewModel {
        AuthViewModel(
            store: store,
            seams: AuthViewModel.Seams(
                nativeLogin: nativeLogin, switchTenant: switchTenant, logout: logout
            )
        )
    }

    private func readyStore(token: String) throws -> SessionStore {
        let store = makeStore()
        try store.saveBaseURL("https://api.example.invalid")
        store.adoptLogin(makeResponse(token: token))
        return store
    }

    func testLoginSuccessAdoptsSessionIntoStore() async throws {
    // fn: M01.F05.I06
        let store = makeStore()
        try store.saveBaseURL("https://api.example.invalid")
        let vm = makeVM(
            store: store,
            nativeLogin: { username, password in
                XCTAssertEqual(username, "alice")
                XCTAssertEqual(password, "dev123456")
                return self.makeResponse(token: "tk-live")
            },
            switchTenant: { _ in throw SeamedFailure() },
            logout: {}
        )
        let ok = await vm.login(username: "alice", password: "dev123456")
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.token, "tk-live")
        XCTAssertEqual(store.user?.username, "alice")
        XCTAssertEqual(store.tenants.count, 2)
    }

    func testLoginFailureKeepsStoreStateAndReportsFailure() async throws {
        let store = makeStore()
        try store.saveBaseURL("https://api.example.invalid")
        let vm = makeVM(
            store: store,
            nativeLogin: { _, _ in throw SeamedFailure() },
            switchTenant: { _ in throw SeamedFailure() },
            logout: {}
        )
        let ok = await vm.login(username: "alice", password: "wrong")
        XCTAssertFalse(ok)
        guard case .failed(let message) = vm.phase else {
            return XCTFail("失败必须呈 failed 态，实际 \(vm.phase)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(store.state, .needsLogin, "登录失败不许改会话状态")
        XCTAssertNil(store.token)
    }

    func testSwitchTenantAdoptsNewToken() async throws {
    // fn: M00.F02.I01
        let store = try readyStore(token: "tk-old")
        let vm = makeVM(
            store: store,
            nativeLogin: { _, _ in throw SeamedFailure() },
            switchTenant: { tenantId in
                XCTAssertEqual(tenantId, "TENANT-002")
                return self.makeResponse(token: "tk-new")
            },
            logout: {}
        )
        let ok = await vm.switchTenant(to: "TENANT-002")
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.token, "tk-new", "切换后端换发新租户 token，旧 token 必须被覆盖")
        XCTAssertEqual(store.refreshToken, "rt-tk-new")
    }

    func testSwitchTenantFailureKeepsCurrentSession() async throws {
        let store = try readyStore(token: "tk-old")
        let vm = makeVM(
            store: store,
            nativeLogin: { _, _ in throw SeamedFailure() },
            switchTenant: { _ in throw SeamedFailure() },
            logout: {}
        )
        let ok = await vm.switchTenant(to: "TENANT-002")
        XCTAssertFalse(ok)
        guard case .failed = vm.phase else {
            return XCTFail("切换失败必须呈 failed 态，实际 \(vm.phase)")
        }
        XCTAssertEqual(store.state, .ready, "切换失败保持原会话")
        XCTAssertEqual(store.token, "tk-old")
    }

    func testLogoutAlwaysClearsLocallyEvenIfServerCallFails() async throws {
    // fn: M01.F05.I04
        let store = try readyStore(token: "tk-by")
        let vm = makeVM(
            store: store,
            nativeLogin: { _, _ in throw SeamedFailure() },
            switchTenant: { _ in throw SeamedFailure() },
            logout: { throw SeamedFailure() }
        )
        await vm.logout()
        XCTAssertEqual(vm.phase, .idle, "服务端登出失败不许把本地登出卡死")
        XCTAssertEqual(store.state, .needsLogin, "登出留 baseURL 直接回登录页")
        XCTAssertNil(store.token)
        XCTAssertNil(store.user)
        XCTAssertTrue(store.tenants.isEmpty)
    }
}

import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-010 T-1：SSO OAuth 2.0 授权码流（M01.F05.I03）红先行。
// 语义镜像家族 LoginPage RFC 6749 §4.1 两阶段：authorize → IdP → 回跳验
// state（一次性、防 CSRF）→ callback 换 lab 自家 JWT → adoptLogin settle。
// state 校验失败不得打 exchange 端点；配置缺失 fail-fast（ADR-0019）。

final class SsoTests: XCTestCase {

    private func makeDeps() -> (UserDefaults, InMemoryTokenStore) {
        let suite = "SsoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, InMemoryTokenStore())
    }

    private func makeLoginResponse(token: String) -> LoginResponse {
        LoginResponse(
            token: token, refreshToken: "rt-\(token)",
            user: CurrentUser(id: "USER-A", username: "alice", displayName: "管理员", roleCode: "admin"),
            tenants: [MyTenant(tenantId: "TENANT-001", code: "city-lab", name: "市住建", roleIds: ["admin"])]
        )
    }

    private func makeStore(_ deps: (UserDefaults, InMemoryTokenStore)) throws -> SessionStore {
        let store = SessionStore(defaults: deps.0, secrets: deps.1)
        try store.saveBaseURL("https://api.example.invalid")
        return store
    }

    // MARK: 纯函数

    func testGenerateStateIsBase64urlAndUnpredictable() {
    // fn: M01.F05.I03
        let a = SsoViewModel.generateState()
        let b = SsoViewModel.generateState()
        XCTAssertTrue(a.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
                      "32 字节 base64url 无填充 = 43 字符")
        XCTAssertNotEqual(a, b, "state 必须每次新生成（防重放）")
    }

    func testRedirectUriUsesSchemeWithFixedPath() {
    // fn: M01.F05.I03
        XCTAssertEqual(SsoViewModel.redirectUri(callbackScheme: "labman"), "labman://oauth/callback")
    }

    func testParseCallbackExtractsCodeAndState() {
    // fn: M01.F05.I03
        let url = URL(string: "labman://oauth/callback?code=CODE-1&state=ST-1")!
        let parsed = SsoViewModel.parseCallback(url)
        XCTAssertEqual(parsed?.code, "CODE-1")
        XCTAssertEqual(parsed?.state, "ST-1")
        XCTAssertNil(SsoViewModel.parseCallback(URL(string: "labman://oauth/callback")!),
                     "缺 code/state 的回调不收")
    }

    // MARK: 登录流

    func testLoginHappyPathExchangesAndAdopts() async throws {
    // fn: M01.F05.I03
        let deps = makeDeps()
        let store = try makeStore(deps)
        var captured: SsoCallbackRequest?
        // authorize 缝捕获 VM 生成的 state，webSession 缝原样回传（IdP 回跳语义）。
        var stateIssued: String?
        let vm = SsoViewModel(
            store: store,
            seams: .init(
                authorize: { _, _, redirectUri, state in
                    stateIssued = state
                    XCTAssertEqual(redirectUri, "labman://oauth/callback")
                    return SsoRedirect(
                        authorizeUrl: "https://saas.example.invalid/authorize?state=\(state)",
                        state: state
                    )
                },
                exchange: { request in
                    captured = request
                    return self.makeLoginResponse(token: "tk-sso-1")
                },
                openWebSession: { authorizeUrl, scheme in
                    XCTAssertEqual(scheme, "labman")
                    return URL(string: "\(scheme)://oauth/callback?code=CODE-1&state=\(stateIssued!)")!
                }
            )
        )
        let ok = await vm.login(clientId: "lab-management", callbackScheme: "labman")
        XCTAssertTrue(ok)
        XCTAssertEqual(store.state, .ready, "换 token 成功必须 adopt 进 ready")
        XCTAssertEqual(store.token, "tk-sso-1")
        XCTAssertEqual(captured?.grantType, .authorizationCode)
        XCTAssertEqual(captured?.code, "CODE-1")
        XCTAssertEqual(captured?.redirectUri, "labman://oauth/callback")
        XCTAssertEqual(captured?.state, stateIssued, "exchange 的 state 与 authorize 发出的一致")
    }

    func testLoginStateMismatchBlocksExchange() async throws {
    // fn: M01.F05.I03
        let deps = makeDeps()
        let store = try makeStore(deps)
        let vm = SsoViewModel(
            store: store,
            seams: .init(
                authorize: { _, _, _, state in
                    SsoRedirect(authorizeUrl: "https://saas/x?state=\(state)", state: state)
                },
                exchange: { _ in
                    XCTFail("state 校验失败不得打 exchange 端点")
                    throw CallShouldNotHappen()
                },
                openWebSession: { _, scheme in
                    URL(string: "\(scheme)://oauth/callback?code=CODE-2&state=TAMPERED")!
                }
            )
        )
        let ok = await vm.login(clientId: "lab-management", callbackScheme: "labman")
        XCTAssertFalse(ok, "回跳 state 被换必须拒绝")
        XCTAssertEqual(store.state, .needsLogin, "拒绝换 token 不进会话")
        if case .failed(let message) = vm.phase {
            XCTAssertTrue(message.contains("state"), "失败态须说明 state 校验")
        } else {
            XCTFail("必须报 failed 态")
        }
    }

    func testLoginMissingConfigFailsFastBeforeAuthorize() async throws {
    // fn: M01.F05.I03
        let deps = makeDeps()
        let store = try makeStore(deps)
        let vm = SsoViewModel(
            store: store,
            seams: .init(
                authorize: { _, _, _, _ in
                    XCTFail("配置缺失不得发起 authorize")
                    throw CallShouldNotHappen()
                },
                exchange: { _ in
                    XCTFail("配置缺失不得打 exchange")
                    throw CallShouldNotHappen()
                },
                openWebSession: { _, _ in
                    XCTFail("配置缺失不得开浏览器会话")
                    throw CallShouldNotHappen()
                }
            )
        )
        let ok = await vm.login(clientId: "", callbackScheme: "labman")
        XCTAssertFalse(ok, "client_id 空 = fail-fast（ADR-0019 不兜底）")
        if case .failed = vm.phase {} else { XCTFail("必须报 failed 态") }
    }

    func testExchangeFailureSurfacesErrorAndStaysOut() async throws {
    // fn: M01.F05.I03
        struct Boom: Error {}
        let deps = makeDeps()
        let store = try makeStore(deps)
        var stateIssued: String?
        let vm = SsoViewModel(
            store: store,
            seams: .init(
                authorize: { _, _, _, state in
                    stateIssued = state
                    return SsoRedirect(authorizeUrl: "https://saas/x?state=\(state)", state: state)
                },
                exchange: { _ in throw Boom() },
                openWebSession: { _, scheme in
                    URL(string: "\(scheme)://oauth/callback?code=CODE-3&state=\(stateIssued ?? "ST-X")")!
                }
            )
        )
        let ok = await vm.login(clientId: "lab-management", callbackScheme: "labman")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.state, .needsLogin, "换 token 失败不进会话")
        XCTAssertNil(store.token)
        if case .failed = vm.phase {} else { XCTFail("必须报 failed 态") }
    }

    // MARK: SSO 配置持久化（SessionStore 扩展，ADR-0019 显式配置）

    func testSaveSsoConfigFailsFastAndSurvivesRebirth() throws {
    // fn: M01.F05.I03
        let deps = makeDeps()
        let store = try makeStore(deps)
        XCTAssertThrowsError(try store.saveSsoConfig(clientId: "  ", callbackScheme: "labman"),
                             "空 client_id 拒存")
        XCTAssertThrowsError(try store.saveSsoConfig(clientId: "lab-management", callbackScheme: ""),
                             "空回调 scheme 拒存")

        try store.saveSsoConfig(clientId: "lab-management", callbackScheme: "labman")
        XCTAssertEqual(store.ssoClientId, "lab-management")
        XCTAssertEqual(store.ssoCallbackScheme, "labman")

        let reborn = SessionStore(defaults: deps.0, secrets: deps.1)
        XCTAssertEqual(reborn.ssoClientId, "lab-management", "配置同 baseURL 属显式配置，重启恢复")
        XCTAssertEqual(reborn.ssoCallbackScheme, "labman")
    }

    func testClearWipesSsoConfigBackToNeedsSetup() throws {
    // fn: M01.F05.I03
        let deps = makeDeps()
        let store = try makeStore(deps)
        try store.saveSsoConfig(clientId: "lab-management", callbackScheme: "labman")
        store.clear()
        XCTAssertNil(store.ssoClientId, "全清连配置一起清（回配置页重配）")
        XCTAssertNil(store.ssoCallbackScheme)
    }
}

private struct CallShouldNotHappen: Error {}

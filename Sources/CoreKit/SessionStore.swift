import Foundation
import LabSharedGenerated

// REQ-2026-003 T-2：会话状态机三态化 + 密态 Keychain 化。
// needsSetup=未配后端；needsLogin=有 baseURL 无会话（登录页）；ready=已登录。
// token/refreshToken 走 TokenStoring 注入缝（App 层绑 Keychain，测试绑内存 fake）；
// baseURL/会话快照（user/tenants，非密）走 UserDefaults——都是用户显式登录的持久化，
// 不是代码默认值兜底（§1 / ADR-0019）。401 失效与登出共用 logout 语义（I02/I04）。

/// 会话状态存储：配置页（needsSetup）→ 登录页（needsLogin）→ 业务页（ready）。
public final class SessionStore {

    public enum SessionState: Equatable {
        case needsSetup
        case needsLogin
        case ready
    }

    private static let baseURLKey = "corekit.baseURL"
    private static let sessionKey = "corekit.session"
    static let tokenKey = "corekit.token"
    static let refreshTokenKey = "corekit.refreshToken"

    private let defaults: UserDefaults
    private let secrets: TokenStoring

    public private(set) var state: SessionState
    public private(set) var baseURL: String?
    public private(set) var token: String?
    public private(set) var refreshToken: String?
    public private(set) var user: CurrentUser?
    public private(set) var tenants: [MyTenant] = []

    public init(defaults: UserDefaults, secrets: TokenStoring) {
        self.defaults = defaults
        self.secrets = secrets
        baseURL = defaults.string(forKey: Self.baseURLKey)
        token = secrets.read(Self.tokenKey)
        refreshToken = secrets.read(Self.refreshTokenKey)

        if token?.isEmpty == false {
            if let data = defaults.data(forKey: Self.sessionKey),
               let snapshot = try? JSONDecoder().decode(CurrentUserSession.self, from: data) {
                user = snapshot.user
                tenants = snapshot.tenants
            }
            state = baseURL?.isEmpty == false ? .ready : .needsSetup
        } else {
            // 密态缺失：上一任会话快照不许呈现（失效即回登录页，I02）。
            token = nil
            refreshToken = nil
            user = nil
            tenants = []
            defaults.removeObject(forKey: Self.sessionKey)
            state = baseURL?.isEmpty == false ? .needsLogin : .needsSetup
        }
    }

    /// 只配置后端地址（REQ-2026-003 T-2：配置页瘦身，token 改由登录换发）。
    /// 校验失败 throw 且不改状态（fail-fast 不留半配置态）；
    /// 成功后有会话 → ready 并重注 Bearer，否则 needsLogin。
    public func saveBaseURL(_ raw: String) throws {
        let normalized = try APIClient.normalizeBaseURL(raw)
        defaults.set(normalized, forKey: Self.baseURLKey)
        baseURL = normalized
        if let token {
            OpenAPIClientAPI.basePath = normalized
            OpenAPIClientAPI.customHeaders["Authorization"] = "Bearer \(token)"
            state = .ready
        } else {
            state = .needsLogin
        }
    }

    /// 登录/切换租户成功后的入账（switch-tenant 换发的也是 LoginResponse）：
    /// 密态落缝 + 会话快照落 defaults + Bearer 注入，状态进 ready。
    public func adoptLogin(_ response: LoginResponse) {
        secrets.save(Self.tokenKey, response.token)
        token = response.token
        if let refresh = response.refreshToken, refresh.isEmpty == false {
            secrets.save(Self.refreshTokenKey, refresh)
            refreshToken = refresh
        } else {
            secrets.delete(Self.refreshTokenKey)
            refreshToken = nil
        }
        let snapshot = CurrentUserSession(
            user: response.user, tenants: response.tenants, currentTenantId: nil
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.sessionKey)
        }
        user = response.user
        tenants = response.tenants
        if let baseURL {
            // baseURL 已过校验，这里只为重注 basePath + Bearer（失败不掩盖登录成功）。
            _ = try? APIClient.bootstrap(baseURL: baseURL, token: response.token)
        }
        state = .ready
    }

    /// 登出/401 失效共用（I02/I04）：清密态 + 快照，留 baseURL 直接回登录页。
    public func logout() {
        secrets.delete(Self.tokenKey)
        secrets.delete(Self.refreshTokenKey)
        token = nil
        refreshToken = nil
        defaults.removeObject(forKey: Self.sessionKey)
        user = nil
        tenants = []
        state = .needsLogin
        OpenAPIClientAPI.customHeaders.removeValue(forKey: "Authorization")
    }

    /// 全清回配置页（换后端入口）。
    public func clear() {
        logout()
        defaults.removeObject(forKey: Self.baseURLKey)
        baseURL = nil
        state = .needsSetup
    }
}

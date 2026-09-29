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
    private static let activeTenantIdKey = "corekit.activeTenantId"
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
    /// 登录 settle 直进的记忆租户（M00.F02）：remembered ?? 单租户 ?? 首位。
    /// 会话级 UI 态非密态——落 defaults 与快照同源，登出即清。
    public private(set) var activeTenantId: String?

    /// 记忆租户对象（stale 时自然为 nil，呈现层直接用）。
    public var activeTenant: MyTenant? {
        tenants.first { $0.tenantId == activeTenantId }
    }

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
                // hydrate 记忆租户：defaults 键为主、快照 currentTenantId 为辅，
                // 都不在本次 tenants 时 activeTenant 计算属性自然为 nil。
                let remembered = defaults.string(forKey: Self.activeTenantIdKey)
                activeTenantId = remembered ?? snapshot.currentTenantId
            }
            state = baseURL?.isEmpty == false ? .ready : .needsSetup
        } else {
            // 密态缺失：上一任会话快照不许呈现（失效即回登录页，I02）。
            token = nil
            refreshToken = nil
            user = nil
            tenants = []
            activeTenantId = nil
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
    /// M00.F02 settle 直进：目标租户 = 显式择定（preferredTenantId，切租户
    /// 路径）∩ 本次 tenants ?? 记忆 ?? 单租户 ?? 首位（家族 settleLogin
    /// 2026-09-23 裁定同款）；快照 currentTenantId 同步写 settled 值。
    public func adoptLogin(_ response: LoginResponse, preferredTenantId: String? = nil) {
        secrets.save(Self.tokenKey, response.token)
        token = response.token
        if let refresh = response.refreshToken, refresh.isEmpty == false {
            secrets.save(Self.refreshTokenKey, refresh)
            refreshToken = refresh
        } else {
            secrets.delete(Self.refreshTokenKey)
            refreshToken = nil
        }
        user = response.user
        tenants = response.tenants
        let remembered = tenants.first { $0.tenantId == preferredTenantId }
            ?? tenants.first { $0.tenantId == activeTenantId }
        let single = tenants.count == 1 ? tenants[0] : nil
        let target = remembered ?? single ?? tenants.first
        activeTenantId = target?.tenantId
        defaults.set(activeTenantId, forKey: Self.activeTenantIdKey)
        let snapshot = CurrentUserSession(
            user: response.user, tenants: response.tenants, currentTenantId: activeTenantId
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.sessionKey)
        }
        if let baseURL {
            // baseURL 已过校验，这里只为重注 basePath + Bearer（失败不掩盖登录成功）。
            _ = try? APIClient.bootstrap(baseURL: baseURL, token: response.token)
        }
        state = .ready
    }

    /// 登出/401 失效共用（I02/I04）：清密态 + 快照，留 baseURL 直接回登录页。
    /// activeTenantId 是会话级状态，同批清（REQ-2026-009 Q2 裁定）。
    public func logout() {
        secrets.delete(Self.tokenKey)
        secrets.delete(Self.refreshTokenKey)
        token = nil
        refreshToken = nil
        defaults.removeObject(forKey: Self.sessionKey)
        defaults.removeObject(forKey: Self.activeTenantIdKey)
        user = nil
        tenants = []
        activeTenantId = nil
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

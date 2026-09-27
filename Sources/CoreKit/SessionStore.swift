import Foundation
import LabSharedGenerated

// REQ-2026-002 T-2（AC-1，Q1 人裁「首启配置页」）：会话配置状态机。
// fail-fast 口径：未配置绝不发 API 请求，无任何默认值兜底（§1）；
// UserDefaults 是用户显式输入的持久化，不是代码兜底（REQ-2026-002 风险 R2）。

/// 会话配置存储：App 首启呈配置页，保存校验通过后进 ready。
/// 校验复用 APIClient.bootstrap（trim/URL 合法性/尾斜杠归一/Bearer 注入一条龙）。
public final class SessionStore {

    public enum SessionState: Equatable {
        case needsSetup
        case ready
    }

    private static let baseURLKey = "corekit.baseURL"
    private static let tokenKey = "corekit.token"

    private let defaults: UserDefaults

    public private(set) var state: SessionState
    public private(set) var baseURL: String?
    public private(set) var token: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = defaults.string(forKey: Self.baseURLKey)
        token = defaults.string(forKey: Self.tokenKey)
        state = (baseURL?.isEmpty == false && token?.isEmpty == false) ? .ready : .needsSetup
    }

    /// 校验并持久化：失败 throw 且不改任何状态（fail-fast 不留半配置态）。
    public func save(baseURL: String, token: String) throws {
        let config = try APIClient.bootstrap(baseURL: baseURL, token: token)
        defaults.set(config.baseURL, forKey: Self.baseURLKey)
        defaults.set(config.token, forKey: Self.tokenKey)
        self.baseURL = config.baseURL
        self.token = config.token
        state = .ready
    }

    /// 清空回配置页（登出/换后端入口）。
    public func clear() {
        defaults.removeObject(forKey: Self.baseURLKey)
        defaults.removeObject(forKey: Self.tokenKey)
        baseURL = nil
        token = nil
        state = .needsSetup
    }
}

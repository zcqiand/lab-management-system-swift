import Foundation
import LabSharedGenerated

/// 会话配置（REQ-2026-001 Q1 结论）：显式注入，缺失即 fail-fast，禁 env 默认值兜底。
public struct SessionConfig {
    public let baseURL: String
    public let token: String

    public init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

public enum APIConfigError: Error, Equatable {
    case missingBaseURL
    case missingToken
    case invalidBaseURL(String)
}

/// 生成 client（LabSharedGenerated）的唯一配置入口。
/// 登录 UI 落地前，token 由调用方显式提供（REQ-2026-001 Q1）。
public enum APIClient {

    /// URL 校验/归一（trim、scheme+host 必备、尾斜杠剥离）。
    /// bootstrap 与 SessionStore.saveBaseURL 共用；生成层按 basePath + path 拼
    /// URLString，尾斜杠不归一会打歪（双斜杠）。
    public static func normalizeBaseURL(_ raw: String) throws -> String {
        let trimmedBase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw APIConfigError.missingBaseURL }
        guard let url = URL(string: trimmedBase), url.scheme != nil, url.host != nil else {
            throw APIConfigError.invalidBaseURL(raw)
        }
        var normalized = url.absoluteString
        if normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized
    }

    /// 校验并注入 baseURL + Bearer 会话。任何缺失/非法立即 throw，不兜底。
    @discardableResult
    public static func bootstrap(baseURL: String, token: String) throws -> SessionConfig {
        let normalized = try normalizeBaseURL(baseURL)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw APIConfigError.missingToken }

        OpenAPIClientAPI.basePath = normalized
        OpenAPIClientAPI.customHeaders["Authorization"] = "Bearer \(trimmedToken)"
        return SessionConfig(baseURL: normalized, token: trimmedToken)
    }
}

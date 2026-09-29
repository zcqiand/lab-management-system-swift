import Foundation
import LabSharedGenerated

// REQ-2026-010 T-1：SSO OAuth 2.0 授权码流原生形态（M01.F05.I03）。
// 语义镜像家族 LoginPage RFC 6749 §4.1 两阶段：
//   authorize（response_type=code + client_id + redirect_uri + state 防 CSRF）
//   → ASWebAuthenticationSession 跳 IdP（saas）
//   → 回跳验 state（一次性、防 CSRF，不匹配绝不打 exchange）
//   → callback 换 lab 自家 JWT → store.adoptLogin settle 直进（REQ-2026-009）。
// 三缝注入：authorize / exchange 打生成物 AuthAPI，openWebSession App 层绑
// ASWebAuthenticationSession（测试绑 stub）。client_id/回调 scheme 是用户
// 显式配置（SessionStore 落账），缺失 fail-fast 不兜底字面量（ADR-0019）。

/// SSO 授权码流视图模型：state 生成/校验为纯函数，网络与浏览器会话走缝。
public final class SsoViewModel: ObservableObject {

    /// 浏览器会话缝：入参 (authorizeUrl, callbackScheme)，回跳 URL 出参。
    /// App 层实现 = ASWebAuthenticationSession(prefersEphemeralWebBrowserSession)。
    public struct Seams {
        public var authorize: (OAuthResponseType, String, String, String) async throws -> SsoRedirect
        public var exchange: (SsoCallbackRequest) async throws -> LoginResponse
        public var openWebSession: (String, String) async throws -> URL

        public init(authorize: @escaping (OAuthResponseType, String, String, String) async throws -> SsoRedirect,
                    exchange: @escaping (SsoCallbackRequest) async throws -> LoginResponse,
                    openWebSession: @escaping (String, String) async throws -> URL) {
            self.authorize = authorize
            self.exchange = exchange
            self.openWebSession = openWebSession
        }
    }

    public enum Phase: Equatable {
        case idle
        case busy
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle

    private let store: SessionStore
    private let seams: Seams

    public init(store: SessionStore, seams: Seams) {
        self.store = store
        self.seams = seams
    }

    // MARK: 纯函数

    /// 32 字节随机 → base64url 无填充（43 字符），每次新生成防重放。
    public static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices {
            bytes[i] = UInt8.random(in: .min ... .max, using: &rng)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 回调 redirect_uri：scheme 由用户配置，路径固定 /oauth/callback。
    /// 须与 saas oauth_client 白名单逐字一致（注册为跨仓人裁项，Q2）。
    public static func redirectUri(callbackScheme: String) -> String {
        "\(callbackScheme)://oauth/callback"
    }

    /// 解析回跳 URL 的 code + state；缺任一项不收（nil）。
    public static func parseCallback(_ url: URL) -> (code: String, state: String)? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value,
              code.isEmpty == false, state.isEmpty == false else { return nil }
        return (code, state)
    }

    // MARK: 登录流

    /// 完整授权码流。返回是否已 adopt 进 ready；失败置 failed 态、store 不动。
    @discardableResult
    public func login(clientId: String, callbackScheme: String) async -> Bool {
        // ADR-0019：配置缺失 fail-fast，不发 authorize / 不开浏览器会话。
        let trimmedClient = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScheme = callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedClient.isEmpty == false, trimmedScheme.isEmpty == false else {
            phase = .failed("SSO 配置缺失：请先在配置页填写 client_id 与回调 scheme")
            return false
        }
        phase = .busy
        do {
            let state = Self.generateState()
            let redirectURI = Self.redirectUri(callbackScheme: trimmedScheme)
            let redirect = try await seams.authorize(.code, trimmedClient, redirectURI, state)
            let callbackURL = try await seams.openWebSession(redirect.authorizeUrl, trimmedScheme)
            guard let callback = Self.parseCallback(callbackURL) else {
                phase = .failed("回调缺少 code/state：已取消或回跳不完整")
                return false
            }
            // state 一次性校验（防 CSRF）：回跳值与发出值不一致，绝不打 exchange。
            guard callback.state == state else {
                phase = .failed("state 校验失败：回跳 state 与发出值不一致，已拒绝换 token")
                return false
            }
            let request = SsoCallbackRequest(
                grantType: .authorizationCode,
                code: callback.code,
                redirectUri: redirectURI,
                state: callback.state
            )
            let response = try await seams.exchange(request)
            store.adoptLogin(response)
            phase = .idle
            return true
        } catch {
            // 换 token 失败（含 INVALID_GRANT）：报失败态不进会话，可重试。
            phase = .failed("SSO 登录失败：\(error.localizedDescription)")
            return false
        }
    }
}

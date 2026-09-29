import AuthenticationServices
import Foundation
import UIKit

// REQ-2026-010 T-2（M01.F05.I03）：SsoViewModel.openWebSession 缝的 App 层
// 实现——ASWebAuthenticationSession 单次浏览器会话跳 IdP，自定义 scheme 回跳
// 由系统劫持回 App。prefersEphemeral：不共享用户 Safari 的 cookie/身份。

enum WebAuthSession {

    struct Canceled: Error {}
    struct BadAuthorizeURL: Error {}

    /// 入参 (authorizeUrl, callbackScheme) → 回跳 URL 出参（CoreKit 纯函数解析）。
    static func open(authorizeUrl: String, callbackScheme: String) async throws -> URL {
        struct Holder {
            static var session: ASWebAuthenticationSession?
            static var anchor: Anchor?
        }
        final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
            func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first ?? ASPresentationAnchor()
            }
        }
        guard let url = URL(string: authorizeUrl) else { throw BadAuthorizeURL() }
        return try await withCheckedThrowingContinuation { continuation in
            let anchor = Anchor()
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                Holder.session = nil
                Holder.anchor = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    // 用户取消（error = ASWebAuthenticationSessionError.canceledLogin）
                    // 与系统错误同路抛回，CoreKit 统一落 failed 态。
                    continuation.resume(throwing: error ?? Canceled())
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = true
            // 会话与 anchor 须活到回调完成，闭包捕获不放——静态持有一条命。
            Holder.session = session
            Holder.anchor = anchor
            session.start()
        }
    }
}

import Combine
import Foundation
import LabSharedGenerated

// REQ-2026-003 T-3：认证流 ViewModel——原生登录（I06）/ 租户切换（M00.F02.I01）/
// 登出（I04）。网络缝 Seams 注入：CoreKit 只管状态机，网络实现由 App 层
// APIGlue（生成物唯一入口）供，单测注入 fake 不发真网络。

@MainActor
public final class AuthViewModel: ObservableObject {

    /// 网络缝：签名对齐生成层 AuthAPI 的三个会话端点。
    public struct Seams {
        public var nativeLogin: (_ username: String, _ password: String) async throws -> LoginResponse
        public var switchTenant: (_ tenantId: String) async throws -> LoginResponse
        public var logout: () async throws -> Void

        public init(
            nativeLogin: @escaping (_: String, _: String) async throws -> LoginResponse,
            switchTenant: @escaping (_: String) async throws -> LoginResponse,
            logout: @escaping () async throws -> Void
        ) {
            self.nativeLogin = nativeLogin
            self.switchTenant = switchTenant
            self.logout = logout
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

    /// 原生登录（I06）：成功 adopt 进 store（state→ready），失败保持现状报 failed。
    @discardableResult
    public func login(username: String, password: String) async -> Bool {
        phase = .busy
        do {
            let response = try await seams.nativeLogin(username, password)
            store.adoptLogin(response)
            phase = .idle
            return true
        } catch {
            phase = .failed(Self.message(of: error))
            return false
        }
    }

    /// 租户切换（M00.F02.I01）：后端换发新租户 token（LoginResponse 同形），
    /// 成功覆盖旧会话；失败保持原会话可重试。择定租户进记忆（M00.F02 settle）。
    @discardableResult
    public func switchTenant(to tenantId: String) async -> Bool {
        phase = .busy
        do {
            let response = try await seams.switchTenant(tenantId)
            store.adoptLogin(response, preferredTenantId: tenantId)
            phase = .idle
            return true
        } catch {
            phase = .failed(Self.message(of: error))
            return false
        }
    }

    /// 登出（I04）：服务端通知尽力而为，本地清空必达（回登录页不等网络）。
    public func logout() async {
        phase = .busy
        try? await seams.logout()
        store.logout()
        phase = .idle
    }

    private static func message(of error: Error) -> String {
        if case ErrorResponse.error(let code, _, _, _) = error {
            return "请求失败（HTTP \(code)）"
        }
        return String(describing: error)
    }
}

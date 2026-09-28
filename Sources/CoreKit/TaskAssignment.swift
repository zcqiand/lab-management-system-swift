import Combine
import Foundation
import LabSharedGenerated

// REQ-2026-004 T-1：任务分配 CoreKit（M03.F02.I02 安排/取消检测人员与计划日期）。
// 队列（I01）复用 ReceiptListViewModel（query.flowStatus = .taskAssignment 预设）；
// act（I05）复用 ReceivingFlowViewModel（operator = 真会话身份，REQ-2026-004 Q3）。
// 本文件只有安排/取消一件新事：手填姓名+日期（Q2 裁定，assigneeId 恒不传）。

/// 安排/取消表单错误：安排语义下两字段都必填，缺一 fail-fast 不打端点。
public enum AssignTaskError: Error, Equatable {
    case invalidFields
}

/// 安排/取消 VM：手填「检测人员姓名 + 计划检测日期」两个文本框（家族同款）。
/// - 安排：两字段 trim 后都非空 → AssignTaskRequest(assigneeId: nil, name, date)
/// - 取消：两字段全空 → 全 nil 清空请求（单子回未分配）
/// 失败以 errorMessage 呈现，不清用户输入（AC-6）。
/// 实现 ObservableObject（Combine，非 UI 框架）供 SwiftUI @StateObject 订阅；
/// 变更点显式 objectWillChange.send()，与 ReceiptListViewModel 同款。
public final class AssignTaskViewModel: ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()
    private func notify() { objectWillChange.send() }

    public private(set) var isSaving = false {
        willSet { notify() }
    }
    public private(set) var errorMessage: String? {
        willSet { notify() }
    }

    public var assigneeName = ""
    public var plannedTestDate = ""

    /// 网络缝：(单 id, 请求) → 更新后的接样单；UI 壳注入生成层 receiptsAssignTask。
    private let persist: (String, AssignTaskRequest) async throws -> SampleReceipt

    public init(persist: @escaping (String, AssignTaskRequest) async throws -> SampleReceipt) {
        self.persist = persist
    }

    /// 组装请求。任一字段非空（trim 后）= 安排语义，两字段都必填；
    /// 全空 = 取消安排（全 nil）。
    public func makeRequest() throws -> AssignTaskRequest {
        let name = assigneeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = plannedTestDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty && date.isEmpty {
            return AssignTaskRequest(assigneeId: nil, assigneeName: nil, plannedTestDate: nil)
        }
        guard !name.isEmpty, !date.isEmpty else { throw AssignTaskError.invalidFields }
        return AssignTaskRequest(assigneeId: nil, assigneeName: name, plannedTestDate: date)
    }

    /// 保存：校验不过或端点失败都返回 nil 并落 errorMessage（不打断 UI）。
    @discardableResult
    public func save(id: String) async -> SampleReceipt? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let request: AssignTaskRequest
        do {
            request = try makeRequest()
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
        do {
            return try await persist(id, request)
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }
}

import Foundation
import LabSharedGenerated

// REQ-2026-001 T-4：接样管理 CoreKit ViewModel（纯 Swift，禁 SwiftUI/UIKit）。
// 网络缝 = 注入 async 闭包，单测不发真网络；UI 壳（后续需求）注入生成层调用。

/// 列表 filter 三态。SSOT：shared tsp routes/sample-receipts.tsp listReceipts 注释
/// （不传=全部 / not_yet=停在本环节待提交 / submitted=已提交至下一环节，
/// 其余值不参与过滤等同不传）——枚举从类型层面杜绝第四态。
public enum ReceiptFilter: String, CaseIterable, Equatable {
    case all
    case notYet = "not_yet"
    case submitted = "submitted"

    /// 映射为 listReceipts 的 query 值：all → nil（不传）。
    public var queryValue: String? {
        self == .all ? nil : rawValue
    }
}

/// 接样单列表查询参数（分页 1-based，家族约定 page=1/pageSize=20）。
public struct ReceiptListQuery: Equatable {
    public var page: Int
    public var pageSize: Int
    public var keyword: String?
    public var flowStatus: FlowStatus?
    public var filter: ReceiptFilter

    public init(
        page: Int = 1, pageSize: Int = 20,
        keyword: String? = nil, flowStatus: FlowStatus? = nil,
        filter: ReceiptFilter = .all
    ) {
        self.page = page
        self.pageSize = pageSize
        self.keyword = keyword
        self.flowStatus = flowStatus
        self.filter = filter
    }
}

/// 接样单列表 VM：分页装载 + act 结果回填。
public final class ReceiptListViewModel {

    public private(set) var items: [SampleReceipt] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var hasMore = true
    public var query = ReceiptListQuery()

    private let provider: (ReceiptListQuery) async throws -> [SampleReceipt]

    public init(provider: @escaping (ReceiptListQuery) async throws -> [SampleReceipt]) {
        self.provider = provider
    }

    /// 回到第 1 页整表替换。
    public func load() async {
        query.page = 1
        await fetch(reset: true)
    }

    /// 追加下一页；空页回滚页码并停。
    public func loadNextPage() async {
        query.page += 1
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let requestedPage = query.page
        do {
            let fetched = try await provider(query)
            if reset {
                items = fetched
            } else if fetched.isEmpty {
                query.page = max(1, requestedPage - 1)
                hasMore = false
                return
            } else {
                items += fetched
            }
            hasMore = fetched.count >= query.pageSize
        } catch {
            errorMessage = String(describing: error)
            if !reset { query.page = max(1, requestedPage - 1) }
        }
    }

    /// act 结果回填：按 id 更新 flowStatus，未涉及单保持原状。
    public func apply(_ results: [FlowActionResult]) {
        guard !results.isEmpty else { return }
        let byId = Dictionary(
            results.map { ($0.id, $0) },
            uniquingKeysWith: { _, latter in latter }
        )
        items = items.map { item in
            guard let result = byId[item.id] else { return item }
            var updated = item
            if let status = result.flowStatus { updated.flowStatus = status }
            return updated
        }
    }
}

/// act 选区校验错误：空选择 fail-fast，不打端点（§1 禁兜底同源）。
public enum FlowActionError: Error, Equatable {
    case emptySelection
}

/// 接样阶段 act 流转 VM（M03.F01.I08，POST /api/receipts/receiving/act 三动作统一）。
/// 能否 submit/return/withdraw 的流转语义在后端裁决——本 VM 只管
/// 选区校验 + 请求体组装 + 结果透传，不发明客户端状态机策略。
public final class ReceivingFlowViewModel {

    public let operatorName: String

    private let act: (FlowAction, [String], String?) async throws -> [FlowActionResult]

    public init(
        operatorName: String,
        act: @escaping (FlowAction, [String], String?) async throws -> [FlowActionResult]
    ) {
        self.operatorName = operatorName
        self.act = act
    }

    /// 执行流转并透传逐单结果（ok=false 是业务失败，不 throw——由 UI 按单呈现）。
    @discardableResult
    public func perform(
        _ action: FlowAction, ids: [String], reason: String? = nil
    ) async throws -> [FlowActionResult] {
        guard !ids.isEmpty else { throw FlowActionError.emptySelection }
        return try await act(action, ids, reason)
    }

    /// 组装生成层 FlowActionRequest（UI 壳直连生成 API 时复用）。
    public func makeRequest(
        _ action: FlowAction, ids: [String], reason: String? = nil
    ) throws -> FlowActionRequest {
        guard !ids.isEmpty else { throw FlowActionError.emptySelection }
        return FlowActionRequest(ids: ids, action: action, operator: operatorName, reason: reason)
    }
}

import Combine
import Foundation
import LabSharedGenerated

// REQ-2026-001 T-4：接样管理 CoreKit ViewModel（纯 Swift，禁 SwiftUI/UIKit）。
// 网络缝 = 注入 async 闭包，单测不发真网络；UI 壳注入生成层调用（REQ-2026-002）。
// 列表/详情 VM 实现 ObservableObject（Combine，非 UI 框架）供 SwiftUI @StateObject
// 订阅；变更点显式 objectWillChange.send()，不用 @Published 以保持「公开只读」。

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
public final class ReceiptListViewModel: ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()
    private func notify() { objectWillChange.send() }

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
        notify()
        isLoading = true
        errorMessage = nil
        defer {
            notify()
            isLoading = false
        }
        let requestedPage = query.page
        do {
            let fetched = try await provider(query)
            notify()
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
            notify()
            errorMessage = String(describing: error)
            if !reset { query.page = max(1, requestedPage - 1) }
        }
    }

    /// act 结果回填：按 id 更新 flowStatus，未涉及单保持原状。
    public func apply(_ results: [FlowActionResult]) {
        guard !results.isEmpty else { return }
        notify()
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

// MARK: - REQ-2026-002 T-2：表单（I02）/ 详情（I06）/ 删除（I03）

/// 接样单表单字段 = CreateSampleReceiptRequest 必填集（shared tsp models/sample-receipt.tsp）。
/// 可选字段本需求 UI 不做，后续需求扩列时保持 Equatable 语义（PATCH diff 依赖它）。
public struct ReceiptFormFields: Equatable {
    public var contractId: String
    public var commissionCode: String
    public var commissionDate: String
    public var categoryCode: String
    public var receivedBy: String
    public var sampleSource: String
    public var testCategory: String

    public init(
        contractId: String = "", commissionCode: String = "", commissionDate: String = "",
        categoryCode: String = "", receivedBy: String = "", sampleSource: String = "",
        testCategory: String = ""
    ) {
        self.contractId = contractId
        self.commissionCode = commissionCode
        self.commissionDate = commissionDate
        self.categoryCode = categoryCode
        self.receivedBy = receivedBy
        self.sampleSource = sampleSource
        self.testCategory = testCategory
    }

    /// 必填集字段名 → 值（validate 与 PATCH diff 共用一份遍历，防两处漂移）。
    var entries: [(String, String)] {
        [
            ("contractId", contractId), ("commissionCode", commissionCode),
            ("commissionDate", commissionDate), ("categoryCode", categoryCode),
            ("receivedBy", receivedBy), ("sampleSource", sampleSource),
            ("testCategory", testCategory),
        ]
    }
}

/// 表单错误：必填集不齐 fail-fast，不打端点（§1 禁兜底同源）。
public enum ReceiptFormError: Error, Equatable {
    case invalidFields
}

/// 接样单表单 VM：必填校验 + 请求构造（新建/PATCH 更新）+ 持久化路由。
public final class ReceiptFormViewModel {

    public var fields: ReceiptFormFields
    public private(set) var validationErrors: [String] = []

    /// 网络缝：id=nil → create；id≠nil → update。二选一非 nil，由 save 保证。
    private let persist: (
        _ id: String?, _ create: CreateSampleReceiptRequest?, _ update: UpdateSampleReceiptRequest?
    ) async throws -> SampleReceipt

    public init(
        fields: ReceiptFormFields = ReceiptFormFields(),
        persist: @escaping (
            _ id: String?, _ create: CreateSampleReceiptRequest?, _ update: UpdateSampleReceiptRequest?
        ) async throws -> SampleReceipt = ReceiptFormViewModel.notWired
    ) {
        self.fields = fields
        self.persist = persist
    }

    /// 缺省 persist：只做校验/请求构造的用法必须显式接线才能 save，
    /// 未接线就 save 是显式报错，不静默成功。（public：public init 的默认参数值
    /// 只能引用 public 成员。）
    public static func notWired(
        _ id: String?, _ create: CreateSampleReceiptRequest?, _ update: UpdateSampleReceiptRequest?
    ) async throws -> SampleReceipt {
        struct PersistNotWired: Error {}
        throw PersistNotWired()
    }

    /// 必填集校验：trim 后非空才算有值；缺项逐条进 validationErrors（UI 逐项标错）。
    @discardableResult
    public func validate() -> Bool {
        validationErrors = fields.entries
            .filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.0 }
        return validationErrors.isEmpty
    }

    /// AC-3：新建请求 = 必填集全量。
    public func makeCreateRequest() throws -> CreateSampleReceiptRequest {
        guard validate() else { throw ReceiptFormError.invalidFields }
        return CreateSampleReceiptRequest(
            contractId: fields.contractId,
            commissionCode: fields.commissionCode,
            commissionDate: fields.commissionDate,
            categoryCode: fields.categoryCode,
            receivedBy: fields.receivedBy,
            sampleSource: fields.sampleSource,
            testCategory: fields.testCategory
        )
    }

    /// AC-4 PATCH 语义：只携带与 original 不同的字段；清空（含空白归一后）也是变更。
    public func makeUpdateRequest(original: ReceiptFormFields) throws -> UpdateSampleReceiptRequest {
        guard validate() else { throw ReceiptFormError.invalidFields }
        func changed(_ now: String, _ before: String) -> String? {
            now == before ? nil : now
        }
        return UpdateSampleReceiptRequest(
            contractId: changed(fields.contractId, original.contractId),
            commissionCode: changed(fields.commissionCode, original.commissionCode),
            commissionDate: changed(fields.commissionDate, original.commissionDate),
            categoryCode: changed(fields.categoryCode, original.categoryCode),
            receivedBy: changed(fields.receivedBy, original.receivedBy),
            sampleSource: changed(fields.sampleSource, original.sampleSource),
            testCategory: changed(fields.testCategory, original.testCategory)
        )
    }

    /// 持久化路由：id 缺 → create；id 有 → update（PATCH，diff 基准 = original）。
    @discardableResult
    public func save(id: String?, original: ReceiptFormFields?) async throws -> SampleReceipt {
        if let id {
            let update = try makeUpdateRequest(original: original ?? ReceiptFormFields())
            return try await persist(id, nil, update)
        }
        let create = try makeCreateRequest()
        return try await persist(nil, create, nil)
    }
}

/// 接样单详情 VM（AC-6）：一次 load 同时取接样信息与流程历史。
public final class ReceiptDetailViewModel: ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()
    private func notify() { objectWillChange.send() }

    public private(set) var receipt: SampleReceipt?
    public private(set) var history: [FlowHistoryEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    /// 网络缝：返回 (接样单, 流程历史)；真实现由 UI 壳用 async let 并发取生成层两接口。
    private let fetch: (String) async throws -> (SampleReceipt, [FlowHistoryEntry])

    public init(
        fetch: @escaping (String) async throws -> (SampleReceipt, [FlowHistoryEntry])
    ) {
        self.fetch = fetch
    }

    public func load(id: String) async {
        notify()
        isLoading = true
        errorMessage = nil
        defer {
            notify()
            isLoading = false
        }
        do {
            let (fetchedReceipt, fetchedHistory) = try await fetch(id)
            notify()
            receipt = fetchedReceipt
            history = fetchedHistory
        } catch {
            notify()
            errorMessage = String(describing: error)
            receipt = nil
            history = []
        }
    }
}

/// 接样单删除 VM（AC-5）：确认后单条删除；失败以 errorMessage 呈现不崩。
public final class ReceiptDeleteViewModel {

    public private(set) var isDeleting = false
    public private(set) var errorMessage: String?

    private let delete: (String) async throws -> Void

    public init(delete: @escaping (String) async throws -> Void) {
        self.delete = delete
    }

    public func delete(id: String) async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await delete(id)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

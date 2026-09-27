import CoreKit
import LabSharedGenerated

// REQ-2026-002 T-3：App 层 API 胶水——生成层 completion 回调 → async 桥，
// 供给 CoreKit ViewModel 的网络缝。API 面只认生成物（硬规则 §4）。

enum APIGlue {

    /// RequestBuilder.execute completion → async/await（取 Response.body）。
    static func run<T>(_ build: () -> RequestBuilder<T>) async throws -> T {
        let builder = build()
        let response: Response<T> = try await withCheckedThrowingContinuation { continuation in
            _ = builder.execute { continuation.resume(with: $0) }
        }
        return response.body
    }

    /// 列表 provider（I01）：ReceiptListQuery → 生成层 listReceipts。
    static let list: (ReceiptListQuery) async throws -> [SampleReceipt] = { query in
        let page = try await run {
            ReceiptsAPI.receiptsListReceiptsWithRequestBuilder(
                page: query.page, pageSize: query.pageSize, keyword: query.keyword,
                contractId: nil, flowStatus: query.flowStatus, filter: query.filter.queryValue
            )
        }
        return page.items
    }

    /// 详情 fetch（I06）：async let 并发取接样信息与流程历史。
    static let detail: (String) async throws -> (SampleReceipt, [FlowHistoryEntry]) = { id in
        async let receipt = run { ReceiptsAPI.receiptsGetReceiptWithRequestBuilder(id: id) }
        async let history = run { ReceiptsAPI.receiptsGetReceiptHistoryWithRequestBuilder(id: id) }
        return try await (receipt, history)
    }

    /// act（I04/I08）：接样阶段流转统一端点。
    static func act(
        _ action: FlowAction, ids: [String], operator name: String, reason: String?
    ) async throws -> [FlowActionResult] {
        try await run {
            ReceiptsAPI.receiptsActFlowReceivingWithRequestBuilder(
                flowActionRequest: FlowActionRequest(
                    ids: ids, action: action, operator: name, reason: reason
                )
            )
        }
    }

    /// 表单 persist（I02）：id=nil → create；id+update → PUT（PATCH 语义）。
    static let persist: (
        _ id: String?, _ create: CreateSampleReceiptRequest?, _ update: UpdateSampleReceiptRequest?
    ) async throws -> SampleReceipt = { id, create, update in
        struct BadPersistRequest: Error {}
        if let id, let update {
            return try await run {
                ReceiptsAPI.receiptsUpdateReceiptWithRequestBuilder(
                    id: id, updateSampleReceiptRequest: update
                )
            }
        }
        guard let create else { throw BadPersistRequest() }
        return try await run {
            ReceiptsAPI.receiptsCreateReceiptWithRequestBuilder(createSampleReceiptRequest: create)
        }
    }

    /// 删除（I03）。
    static let deleteReceipt: (String) async throws -> Void = { id in
        _ = try await run { ReceiptsAPI.receiptsDeleteReceiptWithRequestBuilder(id: id) }
    }
}

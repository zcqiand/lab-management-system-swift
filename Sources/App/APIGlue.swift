import CoreKit
import LabSharedGenerated

// REQ-2026-002 T-3：App 层 API 胶水——生成层 completion 回调 → async 桥，
// 供给 CoreKit ViewModel 的网络缝。API 面只认生成物（硬规则 §4）。

enum APIGlue {

    /// 401 拦截缝（M01.F05.I02）：App 层注入（清会话回登录页）；
    /// 本层只识别 401，不感知 SwiftUI / SessionStore。
    static var onUnauthorized: (() -> Void)?

    /// RequestBuilder.execute completion → async/await（取 Response.body）。
    /// 401 统一在这层拦截：先触发回调再原样上抛，调用方照常收到失败。
    static func run<T>(_ build: () -> RequestBuilder<T>) async throws -> T {
        do {
            let builder = build()
            let response: Response<T> = try await withCheckedThrowingContinuation { continuation in
                _ = builder.execute { continuation.resume(with: $0) }
            }
            return response.body
        } catch let error as ErrorResponse {
            if case .error(401, _, _, _) = error {
                onUnauthorized?()
            }
            throw error
        }
    }

    // MARK: - 会话（REQ-2026-003 T-3）

    /// 原生登录（I06）：用户名+密码换 lab JWT。
    static let nativeLogin: (String, String) async throws -> LoginResponse = { username, password in
        try await run {
            AuthAPI.authNativeLoginWithRequestBuilder(
                loginRequest: LoginRequest(username: username, password: password)
            )
        }
    }

    /// 租户切换（M00.F02.I01）：后端换发新租户 token（LoginResponse 同形）。
    static let switchTenant: (String) async throws -> LoginResponse = { tenantId in
        try await run {
            AuthAPI.authSwitchTenantWithRequestBuilder(
                switchTenantRequest: SwitchTenantRequest(tenantId: tenantId)
            )
        }
    }

    /// 登出（I04）：服务端吊销当前 token。
    static let logout: (String) async throws -> Void = { token in
        _ = try await run {
            AuthAPI.authLogoutWithRequestBuilder(
                authLogoutRequest: AuthLogoutRequest(token: token)
            )
        }
    }

    // MARK: - SSO（M01.F05.I03，REQ-2026-010；RFC 6749 §4.1 两阶段）

    /// 阶段 2 authorize：后端校验 client_id/redirect_uri 白名单，拼 IdP 跳转
    /// URL 回 SsoRedirect（state 由客户端生成传入，后端原样带回）。
    static let ssoAuthorize: (
        OAuthResponseType, String, String, String
    ) async throws -> SsoRedirect = { responseType, clientId, redirectUri, state in
        try await run {
            AuthAPI.authSsoAuthorizeWithRequestBuilder(
                responseType: responseType, clientId: clientId,
                redirectUri: redirectUri, state: state
            )
        }
    }

    /// 阶段 1 callback：授权码换 lab 自家 JWT（client_secret 仅后端持有，
    /// saas token 不出 lab 后端）。
    static let ssoCallback: (SsoCallbackRequest) async throws -> LoginResponse = { request in
        try await run {
            AuthAPI.authSsoCallbackWithRequestBuilder(ssoCallbackRequest: request)
        }
    }

    // @impl M03.F01.I01 — 接样单列表（三态过滤/keyword/分页）
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

    // @impl M03.F01.I06 — 接样单流程历史（并发取详情+历史）
    /// 详情 fetch（I06）：async let 并发取接样信息与流程历史。
    static let detail: (String) async throws -> (SampleReceipt, [FlowHistoryEntry]) = { id in
        async let receipt = run { ReceiptsAPI.receiptsGetReceiptWithRequestBuilder(id: id) }
        async let history = run { ReceiptsAPI.receiptsGetReceiptHistoryWithRequestBuilder(id: id) }
        return try await (receipt, history)
    }

    // @impl M03.F01.I04 — 提交接样单（receiving → task_assignment）
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

    /// act（M03.F02.I05）：任务分配阶段流转统一端点（REQ-2026-004）。
    static func assigningAct(
        _ action: FlowAction, ids: [String], operator name: String, reason: String?
    ) async throws -> [FlowActionResult] {
        try await run {
            ReceiptsAPI.receiptsActFlowAssigningWithRequestBuilder(
                flowActionRequest: FlowActionRequest(
                    ids: ids, action: action, operator: name, reason: reason
                )
            )
        }
    }

    /// act（M03.F03.I12）：数据录入阶段流转统一端点（REQ-2026-005）。
    static func dataEntryAct(
        _ action: FlowAction, ids: [String], operator name: String, reason: String?
    ) async throws -> [FlowActionResult] {
        try await run {
            ReceiptsAPI.receiptsActFlowDataEntryWithRequestBuilder(
                flowActionRequest: FlowActionRequest(
                    ids: ids, action: action, operator: name, reason: reason
                )
            )
        }
    }

    /// act（M03.F05~F08.I0x）：报告四阶段流转统一端点（REQ-2026-006），
    /// 按阶段档位路由到 review/approve/issuance/archived。
    static func phaseAct(
        _ phase: ReportPhase, _ action: FlowAction, ids: [String], operator name: String,
        reason: String?
    ) async throws -> [FlowActionResult] {
        try await run {
            switch phase {
            case .review:
                ReceiptsAPI.receiptsActFlowReviewWithRequestBuilder(
                    flowActionRequest: FlowActionRequest(
                        ids: ids, action: action, operator: name, reason: reason
                    )
                )
            case .approval:
                ReceiptsAPI.receiptsActFlowApproveWithRequestBuilder(
                    flowActionRequest: FlowActionRequest(
                        ids: ids, action: action, operator: name, reason: reason
                    )
                )
            case .issuance:
                ReceiptsAPI.receiptsActFlowIssuanceWithRequestBuilder(
                    flowActionRequest: FlowActionRequest(
                        ids: ids, action: action, operator: name, reason: reason
                    )
                )
            case .archived:
                ReceiptsAPI.receiptsActFlowArchivedWithRequestBuilder(
                    flowActionRequest: FlowActionRequest(
                        ids: ids, action: action, operator: name, reason: reason
                    )
                )
            }
        }
    }

    // MARK: - 数据录入目录（M03.F03.I01，REQ-2026-005；页大小 200 镜像家族）

    /// 按单拉样品（录入 sheet 样品 Picker 数据源）。
    static let receiptSamples: (String) async throws -> [Sample] = { receiptId in
        let page = try await run {
            SamplesAPI.samplesListSamplesWithRequestBuilder(
                page: 1, pageSize: 200, receiptId: receiptId, keyword: nil
            )
        }
        return page.items
    }

    /// 参数字典（录入 sheet 参数 Picker 数据源）。
    static let parameters: () async throws -> [InspectionParameter] = {
        let page = try await run {
            InspectionDictionaryAPI.inspectionDictionaryListParametersWithRequestBuilder(
                page: 1, pageSize: 200, keyword: nil, sourceType: nil
            )
        }
        return page.items
    }

    /// 逐样品检测记录（录入 sheet 键控索引数据源）。
    static let testRecords: (String) async throws -> [TestRecord] = { sampleId in
        let page = try await run {
            TestRecordsAPI.testRecordsListTestRecordsWithRequestBuilder(
                page: 1, pageSize: 200, sampleId: sampleId, parameterCode: nil
            )
        }
        return page.items
    }

    /// 检测记录 persist（I02/I03）：id=nil → create；id+update → update。
    /// verdict 均随请求体（Q3 裁定，不走专用 setVerdict 端点）。
    static let persistTestRecord: (
        _ id: String?, _ create: CreateTestRecordRequest?, _ update: UpdateTestRecordRequest?
    ) async throws -> TestRecord = { id, create, update in
        struct BadPersistRequest: Error {}
        if let id, let update {
            return try await run {
                TestRecordsAPI.testRecordsUpdateTestRecordWithRequestBuilder(
                    id: id, updateTestRecordRequest: update
                )
            }
        }
        guard let create else { throw BadPersistRequest() }
        return try await run {
            TestRecordsAPI.testRecordsCreateTestRecordWithRequestBuilder(
                createTestRecordRequest: create
            )
        }
    }

    /// 安排/取消（M03.F02.I02）：手填姓名+日期（REQ-2026-004 Q2，assigneeId 不传）。
    static let assignTask: (String, AssignTaskRequest) async throws -> SampleReceipt = { id, request in
        try await run {
            ReceiptsAPI.receiptsAssignTaskWithRequestBuilder(id: id, assignTaskRequest: request)
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

    // @impl M03.F01.I03 — 删除接样单（confirmed id 直传端点）
    /// 删除（I03）。
    static let deleteReceipt: (String) async throws -> Void = { id in
        _ = try await run { ReceiptsAPI.receiptsDeleteReceiptWithRequestBuilder(id: id) }
    }

    // MARK: - ext 补录（M03.F01.I07，REQ-2026-008；页大小 200 镜像家族）

    /// 类别报告名目录（extFields 定义数据源，Q1 裁定走 live 契约端点）。
    static let reportNames: (Int) async throws -> [InspectionReportName] = { pageSize in
        let page = try await run {
            ReportNamesAPI.reportNamesListReportNamesWithRequestBuilder(
                page: 1, pageSize: pageSize, keyword: nil
            )
        }
        return page.items
    }

    /// 样品 ext 落库（合并语义在 CoreKit，端点收合并后全量 ext）。
    static let updateSampleExt: (String, [String: String]) async throws -> Void = { id, ext in
        _ = try await run {
            SamplesAPI.samplesUpdateSampleExtWithRequestBuilder(
                id: id, updateSampleExtRequest: UpdateSampleExtRequest(ext: ext)
            )
        }
    }
}

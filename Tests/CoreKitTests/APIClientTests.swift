import XCTest
@testable import CoreKit
import LabSharedGenerated

/// REQ-2026-001 AC-1..AC-8 的请求构造与响应解析测试（red-first）。
/// 全部走生成 client 的 RequestBuilder（URLString/parameters 公开属性），
/// 不发真网络；fail-fast 语义锁 APIClient.bootstrap。
final class APIClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        OpenAPIClientAPI.basePath = "https://api.example.invalid"
        OpenAPIClientAPI.customHeaders = [:]
    }

    // MARK: AC-1/AC-2 列表与三态过滤

    func testListRequestCarriesPaginationAndThreeStateFilter() throws {
        // fn: M03.F01.I01
        let builder = ReceiptsAPI.receiptsListReceiptsWithRequestBuilder(
            page: 1, pageSize: 20, keyword: "CMA", contractId: nil,
            flowStatus: nil, filter: "not_yet"
        )
        XCTAssertTrue(builder.URLString.contains("/api/receipts"))
        XCTAssertTrue(builder.URLString.contains("page=1"))
        XCTAssertTrue(builder.URLString.contains("pageSize=20"))
        XCTAssertTrue(builder.URLString.contains("filter=not_yet"))
    }

    func testListRequestWithoutFilterOmitsFilterParam() throws {
        // fn: M03.F01.I01
        let builder = ReceiptsAPI.receiptsListReceiptsWithRequestBuilder(
            page: nil, pageSize: nil, keyword: nil, contractId: nil,
            flowStatus: nil, filter: nil
        )
        XCTAssertFalse(builder.URLString.contains("filter="))
    }

    // MARK: AC-3/AC-4 创建/更新与 AC-7 act 请求体

    func testCreateReceiptBodyEncodesRequiredSet() throws {
        // fn: M03.F01.I02
        let body = CreateSampleReceiptRequest(
            contractId: "c-1", commissionCode: "WT-2026-001",
            commissionDate: "2026-09-27", commissionRegisterCode: nil,
            commissionRegisterDate: nil, categoryCode: "CAT01",
            projectName: nil, clientUnit: nil, buildingUnit: nil,
            supervisorUnit: nil, constructionUnit: nil, witnessUnit: nil,
            samplingLocation: nil, witness: nil, witnessPhone: nil,
            inspector: nil, inspectorPhone: nil, receivedBy: "alice",
            sampleSource: "witness", testCategory: "detected",
            testEnvironment: nil, mainEquipment: nil, testOperator: nil,
            testStartDate: nil, testEndDate: nil, originalRecordNo: nil,
            remark: nil, judgmentBasis: nil, testingBasis: nil,
            testParameters: nil
        )
        let builder = ReceiptsAPI.receiptsCreateReceiptWithRequestBuilder(createSampleReceiptRequest: body)
        // 生成层把 body 预编码成 parameters["jsonData"] = Data（JSONDataEncoding.jsonDataKey），取 Data 反解为字典断言。
        let bodyData = try XCTUnwrap(builder.parameters?["jsonData"] as? Data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(json["contractId"] as? String, "c-1")
        XCTAssertEqual(json["commissionCode"] as? String, "WT-2026-001")
        XCTAssertEqual(json["receivedBy"] as? String, "alice")
        XCTAssertEqual(builder.URLString.contains("/api/receipts"), true)
    }

    func testActRequestEncodesThreeActions() throws {
        // fn: M03.F01.I08
        for (action, expectedRaw) in [
            (FlowAction.submit, "submit"),
            (FlowAction.`return`, "return"),
            (FlowAction.withdraw, "withdraw"),
        ] {
            let body = FlowActionRequest(
                ids: ["r-1", "r-2"], action: action, operator: "alice", reason: nil
            )
            let builder = ReceiptsAPI.receiptsActFlowReceivingWithRequestBuilder(flowActionRequest: body)
            // 同上：body 是 parameters["jsonData"] 里的预编码 Data。
            let bodyData = try XCTUnwrap(builder.parameters?["jsonData"] as? Data)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(json["action"] as? String, expectedRaw)
            XCTAssertEqual(json["operator"] as? String, "alice")
            XCTAssertEqual((json["ids"] as? [String])?.count, 2)
            XCTAssertTrue(builder.URLString.contains("/api/receipts/receiving/act"))
        }
    }

    // MARK: AC-6 响应解析

    func testSampleReceiptFixtureDecodes() throws {
        // fn: M03.F01.I01
        let json = """
        {
          "id": "r-1", "tenantId": "t-1", "contractId": "c-1",
          "commissionCode": "WT-2026-001", "commissionDate": "2026-09-27",
          "categoryCode": "CAT01", "receivedBy": "alice",
          "sampleSource": "witness", "testCategory": "detected",
          "flowStatus": "receiving", "flowHistory": [],
          "createdAt": "2026-09-27T08:00:00Z", "updatedAt": "2026-09-27T08:00:00Z"
        }
        """.data(using: .utf8)!
        let receipt = try JSONDecoder().decode(SampleReceipt.self, from: json)
        XCTAssertEqual(receipt.id, "r-1")
        XCTAssertEqual(receipt.flowStatus, .receiving)
        XCTAssertEqual(receipt.commissionCode, "WT-2026-001")
    }

    func testHistoryFixtureDecodes() throws {
        // fn: M03.F01.I06
        let json = """
        [{
          "action": "submit", "from": "receiving", "to": "task_assignment",
          "operator": "alice", "at": "2026-09-27T09:00:00Z"
        }]
        """.data(using: .utf8)!
        let history = try JSONDecoder().decode([FlowHistoryEntry].self, from: json)
        XCTAssertEqual(history.first?.action, .submit)
        XCTAssertEqual(history.first?.to, .taskAssignment)
        XCTAssertEqual(history.first?.operator, "alice")
    }

    // MARK: AC-8 fail-fast 会话注入（Q1 结论）

    func testBootstrapFailsFastOnEmptyBaseURL() {
        XCTAssertThrowsError(
            try APIClient.bootstrap(baseURL: "  ", token: "tk-1")
        ) { error in
            guard case APIConfigError.missingBaseURL = error else {
                return XCTFail("期望 missingBaseURL，实际 \(error)")
            }
        }
    }

    func testBootstrapFailsFastOnEmptyToken() {
        XCTAssertThrowsError(
            try APIClient.bootstrap(baseURL: "https://api.example.invalid", token: "")
        ) { error in
            guard case APIConfigError.missingToken = error else {
                return XCTFail("期望 missingToken，实际 \(error)")
            }
        }
    }

    func testBootstrapFailsFastOnInvalidBaseURL() {
        XCTAssertThrowsError(
            try APIClient.bootstrap(baseURL: "not a url", token: "tk-1")
        ) { error in
            guard case APIConfigError.invalidBaseURL = error else {
                return XCTFail("期望 invalidBaseURL，实际 \(error)")
            }
        }
    }

    func testBootstrapInjectsBearerHeaderAndBasePath() throws {
        try APIClient.bootstrap(baseURL: "https://api.example.invalid/", token: "tk-1")
        XCTAssertEqual(OpenAPIClientAPI.basePath, "https://api.example.invalid")
        XCTAssertEqual(OpenAPIClientAPI.customHeaders["Authorization"], "Bearer tk-1")
        let builder = ReceiptsAPI.receiptsGetReceiptWithRequestBuilder(id: "r-1")
        XCTAssertTrue(builder.URLString.hasPrefix("https://api.example.invalid/api/receipts/r-1"))
    }
}

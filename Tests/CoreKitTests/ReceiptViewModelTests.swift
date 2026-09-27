import XCTest
@testable import CoreKit
import LabSharedGenerated

/// REQ-2026-001 T-4：CoreKit 纯 Swift ViewModel（列表查询 / act 流转）。
/// 网络缝 = 注入 async 闭包，单测不发真网络；filter 三态语义 SSOT =
/// shared tsp routes/sample-receipts.tsp listReceipts 注释（不传/not_yet/submitted）。
final class ReceiptViewModelTests: XCTestCase {

    // MARK: 脚手架

    private func makeReceipt(id: String, flowStatus: FlowStatus) throws -> SampleReceipt {
        let json = """
        {
          "id": "\(id)", "tenantId": "t-1", "contractId": "c-1",
          "commissionCode": "WT-2026-\(id)", "commissionDate": "2026-09-27",
          "categoryCode": "CAT01", "receivedBy": "alice",
          "sampleSource": "witness", "testCategory": "detected",
          "flowStatus": "\(flowStatus.rawValue)", "flowHistory": [],
          "createdAt": "2026-09-27T08:00:00Z", "updatedAt": "2026-09-27T08:00:00Z"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(SampleReceipt.self, from: json)
    }

    private func makeList(_ specs: [(String, FlowStatus)]) throws -> [SampleReceipt] {
        try specs.map { try makeReceipt(id: $0.0, flowStatus: $0.1) }
    }

    // MARK: filter 三态 → 查询值

    func testFilterThreeStatesMapToQueryValues() {
        XCTAssertEqual(ReceiptFilter.all.queryValue, nil)
        XCTAssertEqual(ReceiptFilter.notYet.queryValue, "not_yet")
        XCTAssertEqual(ReceiptFilter.submitted.queryValue, "submitted")
    }

    // MARK: 列表加载

    func testLoadResetsToPage1AndReplacesItems() async throws {
        var seen: [ReceiptListQuery] = []
        let vm = ReceiptListViewModel(provider: { query in
            seen.append(query)
            return try self.makeList([("r-1", .receiving)])
        })
        vm.query.page = 3
        vm.query.filter = .notYet
        await vm.load()
        XCTAssertEqual(seen.last?.page, 1, "load 必须回到第 1 页")
        XCTAssertEqual(seen.last?.filter, .notYet)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.id, "r-1")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func testLoadNextPageAppendsAndStopsAtShortPage() async throws {
        let page1 = try makeList((1...20).map { ("r-\($0)", .receiving) })
        let page2 = try makeList([("r-21", .receiving)])
        let pages = [page1, page2]
        var call = 0
        let vm = ReceiptListViewModel(provider: { _ in
            defer { call += 1 }
            return pages[min(call, pages.count - 1)]
        })
        await vm.load()
        XCTAssertTrue(vm.hasMore, "整页 20 条 = 可能还有下一页")
        await vm.loadNextPage()
        XCTAssertEqual(vm.items.count, 21, "第 2 页 1 条不足整页 → 追加后停")
        XCTAssertFalse(vm.hasMore)
    }

    func testLoadErrorSurfacesMessageAndResetsLoading() async throws {
        struct Boom: Error {}
        let failing = ReceiptListViewModel(provider: { _ in throw Boom() })
        await failing.load()
        XCTAssertNotNil(failing.errorMessage)
        XCTAssertTrue(failing.items.isEmpty)
        XCTAssertFalse(failing.isLoading)
    }

    // MARK: act 流转（emptySelection fail-fast + 结果回填）

    func testActWithEmptySelectionFailsFastWithoutCallingEndpoint() async throws {
        struct NoCall: Error {}
        var called = false
        let vm = ReceivingFlowViewModel(operatorName: "alice") { _, _, _ in
            called = true
            return []
        }
        do {
            _ = try await vm.perform(.submit, ids: [], reason: nil)
            XCTFail("空选择必须 throw")
        } catch let error as FlowActionError {
            XCTAssertEqual(error, .emptySelection)
        }
        XCTAssertFalse(called, "空选择不许打到端点")
    }

    func testActSendsOperatorAndAppliesResultStatus() async throws {
        var captured: (action: FlowAction, ids: [String], reason: String?)?
        let vm = ReceivingFlowViewModel(operatorName: "alice") { action, ids, reason in
            captured = (action, ids, reason)
            return [FlowActionResult(id: "r-1", ok: true, flowStatus: .taskAssignment)]
        }
        let results = try await vm.perform(.submit, ids: ["r-1"], reason: "补录完成")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(captured?.action, .submit)
        XCTAssertEqual(captured?.ids, ["r-1"])
        XCTAssertEqual(captured?.reason, "补录完成")

        // 结果回填列表：r-1 → task_assignment
        let list = ReceiptListViewModel(provider: { _ in
            try self.makeList([("r-1", .receiving), ("r-2", .receiving)])
        })
        await list.load()
        list.apply(results)
        XCTAssertEqual(list.items.first { $0.id == "r-1" }?.flowStatus, .taskAssignment)
        XCTAssertEqual(list.items.first { $0.id == "r-2" }?.flowStatus, .receiving, "未涉及单不许被动")
    }

    func testActFailureResultCarriesMessageNotThrow() async throws {
        let vm = ReceivingFlowViewModel(operatorName: "alice") { _, _, _ in
            [FlowActionResult(id: "r-9", ok: false, message: "状态不允许提交")]
        }
        let results = try await vm.perform(.submit, ids: ["r-9"], reason: nil)
        XCTAssertEqual(results.first?.ok, false)
        XCTAssertEqual(results.first?.message, "状态不允许提交")
    }
}

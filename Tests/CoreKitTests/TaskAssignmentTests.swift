import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-004 T-1：任务分配 CoreKit 状态机（红先行）。
// 队列（I01）复用 ReceiptListViewModel——query.flowStatus 预设钉死分配环节；
// 安排/取消（I02）= AssignTaskViewModel：手填姓名+日期（Q2 裁定，assigneeId
// 不传），两字段全空 = 取消安排（全 nil 清空请求）；act（I05）复用
// ReceivingFlowViewModel，operator = 真会话身份（Q3 裁定），缺席 fail-fast。
final class TaskAssignmentTests: XCTestCase {

    private func makeReceipt(
        id: String = "r-1",
        flowStatus: FlowStatus = .taskAssignment,
        assigneeName: String? = nil,
        plannedTestDate: String? = nil
    ) -> SampleReceipt {
        SampleReceipt(
            id: id, tenantId: "t-1", contractId: "c-1",
            commissionCode: "WT-2026-001", commissionDate: "2026-09-28",
            categoryCode: "cat-1", receivedBy: "李接样", sampleSource: "现场",
            testCategory: "环氧树脂", flowStatus: flowStatus, flowHistory: [],
            assigneeName: assigneeName, plannedTestDate: plannedTestDate,
            createdAt: "2026-09-28T09:00:00Z", updatedAt: "2026-09-28T09:00:00Z"
        )
    }

    // MARK: I01 分配队列

    func testQueueQueryPinsTaskAssignmentStage() async throws {
    // fn: M03.F02.I01
        // 队列 = ReceiptListViewModel 复用：provider 收到的查询必须钉死
        // flowStatus=task_assignment，keyword 透传，分页 1 起。
        var seen: ReceiptListQuery?
        let vm = ReceiptListViewModel(provider: { query in
            seen = query
            return []
        })
        vm.query.flowStatus = .taskAssignment
        vm.query.pageSize = 50
        vm.query.keyword = "WT-2026"
        await vm.load()
        XCTAssertEqual(seen?.flowStatus, .taskAssignment, "队列查询必须钉在分配环节")
        XCTAssertEqual(seen?.keyword, "WT-2026")
        XCTAssertEqual(seen?.page, 1)
    }

    // MARK: I02 安排/取消

    func testAssignRequestTrimsAndRequiresBothFields() throws {
    // fn: M03.F02.I02
        // 安排语义：姓名+日期都必填（trim 后），assigneeId 恒不传（Q2 手填裁定）。
        let vm = AssignTaskViewModel { _, _ in
            XCTFail("makeRequest 阶段不该触发持久化")
            struct Never: Error {}
            throw Never()
        }
        vm.assigneeName = "  王检测 "
        vm.plannedTestDate = " 2026-10-01 "
        let request = try vm.makeRequest()
        XCTAssertNil(request.assigneeId, "手填形态不传 assigneeId")
        XCTAssertEqual(request.assigneeName, "王检测")
        XCTAssertEqual(request.plannedTestDate, "2026-10-01")

        vm.assigneeName = "   "
        XCTAssertThrowsError(try vm.makeRequest(), "缺姓名必须 fail-fast 不打端点")
    }

    func testCancelAssignRequestClearsAllFields() throws {
    // fn: M03.F02.I02
        // 取消安排语义：两字段全空 = 全 nil 清空请求（家族「取消」同款）。
        let vm = AssignTaskViewModel { _, _ in
            struct Never: Error {}
            throw Never()
        }
        let request = try vm.makeRequest()
        XCTAssertNil(request.assigneeId)
        XCTAssertNil(request.assigneeName)
        XCTAssertNil(request.plannedTestDate)
    }

    func testAssignSaveReturnsAdoptedReceipt() async throws {
    // fn: M03.F02.I02
        let updated = makeReceipt(id: "r-1", assigneeName: "王检测", plannedTestDate: "2026-10-01")
        let vm = AssignTaskViewModel { [updated] id, request in
            XCTAssertEqual(id, "r-1")
            XCTAssertEqual(request.assigneeName, "王检测")
            return updated
        }
        vm.assigneeName = "王检测"
        vm.plannedTestDate = "2026-10-01"
        let saved = await vm.save(id: "r-1")
        XCTAssertEqual(saved?.id, "r-1")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSaving, "save 返回后忙态必须落回")
    }

    func testAssignSaveFailureReportsAndKeepsFields() async {
        let vm = AssignTaskViewModel { _, _ in throw SeamedFailure() }
        vm.assigneeName = "王检测"
        vm.plannedTestDate = "2026-10-01"
        let saved = await vm.save(id: "r-1")
        XCTAssertNil(saved)
        XCTAssertNotNil(vm.errorMessage, "失败必须呈错不打断")
        XCTAssertEqual(vm.assigneeName, "王检测", "失败不许清用户输入")
    }

    // MARK: I05 act 三动作（operator=真会话身份）

    func testActEmbedsSessionOperatorAndPerforms() async throws {
    // fn: M03.F02.I05
        // operator = 会话用户名（Q3 裁定）：组装进请求体，act 缝收到动作与选区。
        var seenAction: FlowAction?
        var seenIds: [String]?
        let flow = ReceivingFlowViewModel(operatorName: "alice") { action, ids, _ in
            seenAction = action
            seenIds = ids
            return []
        }
        let results = try await flow.perform(.submit, ids: ["r-1", "r-2"])
        XCTAssertEqual(results.count, 0)
        XCTAssertEqual(seenAction, .submit)
        XCTAssertEqual(seenIds, ["r-1", "r-2"])
        let request = try flow.makeRequest(.submit, ids: ["r-1"])
        XCTAssertEqual(request.operator, "alice", "请求体 operator 必须是会话身份")
    }

    func testActRejectsMissingOperator() async {
    // fn: M03.F02.I05
        // 身份缺席 fail-fast 不打端点（ADR-0019：禁业务身份兜底）。
        var seamCalled = false
        let flow = ReceivingFlowViewModel(operatorName: "   ") { _, _, _ in
            seamCalled = true
            return []
        }
        do {
            _ = try await flow.perform(.submit, ids: ["r-1"])
            XCTFail("缺席 operator 必须 throw")
        } catch {
            XCTAssertFalse(seamCalled, "fail-fast 不许触达网络缝")
        }
    }
}

private struct SeamedFailure: Error {}

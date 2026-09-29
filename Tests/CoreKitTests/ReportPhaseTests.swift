import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-006 T-1：报告四阶段 CoreKit 契约（红先行）。
// 四阶段与接样→分配→录入（各自已有 act 三动作：M03.F01.I08 / F02.I05 /
// F03.I12）是同一流程线：本件只有一件新事 = ReportPhase 阶段描述（阶段→
// flowStatus / submitLabel / 页标题），队列与 act 全复用既有缝
// （ReceiptListViewModel + ReceivingFlowViewModel，operator=会话身份）。
// 发放报告编号后端 act 语义内含生成，UI 只显示 reportCode（家族实证）。
final class ReportPhaseTests: XCTestCase {

    private func makeReceipt(id: String = "r-1", flowStatus: FlowStatus) -> SampleReceipt {
        SampleReceipt(
            id: id, tenantId: "t-1", contractId: "c-1",
            commissionCode: "WT-2026-001", commissionDate: "2026-09-28",
            categoryCode: "cat-1", receivedBy: "李接样", sampleSource: "现场",
            testCategory: "环氧树脂", flowStatus: flowStatus, flowHistory: [],
            createdAt: "2026-09-28T09:00:00Z", updatedAt: "2026-09-28T09:00:00Z"
        )
    }

    private func loadQueue(_ phase: ReportPhase) async -> (seen: ReceiptListQuery?, count: Int) {
        var seen: ReceiptListQuery?
        let vm = ReceiptListViewModel(provider: { query in
            seen = query
            return [self.makeReceipt(flowStatus: phase.flowStatus)]
        })
        vm.query.flowStatus = phase.flowStatus
        vm.query.pageSize = 50
        vm.query.keyword = "WT-2026"
        await vm.load()
        return (seen, vm.items.count)
    }

    // MARK: F05 审核

    func testReviewQueuePinsReviewStage() async {
    // fn: M03.F05.I01
        let (seen, count) = await loadQueue(.review)
        XCTAssertEqual(seen?.flowStatus, .review, "审核队列查询必须钉在 review 环节")
        XCTAssertEqual(seen?.keyword, "WT-2026")
        XCTAssertEqual(seen?.page, 1)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(ReportPhase.review.submitLabel, "审核通过")
    }

    func testReviewActEmbedsSessionOperator() throws {
    // fn: M03.F05.I07
    // fn: M03.F05.I02
        // 审核通过/驳回按钮与 act 行同一条提交路：operator=会话身份进请求体。
        let flow = ReceivingFlowViewModel(operatorName: "alice") { _, _, _ in [] }
        let request = try flow.makeRequest(.submit, ids: ["r-1"])
        XCTAssertEqual(request.operator, "alice")
        XCTAssertEqual(request.ids, ["r-1"])
        let returnRequest = try flow.makeRequest(.return, ids: ["r-1"])
        XCTAssertEqual(returnRequest.action, .return, "驳回 = return 批次回退一阶")
    }

    // MARK: F06 批准

    func testApprovalQueuePinsApprovalStage() async {
    // fn: M03.F06.I01
        let (seen, count) = await loadQueue(.approval)
        XCTAssertEqual(seen?.flowStatus, .approval, "批准队列查询必须钉在 approval 环节")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(ReportPhase.approval.submitLabel, "批准")
    }

    func testApprovalActEmbedsSessionOperator() throws {
    // fn: M03.F06.I05
    // fn: M03.F06.I02
        let flow = ReceivingFlowViewModel(operatorName: "alice") { _, _, _ in [] }
        let request = try flow.makeRequest(.submit, ids: ["r-1"])
        XCTAssertEqual(request.operator, "alice")
        let returnRequest = try flow.makeRequest(.return, ids: ["r-1"])
        XCTAssertEqual(returnRequest.action, .return, "驳回 = return 批次回退一阶")
    }

    // MARK: F07 发放（报告编号后端生成，UI 只显示）

    func testIssuanceQueuePinsIssuanceStage() async {
    // fn: M03.F07.I01
        let (seen, count) = await loadQueue(.issuance)
        XCTAssertEqual(seen?.flowStatus, .issuance, "发放队列查询必须钉在 issuance 环节")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(ReportPhase.issuance.submitLabel, "发放")
    }

    func testIssuanceActEmbedsSessionOperator() throws {
    // fn: M03.F07.I05
    // fn: M03.F07.I02
        // 发放按钮 = 本阶段 act submit；报告编号由后端 act 语义生成，
        // 客户端不组编号请求（家族实证）——锁「operator 进请求体」即可。
        let flow = ReceivingFlowViewModel(operatorName: "bob") { _, _, _ in [] }
        let request = try flow.makeRequest(.submit, ids: ["r-1"])
        XCTAssertEqual(request.operator, "bob")
    }

    // MARK: F08 归档

    func testArchivedQueuePinsArchivedStage() async {
    // fn: M03.F08.I01
        let (seen, count) = await loadQueue(.archived)
        XCTAssertEqual(seen?.flowStatus, .archived, "归档队列查询必须钉在 archived 环节")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(ReportPhase.archived.submitLabel, "归档完成")
    }

    func testArchivedActEmbedsSessionOperator() throws {
    // fn: M03.F08.I05
    // fn: M03.F08.I02
        let flow = ReceivingFlowViewModel(operatorName: "bob") { _, _, _ in [] }
        let request = try flow.makeRequest(.submit, ids: ["r-1"])
        XCTAssertEqual(request.operator, "bob")
    }

    // MARK: 四阶段一巡（全量覆盖：4 阶段 × flowStatus 映射无串档）

    func testAllFourPhasesMapToDistinctFlowStatuses() {
    // fn: M03.F05.I01
    // fn: M03.F06.I01
    // fn: M03.F07.I01
    // fn: M03.F08.I01
        let statuses = ReportPhase.allCases.map(\.flowStatus)
        XCTAssertEqual(Set(statuses).count, 4, "四阶段必须各钉一态，不许串档")
        XCTAssertEqual(statuses, [.review, .approval, .issuance, .archived])
    }
}

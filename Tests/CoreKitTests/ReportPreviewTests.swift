import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-007 T-1：接样单详情/预览 CoreKit 契约（红先行）。
// I02 = 时间线 at 倒序（旧树不排序 → 真红）；I03 = ReportPreviewViewModel
// 按样品归集记录（新符号 → 真红）；I01 = SampleReceipt 全字段直取（App 呈现面）。

final class ReportPreviewTests: XCTestCase {

    private func makeReceipt() -> SampleReceipt {
        SampleReceipt(
            id: "r-9", tenantId: "t-1", contractId: "c-1",
            commissionCode: "WT-2026-009", commissionDate: "2026-09-29",
            categoryCode: "BG", projectName: "滨江大道改造", clientUnit: "城建集团",
            buildingUnit: "城建一公司", supervisorUnit: "监理A",
            constructionUnit: "施工B", witnessUnit: "见证C",
            samplingLocation: "3号桥台", witness: "王见证",
            inspector: "赵送检", receivedBy: "李接样",
            sampleSource: "现场", testCategory: "环氧树脂",
            flowStatus: .issuance, flowHistory: [],
            assigneeName: "钱检测", plannedTestDate: "2026-10-08",
            reportCode: "BG-2026-001", reportDate: "2026-09-29",
            result: .pass,
            createdAt: "2026-09-29T09:00:00Z", updatedAt: "2026-09-29T09:00:00Z"
        )
    }

    private func makeRecord(
        sampleId: String, code: String, verdict: String?
    ) -> TestRecord {
        TestRecord(
            id: "\(sampleId)#\(code)", tenantId: "t-1", sampleId: sampleId,
            parameterCode: code, requirement: ">=42.5", result: "48.2",
            verdict: verdict,
            createdAt: "2026-09-29T09:00:00Z", updatedAt: "2026-09-29T09:00:00Z"
        )
    }

    // MARK: I01 详情全字段

    func testDetailReceiptCarriesFullFieldSet() {
    // fn: M03.F09.I01
        let receipt = makeReceipt()
        XCTAssertEqual(receipt.commissionCode, "WT-2026-009")
        XCTAssertEqual(receipt.projectName, "滨江大道改造")
        XCTAssertEqual(receipt.clientUnit, "城建集团")
        XCTAssertEqual(receipt.witnessUnit, "见证C")
        XCTAssertEqual(receipt.samplingLocation, "3号桥台")
        XCTAssertEqual(receipt.assigneeName, "钱检测")
        XCTAssertEqual(receipt.reportCode, "BG-2026-001")
        XCTAssertEqual(receipt.reportDate, "2026-09-29")
        XCTAssertEqual(receipt.result, .pass)
    }

    // MARK: I02 时间线 at 倒序

    func testDetailHistorySortedByAtDescending() async {
    // fn: M03.F09.I02
        let entry = { (at: String) -> FlowHistoryEntry in
            FlowHistoryEntry(
                action: .submit, from: .receiving, to: .taskAssignment,
                operator: "alice", at: at
            )
        }
        let vm = ReceiptDetailViewModel { _ in
            (self.makeReceipt(), [entry("2026-09-28T09:00:00Z"), entry("2026-09-29T10:00:00Z")])
        }
        await vm.load(id: "r-9")
        XCTAssertEqual(vm.history.map(\.at), [
            "2026-09-29T10:00:00Z", "2026-09-28T09:00:00Z",
        ], "时间线必须按 at 倒序（家族 ReceiptDetail 同款）")
        XCTAssertEqual(vm.receipt?.reportCode, "BG-2026-001")
    }

    // MARK: I03 预览归集

    func testPreviewLoadGroupsRecordsBySample() async {
    // fn: M03.F09.I03
        let samples = [
            Sample(id: "s-1", tenantId: "t-1", receiptId: "r-9", sampleCode: "YP-1",
                   ext: [:], createdAt: "2026-09-29T09:00:00Z", updatedAt: "2026-09-29T09:00:00Z"),
            Sample(id: "s-2", tenantId: "t-1", receiptId: "r-9", sampleCode: "YP-2",
                   ext: [:], createdAt: "2026-09-29T09:00:00Z", updatedAt: "2026-09-29T09:00:00Z"),
        ]
        var queried: [String] = []
        let vm = ReportPreviewViewModel(
            samplesLoad: { receiptId in
                XCTAssertEqual(receiptId, "r-9")
                return samples
            },
            recordsLoad: { sampleId in
                queried.append(sampleId)
                return sampleId == "s-1"
                    ? [self.makeRecord(sampleId: "s-1", code: "P1", verdict: "合格"),
                       self.makeRecord(sampleId: "s-1", code: "P2", verdict: nil)]
                    : [self.makeRecord(sampleId: "s-2", code: "P1", verdict: "不合格")]
            }
        )
        await vm.load(receiptId: "r-9")
        XCTAssertEqual(vm.samples.count, 2)
        XCTAssertEqual(vm.recordsBySample["s-1"]?.count, 2)
        XCTAssertEqual(vm.recordsBySample["s-2"]?.count, 1)
        XCTAssertEqual(vm.recordsBySample["s-1"]?.first?.parameterCode, "P1")
        XCTAssertEqual(queried, ["s-1", "s-2"], "契约 list 无 receiptId 参数，逐样品取（家族同款）")
        XCTAssertNil(vm.errorMessage)
    }

    func testPreviewEmptySamplesYieldsEmptyPreview() async {
    // fn: M03.F09.I03
        let vm = ReportPreviewViewModel(
            samplesLoad: { _ in [] },
            recordsLoad: { _ in [] }
        )
        await vm.load(receiptId: "r-9")
        XCTAssertTrue(vm.samples.isEmpty)
        XCTAssertTrue(vm.recordsBySample.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testPreviewLoadFailureSurfacesMessageAndClearsState() async {
    // fn: M03.F09.I03
        struct Boom: Error {}
        let vm = ReportPreviewViewModel(
            samplesLoad: { _ in throw Boom() },
            recordsLoad: { _ in [] }
        )
        await vm.load(receiptId: "r-9")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.samples.isEmpty)
        XCTAssertTrue(vm.recordsBySample.isEmpty)
    }
}

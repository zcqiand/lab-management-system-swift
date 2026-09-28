import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-005 T-1：数据录入 CoreKit 状态机（红先行）。
// 队列（I01）复用 ReceiptListViewModel——query.flowStatus 预设钉死 data_entry；
// 录入（I01/I02/I03）= DataEntryViewModel：样品/参数目录装载 + 按
// sampleId#parameterCode 键控 create-vs-update（Q2 裁定），verdict 随请求体
// （Q3 裁定，不走专用 setVerdict）；act（I12）复用 ReceivingFlowViewModel，
// operator = 真会话身份（REQ-2026-004 已建立）。
final class DataEntryTests: XCTestCase {

    private func makeReceipt(id: String = "r-1") -> SampleReceipt {
        SampleReceipt(
            id: id, tenantId: "t-1", contractId: "c-1",
            commissionCode: "WT-2026-001", commissionDate: "2026-09-28",
            categoryCode: "cat-1", receivedBy: "李接样", sampleSource: "现场",
            testCategory: "环氧树脂", flowStatus: .dataEntry, flowHistory: [],
            createdAt: "2026-09-28T09:00:00Z", updatedAt: "2026-09-28T09:00:00Z"
        )
    }

    private func makeSample(id: String = "s-1", code: String = "YP-001") -> Sample {
        Sample(
            id: id, tenantId: "t-1", receiptId: "r-1", sampleCode: code,
            ext: [:], createdAt: "2026-09-28T09:00:00Z", updatedAt: "2026-09-28T09:00:00Z"
        )
    }

    private func makeParameter(code: String = "P-CE", name: String = "抗压强度") -> InspectionParameter {
        InspectionParameter(
            code: code, name: name, rawName: name, canonicalName: name,
            aliases: [], sourceType: .official, sortOrder: 0,
            createdAt: "2026-09-28T09:00:00Z", updatedAt: "2026-09-28T09:00:00Z"
        )
    }

    private func makeRecord(
        id: String = "tr-1", sampleId: String = "s-1",
        parameterCode: String = "P-CE", result: String = "45.2",
        verdict: String? = "合格"
    ) -> TestRecord {
        TestRecord(
            id: id, tenantId: "t-1", sampleId: sampleId, parameterCode: parameterCode,
            requirement: "≥42.5", result: result, verdict: verdict,
            createdAt: "2026-09-28T09:00:00Z", updatedAt: "2026-09-28T09:00:00Z"
        )
    }

    /// 目录/记录给空、persist 未接线的 VM（表单校验类测试用）。
    private static func emptyVM() -> DataEntryViewModel {
        DataEntryViewModel(
            catalogLoad: { _ in ([], []) },
            recordsLoad: { _ in [] },
            persist: { _, _, _ in
                struct Never: Error {}
                throw Never()
            }
        )
    }

    // MARK: I01 数据录入队列 + 目录装载

    func testQueueQueryPinsDataEntryStage() async throws {
    // fn: M03.F03.I01
        // 队列 = ReceiptListViewModel 复用：查询必须钉死 flowStatus=data_entry。
        var seen: ReceiptListQuery?
        let vm = ReceiptListViewModel(provider: { query in
            seen = query
            return [self.makeReceipt()]
        })
        vm.query.flowStatus = .dataEntry
        vm.query.pageSize = 50
        vm.query.keyword = "WT-2026"
        await vm.load()
        XCTAssertEqual(seen?.flowStatus, .dataEntry, "队列查询必须钉在数据录入环节")
        XCTAssertEqual(seen?.keyword, "WT-2026")
        XCTAssertEqual(seen?.page, 1)
        XCTAssertEqual(vm.items.count, 1)
    }

    func testEntryLoadAssemblesCatalogAndKeysRecords() async throws {
    // fn: M03.F03.I01
        // 打开录入：按 receiptId 拉样品 + 参数字典，再逐样品拉检测记录，
        // 按 sampleId#parameterCode 键控可查（家族同款键）。
        let vm = DataEntryViewModel(
            catalogLoad: { receiptId in
                XCTAssertEqual(receiptId, "r-1")
                return ([self.makeSample(id: "s-1"), self.makeSample(id: "s-2", code: "YP-002")],
                        [self.makeParameter()])
            },
            recordsLoad: { sampleId in
                sampleId == "s-1" ? [self.makeRecord()] : []
            },
            persist: { _, _, _ in
                struct Never: Error {}
                throw Never()
            }
        )
        await vm.load(receiptId: "r-1")
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.samples.count, 2)
        XCTAssertEqual(vm.parameters.count, 1)
        vm.selectedSampleId = "s-1"
        vm.selectedParameterCode = "P-CE"
        XCTAssertEqual(vm.existingRecord?.id, "tr-1", "同键记录必须能查到")
        vm.selectedParameterCode = "P-OTHER"
        XCTAssertNil(vm.existingRecord, "不同参数 = 无既有记录")
    }

    // MARK: I02 保存检测记录（verdict 随请求体，Q3 裁定）

    func testCreateRequestTrimsAndRequiresCoreFields() throws {
    // fn: M03.F03.I02
        // 样品/参数/result/requirement 必填（trim 后），standardCode 空串归一为
        // 不传；缺任一必填 fail-fast 不打端点（AC-5）。
        let vm = Self.emptyVM()
        vm.selectedSampleId = "s-1"
        vm.selectedParameterCode = "P-CE"
        vm.result = " 45.2 "
        vm.requirement = " ≥42.5 "
        vm.standardCode = "  "
        vm.verdict = "合格"
        let request = try vm.makeCreateRequest()
        XCTAssertEqual(request.sampleId, "s-1")
        XCTAssertEqual(request.parameterCode, "P-CE")
        XCTAssertEqual(request.result, "45.2")
        XCTAssertEqual(request.requirement, "≥42.5")
        XCTAssertNil(request.standardCode, "空串可选字段归一为不传")
        XCTAssertEqual(request.verdict, "合格", "verdict 必须随创建请求体")

        vm.result = "   "
        XCTAssertThrowsError(try vm.makeCreateRequest(), "result 缺失必须 fail-fast")
        vm.result = "45.2"
        vm.selectedSampleId = ""
        XCTAssertThrowsError(try vm.makeCreateRequest(), "样品未选必须 fail-fast")
    }

    func testSaveWithoutRecordCreatesWithVerdictInBody() async {
    // fn: M03.F03.I02
        // 无同键记录 = 走创建；verdict 随 body（AC-2/Q3，不走 setVerdict 端点）。
        let vm = DataEntryViewModel(
            catalogLoad: { _ in ([self.makeSample()], [self.makeParameter()]) },
            recordsLoad: { _ in [] },
            persist: { id, create, _ in
                XCTAssertNil(id, "无既有记录必须走 create 路")
                XCTAssertEqual(create?.verdict, "合格", "verdict 必须随创建请求体")
                return self.makeRecord(id: "tr-new", verdict: "合格")
            }
        )
        await vm.load(receiptId: "r-1")
        vm.selectedSampleId = "s-1"
        vm.selectedParameterCode = "P-CE"
        vm.result = "45.2"
        vm.requirement = "≥42.5"
        vm.verdict = "合格"
        let saved = await vm.save()
        XCTAssertEqual(saved?.id, "tr-new")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSaving, "save 返回后忙态必须落回")
    }

    // MARK: I03 人工改判 verdict（随 update 请求体）

    func testVerdictRevisionWithExistingRecordGoesUpdate() async {
    // fn: M03.F03.I03
        // 同键已有记录 = 走 update(record.id)；改判后的 verdict 随请求体（AC-3/Q3）。
        let vm = DataEntryViewModel(
            catalogLoad: { _ in ([self.makeSample()], [self.makeParameter()]) },
            recordsLoad: { _ in [self.makeRecord(verdict: "合格")] },
            persist: { id, create, update in
                XCTAssertNil(create, "已有记录不许走 create")
                XCTAssertEqual(id, "tr-1", "update 必须携带既有记录 id")
                XCTAssertEqual(update?.sampleId, "s-1")
                XCTAssertEqual(update?.parameterCode, "P-CE")
                XCTAssertEqual(update?.result, "47.8", "改判连带改值随 body")
                XCTAssertEqual(update?.verdict, "不合格", "改判 verdict 必须随更新请求体")
                return self.makeRecord(result: "47.8", verdict: "不合格")
            }
        )
        await vm.load(receiptId: "r-1")
        vm.selectedSampleId = "s-1"
        vm.selectedParameterCode = "P-CE"
        vm.fillFromExisting()
        vm.result = "47.8"
        vm.verdict = "不合格"
        let saved = await vm.save()
        XCTAssertEqual(saved?.verdict, "不合格")
        XCTAssertNil(vm.errorMessage)
    }

    func testSaveFailureReportsAndKeepsFields() async {
        // 端点拒（网络/后端）：errorMessage 呈错，用户输入不清（AC-6）。
        let vm = DataEntryViewModel(
            catalogLoad: { _ in ([self.makeSample()], [self.makeParameter()]) },
            recordsLoad: { _ in [] },
            persist: { _, _, _ in throw SeamedFailure() }
        )
        await vm.load(receiptId: "r-1")
        vm.selectedSampleId = "s-1"
        vm.selectedParameterCode = "P-CE"
        vm.result = "45.2"
        vm.requirement = "≥42.5"
        let saved = await vm.save()
        XCTAssertNil(saved)
        XCTAssertNotNil(vm.errorMessage, "失败必须呈错不打断")
        XCTAssertEqual(vm.result, "45.2", "失败不许清用户输入")
        XCTAssertEqual(vm.requirement, "≥42.5")
    }

    // MARK: I12 act 三动作（operator=真会话身份）

    func testActDataEntryEmbedsSessionOperatorAndGuardsSelection() async throws {
    // fn: M03.F03.I12
        // 复用 ReceivingFlowViewModel：operator = 会话用户名组装进请求体；
        // 空选区 fail-fast 不打端点（REQ-2026-004 已建立的同款缝）。
        var seamCalled = false
        let flow = ReceivingFlowViewModel(operatorName: "alice") { _, _, _ in
            seamCalled = true
            return []
        }
        do {
            _ = try await flow.perform(.submit, ids: [])
            XCTFail("空选区必须 throw")
        } catch {
            XCTAssertFalse(seamCalled, "fail-fast 不许触达网络缝")
        }
        let results = try await flow.perform(.withdraw, ids: ["r-1"])
        XCTAssertEqual(results.count, 0)
        let request = try flow.makeRequest(.submit, ids: ["r-1"])
        XCTAssertEqual(request.operator, "alice", "请求体 operator 必须是会话身份")
    }
}

private struct SeamedFailure: Error {}

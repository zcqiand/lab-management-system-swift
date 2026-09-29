import XCTest
import LabSharedGenerated
@testable import CoreKit

// REQ-2026-008 T-1：样品 ext 补录 CoreKit 契约（红先行）。
// needsForm 判定 / 必填校验 / 合并语义 / persist 缝，全部镜像家族
// SampleExtFieldsModal + ReportPreviewModal.handleExtSubmit。

final class SampleExtTests: XCTestCase {

    private func makeDef(
        key: String, label: String, type: ExtFieldDefType = .text,
        required: Bool? = nil, source: ExtFieldDefSource? = nil
    ) -> ExtFieldDef {
        ExtFieldDef(key: key, label: label, type: type, required: required, source: source)
    }

    private func makeSample(ext: [String: String]) -> Sample {
        Sample(
            id: "s-1", tenantId: "t-1", receiptId: "r-9", sampleCode: "YP-1",
            ext: ext, createdAt: "2026-09-29T09:00:00Z", updatedAt: "2026-09-29T09:00:00Z"
        )
    }

    // MARK: needsForm 判定

    func testNeedsFormWhenKeyMissing() async {
    // fn: M03.F01.I07
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "103", name: "混凝土抗压",
                                      extFields: [
                                        self.makeDef(key: "sampleModel", label: "型号", required: true),
                                        self.makeDef(key: "grade", label: "等级"),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { _, _ in }
        )
        await vm.load(categoryCode: "103", firstSample: self.makeSample(ext: [:]))
        XCTAssertTrue(vm.needsForm, "缺 key 必须出补录门")
        XCTAssertEqual(vm.formFields.map(\.key), ["sampleModel", "grade"], "receipt 侧字段过滤、其余保序")
        XCTAssertEqual(vm.draft["sampleModel"], "", "缺 key 预填空串")
    }

    func testNoFormWhenAllKeysCovered() async {
    // fn: M03.F01.I07
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "103", name: "混凝土抗压",
                                      extFields: [
                                        self.makeDef(key: "sampleModel", label: "型号", required: true),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { _, _ in }
        )
        await vm.load(categoryCode: "103", firstSample: self.makeSample(ext: ["sampleModel": "C30"]))
        XCTAssertFalse(vm.needsForm, "key 全覆盖不出门")
        XCTAssertTrue(vm.formFields.isEmpty)
    }

    func testReceiptSourceFieldsExcludedFromForm() async {
    // fn: M03.F01.I07
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "110", name: "防水",
                                      extFields: [
                                        self.makeDef(key: "pourDate", label: "浇筑日期", source: .receipt),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { _, _ in }
        )
        await vm.load(categoryCode: "110", firstSample: self.makeSample(ext: [:]))
        XCTAssertFalse(vm.needsForm, "source=receipt 字段家族未接入，非范围（同款边界）")
        XCTAssertTrue(vm.formFields.isEmpty)
    }

    func testLoadPrefillsExistingExtValues() async {
    // fn: M03.F01.I07
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "103", name: "混凝土抗压",
                                      extFields: [
                                        self.makeDef(key: "sampleModel", label: "型号", required: true),
                                        self.makeDef(key: "grade", label: "等级"),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { _, _ in }
        )
        await vm.load(categoryCode: "103",
                      firstSample: self.makeSample(ext: ["sampleModel": "C30"]))
        XCTAssertTrue(vm.needsForm, "覆盖一项仍缺另一项 → 出门")
        XCTAssertEqual(vm.draft, ["sampleModel": "C30", "grade": ""], "现有值预填、缺失键空串")
    }

    // MARK: 必填校验

    func testValidateBlocksOnEmptyRequired() async {
    // fn: M03.F01.I07
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "103", name: "混凝土抗压",
                                      extFields: [
                                        self.makeDef(key: "sampleModel", label: "型号", required: true),
                                        self.makeDef(key: "grade", label: "等级"),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { _, _ in XCTFail("校验不过不得打端点") }
        )
        await vm.load(categoryCode: "103", firstSample: self.makeSample(ext: [:]))
        vm.setValue("  ", forKey: "sampleModel")
        let ok = await vm.save(sampleID: "s-1")
        XCTAssertFalse(ok, "必填空白必须阻断")
        XCTAssertEqual(vm.validationErrors["sampleModel"], "必填")
        XCTAssertTrue(vm.didSave == false)
    }

    // MARK: 保存合并

    func testSaveMergesExistingKeysAndNewValues() async {
    // fn: M03.F01.I07
        var persisted: (String, [String: String])?
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "103", name: "混凝土抗压",
                                      extFields: [
                                        self.makeDef(key: "sampleModel", label: "型号", required: true),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { id, ext in
                persisted = (id, ext)
            }
        )
        await vm.load(categoryCode: "103",
                      firstSample: self.makeSample(ext: ["sampleModel": "C30", "brand": "金桥"]))
        vm.setValue("C40", forKey: "sampleModel")
        let ok = await vm.save(sampleID: "s-1")
        XCTAssertTrue(ok)
        XCTAssertTrue(vm.didSave)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(persisted?.0, "s-1")
        XCTAssertEqual(persisted?.1, ["sampleModel": "C40", "brand": "金桥"],
                       "现有 key 全保留 + 表单值覆盖")
    }

    func testSaveFailureSurfacesErrorAndKeepsDraft() async {
    // fn: M03.F01.I07
        struct Boom: Error {}
        let vm = SampleExtViewModel(
            reportNamesLoad: { _ in
                [InspectionReportName(code: "103", name: "混凝土抗压",
                                      extFields: [
                                        self.makeDef(key: "sampleModel", label: "型号", required: true),
                                      ], sortOrder: 1, createdAt: "", updatedAt: "")]
            },
            persist: { _, _ in throw Boom() }
        )
        await vm.load(categoryCode: "103", firstSample: self.makeSample(ext: [:]))
        vm.setValue("C40", forKey: "sampleModel")
        let ok = await vm.save(sampleID: "s-1")
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.didSave)
        XCTAssertEqual(vm.draft["sampleModel"], "C40", "失败后草稿保留可重交")
    }
}

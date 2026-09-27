import XCTest
@testable import CoreKit
import LabSharedGenerated

/// REQ-2026-002 T-2：表单校验/请求构造（I02）、详情加载（I06）、删除（I03）。
/// 网络缝 = 注入 async 闭包，单测不发真网络；PATCH 语义 = 仅携带变更字段。
final class ReceiptFormDetailTests: XCTestCase {

    // MARK: I02 表单校验（AC-3 必填集）

    private func filledFields() -> ReceiptFormFields {
        var f = ReceiptFormFields()
        f.contractId = "c-1"
        f.commissionCode = "WT-2026-001"
        f.commissionDate = "2026-09-28"
        f.categoryCode = "CAT01"
        f.receivedBy = "alice"
        f.sampleSource = "witness"
        f.testCategory = "detected"
        return f
    }

    func testValidationRequiresFullRequiredSet() {
        // fn: M03.F01.I02
        let vm = ReceiptFormViewModel(fields: ReceiptFormFields())
        XCTAssertFalse(vm.validate(), "全空必填集不过")
        XCTAssertFalse(vm.validationErrors.isEmpty, "逐项标错")
        vm.fields = filledFields()
        vm.fields.contractId = "   " // 纯空白 = 缺失
        XCTAssertFalse(vm.validate(), "空白视同缺失")
        vm.fields.contractId = "c-1"
        XCTAssertTrue(vm.validate())
        XCTAssertTrue(vm.validationErrors.isEmpty)
    }

    func testMakeCreateRequestCarriesRequiredSet() throws {
        // fn: M03.F01.I02
        let vm = ReceiptFormViewModel(fields: filledFields())
        let request = try vm.makeCreateRequest()
        XCTAssertEqual(request.contractId, "c-1")
        XCTAssertEqual(request.commissionCode, "WT-2026-001")
        XCTAssertEqual(request.commissionDate, "2026-09-28")
        XCTAssertEqual(request.categoryCode, "CAT01")
        XCTAssertEqual(request.receivedBy, "alice")
        XCTAssertEqual(request.sampleSource, "witness")
        XCTAssertEqual(request.testCategory, "detected")
    }

    func testMakeCreateRequestFailsFastWhenInvalid() {
        let vm = ReceiptFormViewModel(fields: ReceiptFormFields())
        XCTAssertThrowsError(try vm.makeCreateRequest()) { error in
            guard case ReceiptFormError.invalidFields = error else {
                return XCTFail("期望 invalidFields，实际 \(error)")
            }
        }
    }

    // MARK: I02 PATCH 语义（AC-4 仅携带变更字段）

    func testMakeUpdateRequestCarriesOnlyChangedFields() throws {
        // fn: M03.F01.I02
        let original = filledFields()
        var changed = original
        changed.receivedBy = "bob"
        changed.sampleSource = "supplied"
        let vm = ReceiptFormViewModel(fields: changed)
        let request = try vm.makeUpdateRequest(original: original)
        XCTAssertEqual(request.receivedBy, "bob", "变更字段必须携带")
        XCTAssertEqual(request.sampleSource, "supplied")
        XCTAssertNil(request.contractId, "未变更字段不许携带（PATCH 语义）")
        XCTAssertNil(request.commissionCode)
        XCTAssertNil(request.categoryCode)
        XCTAssertNil(request.testCategory)
    }

    func testUpdateWithClearedRequiredFieldFailsValidation() {
        // fn: M03.F01.I02（必填集在编辑态同样成立：清空必填不是合法 PATCH）
        let vm = ReceiptFormViewModel(fields: filledFields())
        vm.fields.sampleSource = "  "
        XCTAssertFalse(vm.validate())
        XCTAssertThrowsError(try vm.makeUpdateRequest(original: filledFields()))
    }

    // MARK: I02 save 路由（AC-3/AC-4：id 缺=新建，id 有=更新）

    func testSaveRoutesCreateOrUpdateByPresenceOfID() async throws {
        // fn: M03.F01.I02
        var calls: [(id: String?, create: Bool, update: Bool)] = []
        let vm = ReceiptFormViewModel(fields: filledFields()) { id, create, update in
            calls.append((id, create != nil, update != nil))
            let json = """
            {"id":"\(id ?? "r-new")","tenantId":"t-1","contractId":"c-1",
            "commissionCode":"WT-2026-001","commissionDate":"2026-09-28",
            "categoryCode":"CAT01","receivedBy":"alice","sampleSource":"witness",
            "testCategory":"detected","flowStatus":"receiving","flowHistory":[],
            "createdAt":"2026-09-28T08:00:00Z","updatedAt":"2026-09-28T08:00:00Z"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(SampleReceipt.self, from: json)
        }
        _ = try await vm.save(id: nil, original: nil)
        _ = try await vm.save(id: "r-1", original: filledFields())
        XCTAssertEqual(calls.count, 2)
        XCTAssertNil(calls[0].id)
        XCTAssertTrue(calls[0].create, "无 id → create 请求")
        XCTAssertFalse(calls[0].update)
        XCTAssertEqual(calls[1].id, "r-1")
        XCTAssertTrue(calls[1].update, "有 id → update（PATCH）请求")
        XCTAssertFalse(calls[1].create)
    }

    func testSaveFailsFastOnInvalidFieldsWithoutCallingEndpoint() async throws {
        var called = false
        let vm = ReceiptFormViewModel(fields: ReceiptFormFields()) { _, _, _ in
            called = true
            struct Boom: Error {}
            throw Boom()
        }
        do {
            _ = try await vm.save(id: nil, original: nil)
            XCTFail("非法必填集必须 throw")
        } catch let error as ReceiptFormError {
            XCTAssertEqual(error, .invalidFields)
        }
        XCTAssertFalse(called, "校验失败不许打到端点")
    }

    // MARK: I06 详情加载（AC-6）

    func testDetailLoadFetchesReceiptAndHistory() async throws {
        // fn: M03.F01.I06
        let receiptJSON = """
        {"id":"r-1","tenantId":"t-1","contractId":"c-1","commissionCode":"WT-2026-001",
        "commissionDate":"2026-09-28","categoryCode":"CAT01","receivedBy":"alice",
        "sampleSource":"witness","testCategory":"detected","flowStatus":"receiving",
        "flowHistory":[],"createdAt":"2026-09-28T08:00:00Z","updatedAt":"2026-09-28T08:00:00Z"}
        """.data(using: .utf8)!
        let vm = ReceiptDetailViewModel(fetch: { id in
            XCTAssertEqual(id, "r-1")
            let receipt = try JSONDecoder().decode(SampleReceipt.self, from: receiptJSON)
            let history = [
                FlowHistoryEntry(action: .submit, from: .receiving, to: .taskAssignment,
                                 `operator`: "alice", at: "2026-09-28T09:00:00Z"),
            ]
            return (receipt, history)
        })
        await vm.load(id: "r-1")
        XCTAssertEqual(vm.receipt?.id, "r-1")
        XCTAssertEqual(vm.history.first?.to, .taskAssignment)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testDetailLoadErrorSurfacesMessage() async throws {
        // fn: M03.F01.I06
        struct Boom: Error {}
        let vm = ReceiptDetailViewModel(fetch: { _ in throw Boom() })
        await vm.load(id: "r-1")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.receipt)
        XCTAssertTrue(vm.history.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: I03 删除（AC-5）

    func testDeleteCallsEndpointWithConfirmedID() async throws {
        // fn: M03.F01.I03
        // 请求构造：DELETE /api/receipts/{id}
        let builder = ReceiptsAPI.receiptsDeleteReceiptWithRequestBuilder(id: "r-1")
        XCTAssertEqual(builder.method, "DELETE")
        XCTAssertTrue(builder.URLString.contains("/api/receipts/r-1"))

        var deleted: String?
        let vm = ReceiptDeleteViewModel { id in
            deleted = id
        }
        await vm.delete(id: "r-1")
        XCTAssertEqual(deleted, "r-1")
        XCTAssertNil(vm.errorMessage)
    }

    func testDeleteFailureSurfacesMessageWithoutThrow() async throws {
        // fn: M03.F01.I03
        struct Boom: Error {}
        let vm = ReceiptDeleteViewModel { _ in throw Boom() }
        await vm.delete(id: "r-1")
        XCTAssertNotNil(vm.errorMessage, "删除失败以 errorMessage 呈现，不许崩")
    }
}

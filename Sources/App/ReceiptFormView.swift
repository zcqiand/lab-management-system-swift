import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-002 T-3：新建/编辑接样单表单（I02，AC-3/AC-4）。
// 必填集校验与请求构造全在 ReceiptFormViewModel；本层只做绑定与标错。

struct ReceiptFormView: View {
    /// nil = 新建；非 nil = 编辑（表单预填）。
    let receipt: SampleReceipt?

    @State private var fields = ReceiptFormFields()
    @State private var original = ReceiptFormFields()
    @State private var validationErrors: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                field("contractId", "委托单位 ID", \.contractId)
                field("commissionCode", "委托编号", \.commissionCode)
                field("commissionDate", "委托日期（YYYY-MM-DD）", \.commissionDate)
                field("categoryCode", "检测类别代码", \.categoryCode)
                field("receivedBy", "接样人", \.receivedBy)
                field("sampleSource", "样品来源", \.sampleSource)
                field("testCategory", "检测性质", \.testCategory)

                if isSaving {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(receipt == nil ? "新建接样单" : "编辑接样单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard let receipt else { return }
        var f = ReceiptFormFields()
        f.contractId = receipt.contractId
        f.commissionCode = receipt.commissionCode
        f.commissionDate = receipt.commissionDate
        f.categoryCode = receipt.categoryCode
        f.receivedBy = receipt.receivedBy
        f.sampleSource = receipt.sampleSource
        f.testCategory = receipt.testCategory
        fields = f
        original = f
    }

    private func field(
        _ name: String, _ title: String, _ key: WritableKeyPath<ReceiptFormFields, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(title, text: Binding(
                get: { fields[keyPath: key] },
                set: { fields[keyPath: key] = $0 }
            ))
            .autocorrectionDisabled()
            if validationErrors.contains(name) {
                Text("必填").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func save() async {
        let vm = ReceiptFormViewModel(fields: fields, persist: APIGlue.persist)
        do {
            isSaving = true
            errorMessage = nil
            _ = try await vm.save(id: receipt?.id, original: original)
            dismiss()
        } catch let error as ReceiptFormError {
            _ = vm.validate()
            validationErrors = vm.validationErrors
        } catch {
            errorMessage = String(describing: error)
        }
        isSaving = false
    }
}

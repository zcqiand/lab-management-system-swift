import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-002 T-3：act 确认页（I04 SUBMIT / I08 三动作）。
// 操作人 = 显式输入（空则禁用确认，禁身份兜底）；流转语义在后端，
// 逐单结果 ok=false 以 alert 呈现不崩。

struct ActConfirmSheet: View {
    let action: FlowAction
    let ids: [String]
    /// (结果, 失败信息)；结果非空时调用方回填列表。
    let onDone: (_ results: [FlowActionResult], _ message: String?) -> Void

    @State private var operatorName = ""
    @State private var reason = ""
    @State private var isRunning = false
    @Environment(\.dismiss) private var dismiss

    private var canConfirm: Bool {
        !operatorName.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("操作") {
                    LabeledContent("动作", value: action.label)
                    LabeledContent("单数", value: "\(ids.count)")
                }
                Section("操作人（登录未接入，显式输入）") {
                    TextField("操作人", text: $operatorName)
                        .autocorrectionDisabled()
                }
                if action == .return {
                    Section("退回理由") {
                        TextField("理由", text: $reason, axis: .vertical)
                    }
                }
                if isRunning {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle("确认\(action.label)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { Task { await perform() } }
                        .disabled(!canConfirm)
                }
            }
        }
    }

    private func perform() async {
        isRunning = true
        defer { isRunning = false }
        let trimmedReason = action == .return
            ? reason.trimmingCharacters(in: .whitespaces)
            : nil
        let flow = ReceivingFlowViewModel(
            operatorName: operatorName.trimmingCharacters(in: .whitespaces)
        ) { act, actIds, actReason in
            try await APIGlue.act(act, ids: actIds, operator: operatorName, reason: actReason)
        }
        do {
            let results = try await flow.perform(action, ids: ids, reason: trimmedReason)
            let failures = results.filter { !$0.ok }
            let message: String?
            if let failure = failures.first {
                message = failure.message ?? "存在未成功的单（\(failures.count)/\(results.count)）"
            } else {
                message = nil
            }
            onDone(results, message)
        } catch {
            onDone([], String(describing: error))
        }
    }
}

import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-002 T-3：act 确认页（I04 SUBMIT / I08 三动作 / REQ-2026-004 I05 分配）。
// REQ-2026-004 Q3 起：操作人 = 真会话身份（调用方从 SessionStore 注入，输入框
// 删除，ADR-0019 显式输入临时解退役）；身份缺席由 ReceivingFlowViewModel
// fail-fast（missingOperator）→ alert 呈现。逐单结果 ok=false 以 alert 呈现不崩。

struct ActConfirmSheet: View {
    /// act 端点档位：接样 receiving / 任务分配 assigning / 数据录入 dataEntry
    /// （各阶段端点不同，动作语义同）。
    enum ActEndpoint {
        case receiving
        case assigning
        case dataEntry
    }

    let action: FlowAction
    let ids: [String]
    /// 操作人 = 会话用户名（REQ-2026-004 Q3）；缺席时空串 → 确认禁用 + VM 二次 fail-fast。
    let operatorName: String
    var endpoint: ActEndpoint = .receiving
    /// (结果, 失败信息)；结果非空时调用方回填列表。
    let onDone: (_ results: [FlowActionResult], _ message: String?) -> Void

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
                    LabeledContent("操作人", value: operatorName)
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
        let trimmedOperator = operatorName.trimmingCharacters(in: .whitespaces)
        let flow = ReceivingFlowViewModel(
            operatorName: trimmedOperator
        ) { act, actIds, actReason in
            switch endpoint {
            case .receiving:
                try await APIGlue.act(act, ids: actIds, operator: trimmedOperator, reason: actReason)
            case .assigning:
                try await APIGlue.assigningAct(
                    act, ids: actIds, operator: trimmedOperator, reason: actReason
                )
            case .dataEntry:
                try await APIGlue.dataEntryAct(
                    act, ids: actIds, operator: trimmedOperator, reason: actReason
                )
            }
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

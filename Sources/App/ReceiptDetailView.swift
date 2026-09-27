import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-002 T-3：接样单详情（I06 时间线）+ act 三动作入口（I04/I08）。
// act 的操作人 = 用户显式输入（登录 UI 未落地，禁身份兜底 ADR-0019）。

struct ReceiptDetailView: View {
    let receiptID: String
    let session: AppSession

    @StateObject private var vm = ReceiptDetailViewModel(fetch: { id in
        try await APIGlue.detail(id)
    })
    @State private var actTarget: ActTargetItem?

    var body: some View {
        List {
            if let receipt = vm.receipt {
                Section("接样信息") {
                    labeled("委托编号", receipt.commissionCode)
                    labeled("委托日期", receipt.commissionDate)
                    labeled("检测类别", receipt.categoryCode)
                    labeled("接样人", receipt.receivedBy)
                    labeled("样品来源", receipt.sampleSource)
                    labeled("检测性质", receipt.testCategory)
                    labeled("当前环节", receipt.flowStatus.label)
                }
            }
            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            if let errorMessage = vm.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            Section("流程历史") {
                if vm.history.isEmpty && !vm.isLoading {
                    Text("暂无流转记录").foregroundStyle(.secondary).font(.footnote)
                }
                ForEach(vm.history.indices, id: \.self) { index in
                    let entry = vm.history[index]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.action.label).font(.headline)
                            Spacer()
                            Text(entry.`operator`).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(entry.from.label) → \(entry.to.label)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(entry.at).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if vm.receipt?.flowStatus == .receiving {
                Section {
                    Button {
                        actTarget = ActTargetItem(action: .submit, targetID: receiptID)
                    } label: {
                        Label("提交", systemImage: "paperplane")
                    }
                }
            }
        }
        .navigationTitle("接样单详情")
        .task { await vm.load(id: receiptID) }
        .sheet(item: $actTarget) { target in
            ActConfirmSheet(action: target.action, ids: [target.targetID]) { _, _ in
                actTarget = nil
                Task { await vm.load(id: receiptID) }
            }
        }
    }

    @ViewBuilder
    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

extension FlowAction {
    var label: String {
        switch self {
        case .submit: "提交"
        case .return: "退回"
        case .withdraw: "撤回"
        }
    }
}

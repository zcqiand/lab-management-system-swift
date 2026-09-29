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
    /// REQ-2026-007 I03：数据面报告预览 sheet。
    @State private var showPreview = false

    var body: some View {
        List {
            if let receipt = vm.receipt {
                Section("接样信息") {
                    labeled("委托编号", receipt.commissionCode)
                    labeled("委托日期", receipt.commissionDate)
                    // REQ-2026-007 I01：接样信息全字段面（家族 ReceiptDetail 同款，
                    // 缺席字段显示 —）。
                    labeled("工程名称", receipt.projectName)
                    labeled("委托单位", receipt.clientUnit)
                    labeled("建设单位", receipt.buildingUnit)
                    labeled("监理单位", receipt.supervisorUnit)
                    labeled("施工单位", receipt.constructionUnit)
                    labeled("见证单位", receipt.witnessUnit)
                    labeled("见证人", receipt.witness)
                    labeled("送检人", receipt.inspector)
                    labeled("取样地点", receipt.samplingLocation)
                    labeled("报告类别", receipt.categoryCode)
                    labeled("样品来源", receipt.sampleSource)
                    labeled("检测性质", receipt.testCategory)
                    labeled("合同 ID", receipt.contractId)
                    labeled("当前环节", receipt.flowStatus.label)
                    labeled("检测结果", receipt.result?.label)
                    labeled("检测负责人", receipt.assigneeName)
                    labeled("计划检测日期", receipt.plannedTestDate)
                    labeled("报告编号", receipt.reportCode)
                    labeled("报告日期", receipt.reportDate)
                }
                Section {
                    Button {
                        showPreview = true
                    } label: {
                        Label("报告预览", systemImage: "doc.text")
                    }
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
        .sheet(isPresented: $showPreview) {
            ReportPreviewSheet(receiptID: receiptID)
        }
        .sheet(item: $actTarget) { target in
            ActConfirmSheet(action: target.action, ids: [target.targetID], operatorName: session.store.user?.username ?? "") { _, _ in
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

    /// 可选字段缺席显示 —（REQ-2026-007 AC-2）。
    @ViewBuilder
    private func labeled(_ title: String, _ value: String?) -> some View {
        labeled(title, value ?? "—")
    }
}

extension ReceiptResult {
    var label: String {
        switch self {
        case .pass: "合格"
        case .fail: "不合格"
        case .empty: "—"
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

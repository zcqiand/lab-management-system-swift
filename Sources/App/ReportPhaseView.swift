import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-006 T-2：报告四阶段页（M03.F05~F08）。
// 镜像家族 ReportPhasePage 单组件（stage + submitLabel 参数化）+ 4 个入口：
// 一个 ReportPhaseView 按 ReportPhase 档位复用，不复制四份（AC-6）。
// I01 队列 = ReceiptListViewModel 复用（query.flowStatus 钉本阶段，page 1/
// pageSize 50 + keyword）；I02 操作 = 「{submitLabel}」/「退回」；
// act 三动作 = ActConfirmSheet 复用（endpoint=.phase(phase)，operator=会话身份）；
// 发放的报告编号后端 act 语义生成，行上只显示 reportCode（Q2 裁定）。

struct ReportPhaseView: View {
    let session: AppSession
    let phase: ReportPhase

    @StateObject private var vm: ReceiptListViewModel
    @State private var keyword = ""
    @State private var actTarget: ActTargetItem?
    @State private var errorMessage: String?

    init(session: AppSession, phase: ReportPhase) {
        self.session = session
        self.phase = phase
        _vm = StateObject(wrappedValue: ReceiptListViewModel(provider: { query in
            try await APIGlue.list(query)
        }))
    }

    var body: some View {
        listView
            .sheet(item: $actTarget) { target in
                ActConfirmSheet(
                    action: target.action, ids: [target.targetID],
                    operatorName: session.store.user?.username ?? "",
                    endpoint: .phase(phase)
                ) { results, message in
                    if results.isEmpty == false {
                        vm.apply(results)
                    }
                    if let message {
                        errorMessage = message
                    }
                    actTarget = nil
                }
            }
            .alert(
                "操作结果",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: 列表主体（I01 队列半边）

    private var listView: some View {
        List {
            queueRows
            loadingRow
            errorRow
        }
        .refreshable { await vm.load() }
        .searchable(text: $keyword, prompt: "委托编号 / 关键字")
        .onSubmit(of: .search) {
            vm.query.keyword = keyword.isEmpty ? nil : keyword
            Task { await vm.load() }
        }
        .task {
            // 队列查询钉死本阶段环节（I01）；page 1/pageSize 50 镜像家族。
            vm.query.flowStatus = phase.flowStatus
            vm.query.pageSize = 50
            await vm.load()
        }
        .navigationTitle(phase.phaseTitle)
    }

    @ViewBuilder
    private var queueRows: some View {
        ForEach(vm.items, id: \.id) { receipt in
            row(receipt)
        }
    }

    @ViewBuilder
    private var loadingRow: some View {
        if vm.isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
    }

    @ViewBuilder
    private var errorRow: some View {
        if let message = vm.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func row(_ receipt: SampleReceipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(receipt.commissionCode).font(.headline)
                Spacer()
            }
            // I02：报告编号后端 act 语义生成，此处只显示（Q2 裁定）。
            if let reportCode = receipt.reportCode, !reportCode.isEmpty {
                Text("报告编号 \(reportCode)").font(.subheadline).foregroundStyle(.secondary)
            }
            rowActions(receipt)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowActions(_ receipt: SampleReceipt) -> some View {
        HStack(spacing: 14) {
            // I02：本阶段 submit 按钮（文案随阶段：审核通过/批准/发放/归档完成）。
            Button {
                actTarget = ActTargetItem(action: .submit, targetID: receipt.id)
            } label: {
                Label(phase.submitLabel, systemImage: "checkmark.circle")
                    .font(.footnote)
            }
            // I02：驳回 = act return 批次回退一阶。
            Button {
                actTarget = ActTargetItem(action: .return, targetID: receipt.id)
            } label: {
                Label("退回", systemImage: "arrow.uturn.left")
                    .font(.footnote)
            }
            Spacer()
            // act 三动作收尾：撤回（同菜单语义，家族同款）。
            Menu {
                Button("撤回") {
                    actTarget = ActTargetItem(action: .withdraw, targetID: receipt.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .buttonStyle(.borderless)
    }
}

/// 报告阶段入口目标（toolbar 报告菜单用；navigationDestination(item:) 要 Hashable）。
struct ReportPhaseTargetItem: Identifiable, Hashable {
    let phase: ReportPhase
    var id: String { phase.rawValue }
}

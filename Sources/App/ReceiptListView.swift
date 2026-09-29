import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-002 T-3：接样单列表（I01 三态过滤/keyword/分页）+ 删除确认（I03）
// + act 入口（I04/I08）+ 新建表单入口（I02）。行为全部走 CoreKit ViewModel。
// body 按子表达式拆分（整段 SwiftUI 表达式编译器类型检查超时）。

struct ReceiptListView: View {
    let session: AppSession

    @StateObject private var vm = ReceiptListViewModel(provider: { query in
        try await APIGlue.list(query)
    })
    @State private var filter: ReceiptFilter = .all
    @State private var keyword = ""
    @State private var showCreate = false
    @State private var showAccount = false
    @State private var actTarget: ActTargetItem?
    @State private var deleteTarget: SampleReceipt?
    @State private var actErrorMessage: String?
    /// 报告四阶段入口目标（REQ-2026-006：报告菜单 → ReportPhaseView）。
    @State private var phaseTarget: ReportPhaseTargetItem?

    var body: some View {
        NavigationStack {
            listView
        }
        .sheet(isPresented: $showCreate) {
            ReceiptFormView(receipt: nil)
        }
        .sheet(isPresented: $showAccount, onDismiss: {
            // 租户切换/登出回来都整表刷新（M00.F02.I01：切换后列表刷新）。
            Task { await vm.load() }
        }) {
            AccountView(session: session)
        }
        .sheet(item: $actTarget) { target in
            ActConfirmSheet(action: target.action, ids: [target.targetID], operatorName: session.store.user?.username ?? "") { results, message in
                if results.isEmpty == false {
                    vm.apply(results)
                }
                if let message {
                    actErrorMessage = message
                }
                actTarget = nil
            }
        }
        .alert(
            "操作结果",
            isPresented: Binding(
                get: { actErrorMessage != nil },
                set: { if !$0 { actErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actErrorMessage ?? "")
        }
    }

    // MARK: 列表主体

    private var listView: some View {
        List {
            filterPicker
            receiptRows
            loadingRow
            errorRow
        }
        .refreshable { await vm.load() }
        .searchable(text: $keyword, prompt: "委托编号 / 关键字")
        .onSubmit(of: .search) {
            vm.query.keyword = keyword.isEmpty ? nil : keyword
            Task { await vm.load() }
        }
        .task(id: filter) {
            vm.query.filter = filter
            await vm.load()
        }
        .toolbar {
            Button {
                showAccount = true
            } label: {
                Image(systemName: "person.circle")
            }
            // REQ-2026-004：任务分配页入口（流程第二环节）。
            NavigationLink {
                TaskAssignmentView(session: session)
            } label: {
                Image(systemName: "checklist")
            }
            // REQ-2026-005：数据录入页入口（流程第三环节）。
            NavigationLink {
                DataEntryView(session: session)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            // REQ-2026-006：报告四阶段入口（同一流程线后四环节，单组件四档位）。
            Menu {
                ForEach(ReportPhase.allCases, id: \.self) { phase in
                    Button(phase.phaseTitle) {
                        phaseTarget = ReportPhaseTargetItem(phase: phase)
                    }
                }
            } label: {
                Image(systemName: "doc.plaintext")
            }
            Button {
                showCreate = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .navigationTitle("接样单")
        .navigationDestination(item: $phaseTarget) { target in
            ReportPhaseView(session: session, phase: target.phase)
        }
        .confirmationDialog(
            deleteTarget.map { "删除接样单 \($0.commissionCode)？" } ?? "",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            deleteButtons
        }
    }

    private var filterPicker: some View {
        Picker("状态", selection: $filter) {
            ForEach(ReceiptFilter.allCases, id: \.self) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var receiptRows: some View {
        ForEach(vm.items, id: \.id) { receipt in
            NavigationLink {
                ReceiptDetailView(receiptID: receipt.id, session: session)
            } label: {
                row(receipt)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                swipeActions(for: receipt)
            }
            .onAppear {
                if receipt.id == vm.items.last?.id {
                    Task { await vm.loadNextPage() }
                }
            }
        }
    }

    @ViewBuilder
    private var loadingRow: some View {
        if vm.isLoading && !vm.items.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
    }

    @ViewBuilder
    private var errorRow: some View {
        if let errorMessage = vm.errorMessage {
            Text(errorMessage).foregroundStyle(.red).font(.footnote)
        }
    }

    @ViewBuilder
    private func swipeActions(for receipt: SampleReceipt) -> some View {
        Button(role: .destructive) {
            deleteTarget = receipt
        } label: {
            Label("删除", systemImage: "trash")
        }
        if receipt.flowStatus == .receiving {
            Button {
                actTarget = ActTargetItem(action: .submit, targetID: receipt.id)
            } label: {
                Label("提交", systemImage: "paperplane")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var deleteButtons: some View {
        Button("删除", role: .destructive) {
            guard let id = deleteTarget?.id else { return }
            deleteTarget = nil
            Task { await delete(id) }
        }
        Button("取消", role: .cancel) { deleteTarget = nil }
    }

    // MARK: 行为

    private func delete(_ id: String) async {
        let deleter = ReceiptDeleteViewModel(delete: APIGlue.deleteReceipt)
        await deleter.delete(id: id)
        if let message = deleter.errorMessage {
            actErrorMessage = message
        } else {
            await vm.load()
        }
    }

    // MARK: 行视图

    @ViewBuilder
    private func row(_ receipt: SampleReceipt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(receipt.commissionCode).font(.headline)
                Spacer()
                Text(receipt.flowStatus.label)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text("\(receipt.categoryCode) · \(receipt.receivedBy)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// sheet(item:) 需要 Identifiable 的 act 目标。
struct ActTargetItem: Identifiable {
    var id: String { action.rawValue + targetID }
    let action: FlowAction
    let targetID: String
}

extension FlowStatus {
    var label: String {
        switch self {
        case .receiving: "接样"
        case .taskAssignment: "任务分配"
        case .dataEntry: "数据录入"
        case .review: "审核"
        case .approval: "批准"
        case .issuance: "发放"
        case .archived: "归档"
        case .completed: "完成"
        }
    }
}

extension ReceiptFilter {
    var label: String {
        switch self {
        case .all: "全部"
        case .notYet: "待提交"
        case .submitted: "已提交"
        }
    }
}

import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-004 T-2：任务分配页（M03.F02）。
// I01 队列 = ReceiptListViewModel 复用（query.flowStatus 钉 task_assignment，
// page 1/pageSize 50 + keyword，镜像家族 TaskAssignmentList）；
// I02 安排/取消 = AssignSheet 手填姓名+日期（Q2 裁定）→ receiptsAssignTask；
// I05 act 三动作 = ActConfirmSheet 复用（operator=会话身份）。
// 行为全走 CoreKit ViewModel；body 按子表达式拆分（编译器类型检查超时惯例）。

struct TaskAssignmentView: View {
    let session: AppSession

    @StateObject private var vm = ReceiptListViewModel(provider: { query in
        try await APIGlue.list(query)
    })
    @State private var keyword = ""
    @State private var assignTarget: SampleReceipt?
    @State private var actTarget: ActTargetItem?
    @State private var errorMessage: String?

    var body: some View {
        listView
            .sheet(item: $assignTarget) { receipt in
                AssignSheet(receipt: receipt) { message in
                    assignTarget = nil
                    if let message {
                        errorMessage = message
                    } else {
                        Task { await vm.load() }
                    }
                }
            }
            .sheet(item: $actTarget) { target in
                ActConfirmSheet(
                    action: target.action, ids: [target.targetID],
                    operatorName: session.store.user?.username ?? "",
                    endpoint: .assigning
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

    // MARK: 列表主体（I01）

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
            // 队列查询钉死分配环节（I01）；page 1/pageSize 50 镜像家族。
            vm.query.flowStatus = .taskAssignment
            vm.query.pageSize = 50
            await vm.load()
        }
        .navigationTitle("任务分配")
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
                if let name = receipt.assigneeName, !name.isEmpty {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("未分配").font(.caption).foregroundStyle(.orange)
                }
            }
            if let projectName = receipt.projectName, !projectName.isEmpty {
                Text(projectName).font(.subheadline).foregroundStyle(.secondary)
            }
            if let date = receipt.plannedTestDate, !date.isEmpty {
                Text("计划检测：\(date)").font(.caption).foregroundStyle(.secondary)
            }
            rowActions(receipt)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowActions(_ receipt: SampleReceipt) -> some View {
        HStack(spacing: 14) {
            // I02：安排（未分配/重安排同一入口，表单预填）
            Button {
                assignTarget = receipt
            } label: {
                Label("安排", systemImage: "person.badge.checkmark")
                    .font(.footnote)
            }
            // I02：取消安排（已分配才可清空）
            if receipt.assigneeName != nil {
                Button(role: .destructive) {
                    Task { await cancelAssign(receipt) }
                } label: {
                    Label("取消安排", systemImage: "person.badge.minus")
                        .font(.footnote)
                }
            }
            Spacer()
            // I05：act 三动作菜单
            Menu {
                Button("提交") {
                    actTarget = ActTargetItem(action: .submit, targetID: receipt.id)
                }
                Button("退回接样") {
                    actTarget = ActTargetItem(action: .return, targetID: receipt.id)
                }
                Button("撤回") {
                    actTarget = ActTargetItem(action: .withdraw, targetID: receipt.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .buttonStyle(.borderless)
    }

    private func cancelAssign(_ receipt: SampleReceipt) async {
        // 取消安排 = 全空字段清空请求（CoreKit AssignTaskViewModel 取消语义）。
        let assignVM = AssignTaskViewModel { id, _ in
            try await APIGlue.assignTask(id, AssignTaskRequest())
        }
        _ = await assignVM.save(id: receipt.id)
        if let message = assignVM.errorMessage {
            errorMessage = message
        } else {
            await vm.load()
        }
    }
}

// MARK: I02 安排对话框（手填姓名+日期，家族同款）

private struct AssignSheet: View {
    let receipt: SampleReceipt
    let onDone: (_ message: String?) -> Void

    @StateObject private var form: AssignTaskViewModel
    @State private var plannedDate: Date
    @Environment(\.dismiss) private var dismiss

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(receipt: SampleReceipt, onDone: @escaping (String?) -> Void) {
        self.receipt = receipt
        self.onDone = onDone
        _form = StateObject(wrappedValue: AssignTaskViewModel { id, request in
            try await APIGlue.assignTask(id, request)
        })
        // 预填：已有安排回填；缺省今天（家族 openAssign 同款）。
        let existingName = receipt.assigneeName ?? ""
        _plannedDate = State(initialValue: Self.parseDay(receipt.plannedTestDate) ?? Date())
        _form.wrappedValue.assigneeName = existingName
        _form.wrappedValue.plannedTestDate = receipt.plannedTestDate
            ?? Self.dayFormatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("接样单") {
                    LabeledContent("委托编号", value: receipt.commissionCode)
                }
                Section("安排检测") {
                    TextField("检测人员姓名", text: Binding(
                        get: { form.assigneeName },
                        set: { form.assigneeName = $0 }
                    ))
                    .autocorrectionDisabled()
                    DatePicker("计划检测日期", selection: $plannedDate, displayedComponents: .date)
                        .onChange(of: plannedDate) { _, newValue in
                            form.plannedTestDate = Self.dayFormatter.string(from: newValue)
                        }
                }
                if let message = form.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("安排检测人员")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        // 保存前把 DatePicker 当前值同步进表单（onChange 不覆盖手动路径）。
        form.plannedTestDate = Self.dayFormatter.string(from: plannedDate)
        let saved = await form.save(id: receipt.id)
        onDone(saved == nil ? (form.errorMessage ?? "保存失败") : nil)
    }

    private static func parseDay(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return dayFormatter.date(from: text)
    }
}

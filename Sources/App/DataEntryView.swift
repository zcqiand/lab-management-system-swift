import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-005 T-2：数据录入页（M03.F03）。
// I01 队列 = ReceiptListViewModel 复用（query.flowStatus 钉 data_entry，page 1/
// pageSize 50 + keyword，镜像家族 DataEntryList）+ 行点「录入结果」弹 EntrySheet
// （样品/参数 Picker + 表单，按 sampleId#parameterCode 有记录=更新否则创建）；
// I03 改判 = sheet 内 verdict 选择器改值随保存 body（Q3 裁定）；
// I12 act 三动作 = ActConfirmSheet 复用（endpoint=.dataEntry，operator=会话身份）。
// 表单态留在壳层 @State：CoreKit 公开可变字段不触发 objectWillChange（TextField
// 自持编辑态可以，Picker 选择回显需要重渲染），请求组装与 create/update 路由
// 仍全走 DataEntryViewModel（红先行测试在册）。

struct DataEntryView: View {
    let session: AppSession

    @StateObject private var vm = ReceiptListViewModel(provider: { query in
        try await APIGlue.list(query)
    })
    @State private var keyword = ""
    @State private var entryTarget: SampleReceipt?
    @State private var actTarget: ActTargetItem?
    @State private var errorMessage: String?

    var body: some View {
        listView
            .sheet(item: $entryTarget) { receipt in
                EntrySheet(receipt: receipt) { message in
                    entryTarget = nil
                    if let message {
                        errorMessage = message
                    }
                }
            }
            .sheet(item: $actTarget) { target in
                ActConfirmSheet(
                    action: target.action, ids: [target.targetID],
                    operatorName: session.store.user?.username ?? "",
                    endpoint: .dataEntry
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
            // 队列查询钉死数据录入环节（I01）；page 1/pageSize 50 镜像家族。
            vm.query.flowStatus = .dataEntry
            vm.query.pageSize = 50
            await vm.load()
        }
        .navigationTitle("数据录入")
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
            if let projectName = receipt.projectName, !projectName.isEmpty {
                Text(projectName).font(.subheadline).foregroundStyle(.secondary)
            }
            rowActions(receipt)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowActions(_ receipt: SampleReceipt) -> some View {
        HStack(spacing: 14) {
            // I01：录入结果（sheet 样品/参数 Picker + 表单）
            Button {
                entryTarget = receipt
            } label: {
                Label("录入结果", systemImage: "square.and.pencil")
                    .font(.footnote)
            }
            Spacer()
            // I12：act 三动作菜单
            Menu {
                Button("提交") {
                    actTarget = ActTargetItem(action: .submit, targetID: receipt.id)
                }
                Button("退回任务分配") {
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
}

// MARK: I01/I02/I03 录入对话框（样品/参数 Picker + 表单，家族同款 sheet）

private struct EntrySheet: View {
    let receipt: SampleReceipt
    let onDone: (_ message: String?) -> Void

    @StateObject private var vm: DataEntryViewModel
    @State private var selectedSampleId = ""
    @State private var selectedParameterCode = ""
    @State private var result = ""
    @State private var requirement = ""
    @State private var standardCode = ""
    /// 判定：空串 = 未判定（存 VM 时归一为 nil）。
    @State private var verdict = ""
    @Environment(\.dismiss) private var dismiss

    init(receipt: SampleReceipt, onDone: @escaping (String?) -> Void) {
        self.receipt = receipt
        self.onDone = onDone
        _vm = StateObject(wrappedValue: DataEntryViewModel(
            catalogLoad: { receiptId in
                async let samples = APIGlue.receiptSamples(receiptId)
                async let parameters = APIGlue.parameters()
                return (try await samples, try await parameters)
            },
            recordsLoad: { try await APIGlue.testRecords($0) },
            persist: { id, create, update in
                try await APIGlue.persistTestRecord(id, create, update)
            }
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("接样单") {
                    LabeledContent("委托编号", value: receipt.commissionCode)
                }
                Section("样品与参数") {
                    Picker("样品", selection: $selectedSampleId) {
                        Text("请选择").tag("")
                        ForEach(vm.samples, id: \.id) { sample in
                            Text(sample.sampleCode).tag(sample.id)
                        }
                    }
                    .onChange(of: selectedSampleId) { syncPrefill() }
                    Picker("检测参数", selection: $selectedParameterCode) {
                        Text("请选择").tag("")
                        ForEach(vm.parameters, id: \.code) { parameter in
                            Text(parameter.name).tag(parameter.code)
                        }
                    }
                    .onChange(of: selectedParameterCode) { syncPrefill() }
                }
                Section("检测结果") {
                    TextField("检测结果", text: $result)
                    TextField("技术要求（如 ≥42.5）", text: $requirement)
                    TextField("标准代号（可选）", text: $standardCode)
                    Picker("判定", selection: $verdict) {
                        Text("未判定").tag("")
                        Text("合格").tag("合格")
                        Text("不合格").tag("不合格")
                    }
                }
                if vm.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                if let message = vm.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            .task { await vm.load(receiptId: receipt.id) }
            .navigationTitle("录入检测结果")
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

    /// 选择样品/参数后回填既有记录（AC-3：同键已有记录呈现已录值，改判在此改）。
    private func syncPrefill() {
        vm.selectedSampleId = selectedSampleId
        vm.selectedParameterCode = selectedParameterCode
        vm.fillFromExisting()
        result = vm.result
        requirement = vm.requirement
        standardCode = vm.standardCode
        verdict = vm.verdict ?? ""
    }

    private func save() async {
        // 表单态推进 VM：请求组装/校验/create-vs-update 路由全在 CoreKit。
        vm.selectedSampleId = selectedSampleId
        vm.selectedParameterCode = selectedParameterCode
        vm.result = result
        vm.requirement = requirement
        vm.standardCode = standardCode
        vm.verdict = verdict.isEmpty ? nil : verdict
        let saved = await vm.save()
        onDone(saved == nil ? (vm.errorMessage ?? "保存失败") : nil)
    }
}

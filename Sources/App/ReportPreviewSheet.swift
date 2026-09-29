import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-007 T-2：数据面报告预览 sheet（M03.F09.I03）。
// 用户裁定 Q1：纯 SwiftUI 数据摘要（按样品分组的检测记录 + 判定 + 报告编号），
// 家族 docx 模板填充/打印/套打为 Web 专属，非范围。VM 装载走 CoreKit
// ReportPreviewViewModel，网络缝注 APIGlue（页大小 200 镜像家族）。
// REQ-2026-008 T-2：装载路径装 ext 补录门（M03.F01.I07）——预览装好后按
// categoryCode 判 extFields 缺 key，缺则先出 SampleExtFormView（家族
// ReportPreviewModal 同款门槛），保存成功重载预览。

struct ReportPreviewSheet: View {
    let receiptID: String
    let categoryCode: String

    @StateObject private var vm: ReportPreviewViewModel
    @StateObject private var extVM: SampleExtViewModel
    @Environment(\.dismiss) private var dismiss

    init(receiptID: String, categoryCode: String) {
        self.receiptID = receiptID
        self.categoryCode = categoryCode
        _vm = StateObject(wrappedValue: ReportPreviewViewModel(
            samplesLoad: { try await APIGlue.receiptSamples($0) },
            recordsLoad: { try await APIGlue.testRecords($0) }
        ))
        _extVM = StateObject(wrappedValue: SampleExtViewModel(
            reportNamesLoad: { try await APIGlue.reportNames($0) },
            persist: { try await APIGlue.updateSampleExt($0, $1) }
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("生成预览中")
                } else if let message = vm.errorMessage {
                    ContentUnavailableView(
                        "预览失败", systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                } else if vm.samples.isEmpty {
                    ContentUnavailableView(
                        "暂无样品", systemImage: "doc.text",
                        description: Text("该接样单还没有样品与检测记录")
                    )
                } else if extVM.needsForm && !extVM.didSave {
                    // 补录门（AC-1）：缺 key 先补录，不渲染预览列表。
                    SampleExtFormView(
                        vm: extVM,
                        sampleID: vm.samples[0].id
                    ) {
                        // AC-3：合并落库成功 → 重载预览（样品 ext 已更新）。
                        await vm.load(receiptId: receiptID)
                    }
                } else {
                    previewList
                }
            }
            .navigationTitle("报告预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await vm.load(receiptId: receiptID)
                guard vm.errorMessage == nil else { return }
                // 门判定在预览装载后（家族 needExt 用装载好的 firstSample）。
                await extVM.load(
                    categoryCode: categoryCode,
                    firstSample: vm.samples.first
                )
            }
        }
    }

    private var previewList: some View {
        List {
            ForEach(vm.samples, id: \.id) { sample in
                Section("样品 \(sample.sampleCode)") {
                    if let records = vm.recordsBySample[sample.id], !records.isEmpty {
                        ForEach(records, id: \.id) { record in
                            recordRow(record)
                        }
                    } else {
                        Text("该样品暂无检测记录").foregroundStyle(.secondary).font(.footnote)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recordRow(_ record: TestRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.parameterCode).font(.headline)
                Spacer()
                // 判定缺席不兜业务值，显示 —（ADR-0019 同源：呈现层占位非身份兜底）。
                Text(record.verdict ?? "—").font(.caption).foregroundStyle(.secondary)
            }
            Text("结果 \(record.result) · 要求 \(record.requirement)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

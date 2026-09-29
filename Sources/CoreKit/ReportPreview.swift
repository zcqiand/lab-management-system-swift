import Foundation
import Combine
import LabSharedGenerated

// REQ-2026-007 T-1：报告预览数据面 VM（M03.F09.I03）。
// 契约 list 端点只支持 sampleId 过滤（无 receiptId），按样品逐个取再归集——
// 家族 ReportPreviewModal.recordsOfSamples 同款策略。数据面预览 = 用户裁定
// （Q1 2026-09-29）：纯数据摘要，docx 模板填充/打印/套打为家族 Web 专属，非范围。
// 网络缝 = 注入 async 闭包（samplesLoad / recordsLoad），单测不发真网络。

/// 报告预览 VM：按样品归集检测记录。
public final class ReportPreviewViewModel: ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()
    private func notify() { objectWillChange.send() }

    public private(set) var samples: [Sample] = []
    /// 键 = sampleId（值按 updatedAt 或创建序，透传生成层返回序）。
    public private(set) var recordsBySample: [String: [TestRecord]] = [:]
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let samplesLoad: (String) async throws -> [Sample]
    private let recordsLoad: (String) async throws -> [TestRecord]

    public init(
        samplesLoad: @escaping (String) async throws -> [Sample],
        recordsLoad: @escaping (String) async throws -> [TestRecord]
    ) {
        self.samplesLoad = samplesLoad
        self.recordsLoad = recordsLoad
    }

    /// 装载：样品单次取，记录按样品逐个取（任何失败清空整体，不留半写状态）。
    public func load(receiptId: String) async {
        notify()
        isLoading = true
        errorMessage = nil
        defer {
            notify()
            isLoading = false
        }
        do {
            let fetchedSamples = try await samplesLoad(receiptId)
            notify()
            var grouped: [String: [TestRecord]] = [:]
            for sample in fetchedSamples {
                grouped[sample.id] = try await recordsLoad(sample.id)
            }
            notify()
            samples = fetchedSamples
            recordsBySample = grouped
        } catch {
            notify()
            errorMessage = String(describing: error)
            samples = []
            recordsBySample = [:]
        }
    }
}

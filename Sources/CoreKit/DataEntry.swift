import Combine
import Foundation
import LabSharedGenerated

// REQ-2026-005 T-1：数据录入 CoreKit（M03.F03.I01/I02/I03）。
// 队列（I01 列表半边）复用 ReceiptListViewModel（query.flowStatus = .dataEntry
// 预设）；act（I12）复用 ReceivingFlowViewModel（operator = 会话身份）。
// 本文件只有一件新事：录入 sheet 的目录装载 + create-vs-update 请求组装。
// 键控与家族同款：sampleId#parameterCode（vue DataEntryPage 实证）。

/// 录入表单错误：样品/参数未选或必填字段缺失 fail-fast，不打端点（§1 禁兜底同源）。
public enum DataEntryError: Error, Equatable {
    case invalidFields
}

/// 录入 VM：装载样品/参数/既有记录目录，按同键记录有无路由 create/update。
/// verdict 随请求体一并提交（REQ-2026-005 Q3 裁定，家族两仓实证；
/// 生成物专用 testRecordsSetVerdict 端点本仓不用）。
/// 失败以 errorMessage 呈现，不清用户输入（AC-6）。
/// ObservableObject（Combine）供 SwiftUI @StateObject 订阅，
/// 变更点显式 objectWillChange.send()，与 ReceiptListViewModel 同款。
public final class DataEntryViewModel: ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()
    private func notify() { objectWillChange.send() }

    public private(set) var samples: [Sample] = []
    public private(set) var parameters: [InspectionParameter] = []
    /// 键 = "sampleId#parameterCode"，值 = 该样品检测记录（逐样品装载）。
    public private(set) var recordsBySample: [String: [TestRecord]] = [:]
    public private(set) var isLoading = false {
        willSet { notify() }
    }
    public private(set) var errorMessage: String? {
        willSet { notify() }
    }
    public private(set) var isSaving = false {
        willSet { notify() }
    }

    // 录入表单：样品/参数来自 Picker，其余手填；verdict 可空（随 body，Q3）。
    public var selectedSampleId = ""
    public var selectedParameterCode = ""
    public var result = ""
    public var requirement = ""
    public var standardCode = ""
    public var verdict: String?

    /// 网络缝：目录装载（receiptId → 样品 + 参数字典）；真实现由 UI 壳用
    /// async let 并发取生成层两接口。
    private let catalogLoad: (String) async throws -> ([Sample], [InspectionParameter])
    /// 网络缝：逐样品检测记录（家族同款一页 200）。
    private let recordsLoad: (String) async throws -> [TestRecord]
    /// 网络缝：id=nil → create；id+update → update。二选一，由 save 保证。
    private let persist: (
        _ id: String?, _ create: CreateTestRecordRequest?, _ update: UpdateTestRecordRequest?
    ) async throws -> TestRecord

    public init(
        catalogLoad: @escaping (String) async throws -> ([Sample], [InspectionParameter]),
        recordsLoad: @escaping (String) async throws -> [TestRecord],
        persist: @escaping (
            _ id: String?, _ create: CreateTestRecordRequest?, _ update: UpdateTestRecordRequest?
        ) async throws -> TestRecord
    ) {
        self.catalogLoad = catalogLoad
        self.recordsLoad = recordsLoad
        self.persist = persist
    }

    /// 家族同款记录键：`sampleId#parameterCode`（vue DataEntryPage 实证）。
    public static func recordKey(sampleId: String, parameterCode: String) -> String {
        "\(sampleId)#\(parameterCode)"
    }

    /// 当前选中样品+参数下的既有记录（有 = update 路，无 = create 路）。
    public var existingRecord: TestRecord? {
        recordsBySample[selectedSampleId]?.first { $0.parameterCode == selectedParameterCode }
    }

    /// 装载目录：样品+参数并发，随后逐样品拉记录建键控索引。
    /// 任一缝失败 = 整体失败（目录不全的录入页是半残态，宁可整页报错重进）。
    public func load(receiptId: String) async {
        notify()
        isLoading = true
        errorMessage = nil
        defer {
            notify()
            isLoading = false
        }
        do {
            let (fetchedSamples, fetchedParameters) = try await catalogLoad(receiptId)
            var records: [String: [TestRecord]] = [:]
            for sample in fetchedSamples {
                records[sample.id] = try await recordsLoad(sample.id)
            }
            notify()
            samples = fetchedSamples
            parameters = fetchedParameters
            recordsBySample = records
        } catch {
            notify()
            errorMessage = String(describing: error)
            samples = []
            parameters = []
            recordsBySample = [:]
        }
    }

    /// 既有记录回填表单（AC-3：打开 sheet 即呈现已录值）。
    public func fillFromExisting() {
        guard let record = existingRecord else { return }
        result = record.result
        requirement = record.requirement
        standardCode = record.standardCode ?? ""
        verdict = record.verdict
    }

    private func trimmedResult() -> String { result.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 组装创建请求：样品/参数/result/requirement 必填（trim 后），
    /// standardCode 空串归一为不传；verdict 原样随 body（Q3）。
    public func makeCreateRequest() throws -> CreateTestRecordRequest {
        let sampleId = selectedSampleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let parameterCode = selectedParameterCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultValue = trimmedResult()
        let requirementValue = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sampleId.isEmpty, !parameterCode.isEmpty,
              !resultValue.isEmpty, !requirementValue.isEmpty else {
            throw DataEntryError.invalidFields
        }
        let standardCodeValue = standardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return CreateTestRecordRequest(
            sampleId: sampleId, parameterCode: parameterCode,
            standardCode: standardCodeValue.isEmpty ? nil : standardCodeValue,
            requirementCode: nil, requirement: requirementValue,
            result: resultValue, verdict: verdict
        )
    }

    /// 组装更新请求：键（样品/参数）不变，表单值全量随 body（家族同款整提交）。
    public func makeUpdateRequest() throws -> UpdateTestRecordRequest {
        _ = try makeCreateRequest() // 同一套必填校验
        let standardCodeValue = standardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateTestRecordRequest(
            sampleId: selectedSampleId, parameterCode: selectedParameterCode,
            standardCode: standardCodeValue.isEmpty ? nil : standardCodeValue,
            requirementCode: nil,
            requirement: requirement.trimmingCharacters(in: .whitespacesAndNewlines),
            result: trimmedResult(), verdict: verdict
        )
    }

    /// 保存：同键有记录走 update(record.id)，无记录走 create；
    /// 校验不过或端点失败都返回 nil 并落 errorMessage（不打断 UI，AC-5/AC-6）。
    @discardableResult
    public func save() async -> TestRecord? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let existing = existingRecord
        do {
            if let existing {
                return try await persist(existing.id, nil, try makeUpdateRequest())
            }
            return try await persist(nil, try makeCreateRequest(), nil)
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }
}

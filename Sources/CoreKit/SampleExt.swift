import Combine
import Foundation
import LabSharedGenerated

// REQ-2026-008 T-1：样品 ext 补录 VM（M03.F01.I07，纯 Swift 禁 UI 框架）。
// 语义镜像家族 SampleExtFieldsModal + ReportPreviewModal.handleExtSubmit：
// 预览前门槛——类别 extFields 非空且首样品缺 key 时先补录；提交 = 合并 ext
// （现有 key 全保留 + 表单非空值覆盖）→ PUT /api/samples/{id}/ext。
// source=receipt 的字段家族亦未接入（只写 sample.ext），同款过滤为非范围。

public final class SampleExtViewModel: ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()
    private func notify() { objectWillChange.send() }

    /// 表单渲染用的全部可用定义（已滤掉 source=receipt）。
    public private(set) var allFields: [ExtFieldDef] = []
    /// 缺 key 子集——补录门判定依据（家族 needExt 的 some(f => !ext[f.key]) 同义）。
    public private(set) var formFields: [ExtFieldDef] = []
    public private(set) var needsForm = false
    public private(set) var draft: [String: String] = [:]
    public private(set) var validationErrors: [String: String] = [:]
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var didSave = false

    /// 合并基准：load 时的样品 ext 现状（save 时现有 key 全保留）。
    private var originalExt: [String: String] = [:]

    /// 网络缝：reportNamesLoad(pageSize) 拉类别定义；persist(id, mergedExt) 落库。
    private let reportNamesLoad: (Int) async throws -> [InspectionReportName]
    private let persist: (String, [String: String]) async throws -> Void

    public init(
        reportNamesLoad: @escaping (Int) async throws -> [InspectionReportName],
        persist: @escaping (String, [String: String]) async throws -> Void
    ) {
        self.reportNamesLoad = reportNamesLoad
        self.persist = persist
    }

    /// 装载类别定义并做出门判定。firstSample=nil（无样品）不开门（家族同款）。
    public func load(categoryCode: String, firstSample: Sample?) async {
        notify()
        do {
            let names = try await reportNamesLoad(200)
            notify()
            let defs = names.first { $0.code == categoryCode }?.extFields ?? []
            let usable = defs.filter { $0.source != .receipt }
            originalExt = firstSample?.ext ?? [:]
            allFields = usable
            // 草稿预填：现有值进表单可改，缺失键空串（家族 initialExt 同步语义）。
            draft = Dictionary(
                uniqueKeysWithValues: usable.map { ($0.key, originalExt[$0.key] ?? "") }
            )
            formFields = usable.filter { (originalExt[$0.key] ?? "").isEmpty }
            needsForm = firstSample != nil && !formFields.isEmpty
            validationErrors = [:]
            errorMessage = nil
        } catch {
            notify()
            errorMessage = String(describing: error)
            allFields = []
            formFields = []
            draft = [:]
            needsForm = false
        }
        notify()
    }

    public func setValue(_ value: String, forKey key: String) {
        draft[key] = value
        notify()
    }

    /// 必填校验：trim 后非空才算有值；错项 keyed 进 validationErrors（UI 逐项标错）。
    @discardableResult
    public func validate() -> Bool {
        var errors: [String: String] = [:]
        for def in allFields where def.required == true {
            let value = draft[def.key] ?? ""
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                errors[def.key] = "必填"
            }
        }
        validationErrors = errors
        notify()
        return errors.isEmpty
    }

    /// 提交：合并（现有 key 全保留 + 表单非空值覆盖）→ persist 缝。
    /// 校验不过不打端点；失败呈现 errorMessage 且草稿保留（AC-5）。
    @discardableResult
    public func save(sampleID: String) async -> Bool {
        guard validate() else { return false }
        notify()
        isSaving = true
        errorMessage = nil
        defer {
            notify()
            isSaving = false
        }
        var merged = originalExt
        for (key, value) in draft {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { merged[key] = trimmed }
        }
        do {
            try await persist(sampleID, merged)
            notify()
            didSave = true
            return true
        } catch {
            notify()
            errorMessage = String(describing: error)
            return false
        }
    }
}

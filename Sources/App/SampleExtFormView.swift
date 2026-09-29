import CoreKit
import LabSharedGenerated
import SwiftUI

// REQ-2026-008 T-2：类别参数补录表单（M03.F01.I07）。
// 家族 SampleExtFieldsModal 同款：四型控件（text/number/date → TextField，
// select → Picker(options)）+ 必填逐项标错。草稿留壳层 @State（表单态必留壳），
// 保存前逐键 setValue 回 VM，校验/合并/落库语义全在 CoreKit SampleExtViewModel。

struct SampleExtFormView: View {
    @ObservedObject private var vm: SampleExtViewModel
    private let sampleID: String
    private let onSaved: () async -> Void

    @State private var draft: [String: String] = [:]
    @State private var isSaving = false

    init(vm: SampleExtViewModel, sampleID: String, onSaved: @escaping () async -> Void) {
        self.vm = vm
        self.sampleID = sampleID
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("类别参数补录") {
                ForEach(vm.allFields, id: \.key) { def in
                    fieldRow(def)
                }
            }
            if let message = vm.errorMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存并继续预览").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear { draft = vm.draft }
    }

    @ViewBuilder
    private func fieldRow(_ def: ExtFieldDef) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if def.type == .select {
                Picker(rowLabel(def), selection: binding(def.key)) {
                    Text("请选择").tag("")
                    ForEach(def.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            } else {
                TextField(rowLabel(def), text: binding(def.key))
                    .keyboardType(def.type == .number ? .decimalPad : .default)
            }
            if let error = vm.validationErrors[def.key] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func rowLabel(_ def: ExtFieldDef) -> String {
        def.required == true ? "\(def.label)（必填）" : def.label
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0 })
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        for (key, value) in draft {
            vm.setValue(value, forKey: key)
        }
        guard await vm.save(sampleID: sampleID) else { return }
        await onSaved()
    }
}

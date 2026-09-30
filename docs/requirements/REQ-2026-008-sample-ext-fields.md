# REQ-2026-008 样品扩展属性补录（M03.F01.I07）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-29 |
| 优先级 | P2 |
| 状态 | **已上线**（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） |
| 关联 ADR | ADR-0019（缺失不兜底，沿用） |
| 上游 | REQ-2026-001 Q3 延后项；REQ-2026-007（预览 sheet 是本需求触发位） |

## 1. 需求描述

**背景**：

- 家族 react SampleExtFieldsModal（M03.F01.I07）已上线：预览前门槛——当前
  接样单 categoryCode 对应的 InspectionReportName.extFields 非空且首个样品
  未覆盖对应 key 时，先弹「类别参数补录」表单；提交 = 合并 ext →
  `PUT /api/samples/{id}/ext` → 用合并后的样品继续渲染预览。
- REQ-2026-007 已交付 iOS 数据面预览 sheet，本需求把补录门装到同一装载路径。
- **契约零改动**：生成物 UpdateSampleExtRequest(ext:)、
  SamplesAPI.samplesUpdateSampleExt、ExtFieldDef{key,label,type,required,
  options,tag,source}、InspectionReportName.extFields、
  ReportNamesAPI.reportNamesListReportNames 全在。
- extFields 定义取 **live 契约端点** GET /api/report-names（家族 react 用
  静态种子 JSON 属 Web 构建资产非契约面，iOS 不镜像该资产）。

**范围**（单子项 I07，REQ-2026-001 已登记行，本次规划→开发中）：

| 关注点 | 内容 |
|---|---|
| 触发位 | ReportPreviewSheet 装载路径（家族同款预览前门槛） |
| 需补录判定 | extFields 非空 ∧ 首样品存在 ∧ 存在 key 缺失（`source == receipt` 的字段除外——家族亦未接入 receipt 侧预留，声明非范围） |
| 表单 | 每行 label + 控件：text → TextField；number → TextField(.decimalPad)；date → TextField（ISO 日期串，与 ext 值形态一致）；select → Picker(options)。必填未填阻断提交并逐项标错 |
| 提交 | 合并 = 现有 ext 全保留 + 表单新值覆盖 → UpdateSampleExtRequest → PUT /api/samples/{id}/ext；成功后继续预览装载 |
| CoreKit | SampleExtViewModel：reportNamesLoad / persist 缝注入；需补录判定与合并为纯函数可测（新符号 → 真红可行） |

**非范围**：source == "receipt" 的 ext 字段（家族同款未接入）；docx 模板
占位符 tag 呈现（Web 预览专属语义）；样品列表逐个补录（家族亦只处理首样品）。

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | 类别 extFields 非空且首样品缺 key | 打开报告预览 | 装载停在补录表单（不渲染预览列表）；表单预填样品现有 ext 值 |
| AC-2 | 表单含必填项 | 必填留空点保存 | 提交阻断 + 逐项标错，不打端点（fail-fast 同源） |
| AC-3 | 表单填写齐 | 点保存 | 合并（现有 key 全保留 + 新值覆盖）→ PUT /api/samples/{id}/ext → 成功后预览继续装载 |
| AC-4 | 类别无 extFields 或 key 已全覆盖 | 打开报告预览 | 不出补录门，直接预览（既有行为保持） |
| AC-5 | 提交失败（网络/后端错） | 点保存 | 错误呈现不崩，表单字段保留可重交 |

## 3. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：I07 行规划→开发中（REQ-2026-001 已登记行的状态翻转）；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit 红先行：SampleExtViewModel（needsForm 判定 / merge 纯函数 / validate 必填 / persist 缝）；ReportPreviewViewModel 不动 | 完成（2026-09-29，真红 `cannot find 'SampleExtViewModel' in scope` ×7 → 绿 7/7） |
| T-2 | App：ReportPreviewSheet 装载路径装补录门（extFields 拉取 + 判定 + 表单态）；表单控件四型渲染 | 完成（2026-09-29，APIGlue 两缝 + SampleExtFormView + 补录门） |
| T-3 | trace_cmd 挂 I07 + 设计映射行 + 全门绿 + push + gitlink | 完成（2026-09-29，trace 63 测试 / 34 ID） |

## 4. 功能影响

| 功能 ID | 影响类型 | 说明 |
|---|---|---|
| M03.F01.I07 | 变更 | 既有行（REQ-2026-001 Q3 延后）规划→开发中，落地实现；接口/表不变 |

## 5. 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 extFields 定义源：家族静态种子 JSON vs live 端点 | **live 端点 GET /api/report-names**（种子 JSON 是 Web 构建资产非契约面；live 端点在 shared .tsp 契约内，§4 API 面只认生成物） | 自裁（契约事实非语义分歧，family 端点也在） | 2026-09-29 |

## 6. 附注

- 存档：`.state/tree-change.json`（approved=false 待批，base_sha 567db71c69580313，以 --report 输出为准）
- 上游 REQ-2026-001 Q3 延后项 + REQ-2026-007（触发位=预览 sheet）；关联 ADR-0019 沿用
- 家族参照：`output/lab-management-system-react/src/features/data-entry/SampleExtFieldsModal.tsx`
  + `ReportPreviewModal.tsx` handleExtSubmit（合并 → PUT → 重渲染）

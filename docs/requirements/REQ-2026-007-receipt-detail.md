# REQ-2026-007 接样单详情（M03.F09）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-29 |
| 优先级 | P1 |
| 状态 | **已上线**（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） |
| 关联 ADR | ADR-0019（operator=真会话身份，沿用） |
| 上游 | REQ-2026-006（报告四阶段）——详情页是流程线任一环节可查看的横切面 |

## 1. 需求描述

**背景**：

- 家族 react ReceiptDetail 已上线：详情全字段表 + 时间线 + 报告预览按钮。
  Swift 既有 ReceiptDetailView（REQ-2026-002，M03.F01.I06）只有 7 字段接样
  信息 + 时间线 + receiving 提交按钮——I01 差距 = 字段全量化。
- **契约零改动**：生成物 SampleReceipt 全字段在；样品与记录端点缝已在
  （APIGlue.receiptSamples / testRecords）。
- **I03 预览形态**：家族 react 是 docx 模板填充 + 浏览器打印/套打（Web 专属
  技术栈 + 30 个 docx 模板资产，iOS 无对应物）。用户裁定 Swift 侧 =
  **数据面预览**：按样品归集检测记录，纯 SwiftUI 渲染报告式摘要。docx 链路
  非范围。

**范围**（三子项，编号镜像家族 data-fn 实证）：

| ID | 内容 | 实现路径 |
|---|---|---|
| I01 | 详情页接样信息全字段表 | 扩展 ReceiptDetailView 接样信息 Section（家族 20+ 字段面） |
| I02 | 流程历史时间线（at 倒序） | 既有实现（F01.I06）同一代码双挂 ID，零新代码 |
| I03 | 报告预览（数据面摘要） | ReportPreviewViewModel（CoreKit）+ 预览 sheet（App）；复用 APIGlue 缝 |

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | 详情页数据齐 | 点「报告预览」 | 预览 sheet 呈现按样品归集的检测记录摘要（样品/参数/结果/判定）+ reportCode 呈现 |
| AC-2 | 详情页数据齐 | 观察接样信息表 | 家族同款全字段面，缺席字段显示 — |
| AC-3 | 时间线已有记录 | 观察流程历史 | 按 at 倒序呈现（既有 F01.I06 实现，双挂 I02） |
| AC-4 | 无样品/无记录 | 点报告预览 | 空态呈现不崩；拉取失败呈现错误不崩 |
| AC-5 | act 成功返回详情 | 观察刷新 | 详情（含 reportCode）重取刷新（既有行为保持） |

## 3. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：F09 三子项登记 → 人批 → F09 规划→开发中；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit 红先行：ReportPreviewViewModel（按样品归集 records）+ 详情时间线 at 倒序（I02 新增排序）| 完成（真红实证：staging 无实现报 cannot find 'ReportPreviewViewModel' ×3；绿跑 69/69） |
| T-2 | App：ReceiptDetailView 全字段化 + 预览按钮 + ReportPreviewSheet（按样品分组摘要列表） | 完成（iOS build 门绿） |
| T-3 | trace_cmd 挂 ID（I01/I02/I03）+ 设计映射 + 全门绿 + push | 完成（trace 56 测试 / 33 ID，F09 3 ID 落账） |

## 4. 功能影响

| 功能 ID | 影响类型 | 说明 |
|---|---|---|
| M03.F09.I01 | 新增 | 详情页全字段表（tree-change 批准登记） |
| M03.F09.I02 | 新增 | 既有时间线双挂（零新代码） |
| M03.F09.I03 | 新增 | 按样品归集预览（数据面形态，Q1 裁定） |

## 5. 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 I03 预览 iOS 形态（docx 全家桶 vs 数据面摘要 vs 不做） | **数据面预览**（纯 SwiftUI 数据摘要；docx 填充/打印/套打 Web 专属非范围） | zcqiand | 2026-09-29 |

## 6. 附注

- 存档：`.state/tree-change.json`（approved=true，base_sha 5c2fcfcad866d4f9）
- 上游 REQ-2026-006；关联 ADR-0019 沿用

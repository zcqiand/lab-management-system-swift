# REQ-2026-006 报告四阶段（M03.F05~F08 流程后四环节）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-29 |
| 优先级 | P1 |
| 状态 | **已上线**（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） |
| 关联 ADR | ADR-0019（operator=真会话身份，REQ-2026-004 已落地，沿用） |
| 上游 | REQ-2026-005（数据录入，流程第三环节）——四阶段与接样→分配→录入是同一流程线，不拆分 |

## 1. 需求描述

**用户原话**（2026-09-29，范围裁定）：

> 先做 M03.F05-F08 报告四阶段，按理说报告四阶段与接样 → 任务分配 → 数据录入流程是一体的，不应该分开

**背景**：

- 家族 vue/react 四阶段全部已上线，且共享一个 ReportPhasePage（参数 stage +
  submitLabel），4 个 page wrapper 各传一组——Swift 同构镜像：一个
  ReportPhaseView + 4 个入口。
- **契约零改动**：生成物四阶段 act 端点全在——
  `receiptsActFlowReview / Approve / Issuance / Archived(flowActionRequest:)`；
  `receiptsListReceipts(flowStatus:)` 覆盖 review/approval/issuance/archived
  四态；`SampleReceipt.reportCode/reportDate` 已在模型。本仓纯消费。
- 「发放（生成报告编号）」：报告编号由后端 act submit 语义生成（家族
  ReportPhasePage 注释实证「后端 act 语义已含，此处只显示」），Swift 侧
  只需在行上呈现 reportCode，不发专用请求。

**范围**（每阶段三件，镜像家族已上线面；各阶段废弃号 I03/I06~I09 不复用）：

| 阶段 | 队列页 | 操作按钮 | act 行 |
|---|---|---|---|
| F05 审核 review | I01 审核队列 | I02 审核通过/驳回 | I07 act 三动作（I08/I09 废弃并入） |
| F06 批准 approval | I01 批准队列 | I02 批准/驳回 | I05 act 三动作（I06/I07 废弃并入） |
| F07 发放 issuance | I01 发放队列 | I02 发放（生成报告编号） | I05 act 三动作（I06/I07 废弃并入） |
| F08 归档 archived | I01 归档队列 | I02 归档完成 | I05 act 三动作（I06/I07 废弃并入） |

- 队列 = `ReceiptListViewModel` 复用（query.flowStatus 钉各阶段，page 1 /
  pageSize 50 + keyword）；行呈 reportCode（F07 起后端已生成时）。
- 操作 = 选中行「{submitLabel}」与「退回」→ `ReceivingFlowViewModel` 复用
  （operator=会话身份），端点按阶段档位走 ActConfirmSheet 新增四档。
- **非范围**：各阶段 I04 三态过滤器（家族规划态）；F09 接样单详情（独立需求）；
  M01.F05.I03 SSO（此前已裁后续）。

### 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 四阶段与前三环节的关系：拆独立需求 vs 一体？ | **一体一个 REQ**（用户裁定：四阶段与接样→分配→录入是同一流程线，不应该分开）。 | zcqiand | 2026-09-29 |
| Q2 发放（生成报告编号）怎么落：专用端点 vs act 语义内含？ | **act 语义内含**（家族 ReportPhasePage 实证「后端 act 语义已含，此处只显示」；生成物无专用报告编号端点）；Swift 行上呈现 reportCode。 | zcqiand（家族实证裁定） | 2026-09-29 |

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | 已登录，存在各阶段态接样单 | 进四阶段任一队列页 | 各页只显示本阶段 flowStatus 单子；keyword 过滤生效 |
| AC-2 | 队列勾选单子 | 点「{submitLabel}」（审核通过/批准/发放/归档完成） | 走本阶段 act 端点 action=submit；operator=会话用户名；成功后离队刷新 |
| AC-3 | 队列勾选单子 | 点「退回」 | 走本阶段 act 端点 action=return；批次回退一阶 |
| AC-4 | F07 发放 submit 成功 | 观察行 | reportCode 呈现（后端生成，UI 只显示） |
| AC-5 | act 失败（网络或后端拒） | 观察列表 | 列表原状，错误信息呈现，无半写状态 |
| AC-6 | 同一套页面代码 | 检查实现 | ReportPhaseView 单组件参数化（stage+submitLabel），4 入口复用，不复制四份 |

## 3. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：四阶段 12 子项登记（镜像家族已上线编号，废弃号不复用）→ 人批 → F05~F08 规划→开发中；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit 红先行：四阶段队列钉态测试（ReceiptListViewModel query 预设 ×4）+ 四阶段 act 请求组装测试（ReceivingFlowViewModel makeRequest ×4，operator=会话身份断言） | 完成（2026-09-29 红确认 `cannot find 'ReportPhase' in scope`，staging 为实现落盘前快照） |
| T-2 | App：ReportPhaseView 单组件（队列 + 选中行 submit/return + reportCode 呈现）+ 4 个入口（ReceiptListView 报告菜单/链接）+ ActConfirmSheet 四档位（review/approve/issuance/archived）+ APIGlue 四 act 缝 | 完成（2026-09-29 远端 test 64/64 绿 + build 绿；首版 navigationDestination(item:) 缺 Hashable 被门禁拦下，补 conform 后绿） |
| T-3 | trace_cmd 挂 ID（12 子项）+ 功能树/设计映射开发中 + 全门绿 + push | 完成（trace 51 测试/30 ID，F05~F08 12/12 挂钩；设计映射 12 行；全门与 push 见 gitlog） |

## 4. 功能影响

| 功能 ID | 影响类型 | 说明 |
|---|---|---|
| M03.F05.I01 | 变更 | 审核队列（tree-change 批准后登记） |
| M03.F05.I02 | 变更 | 审核通过/驳回按钮（同上） |
| M03.F05.I07 | 变更 | 报告审核 act 三动作（同上；I08/I09 家族已废弃语义并入） |
| M03.F06.I01 | 变更 | 批准队列（同上） |
| M03.F06.I02 | 变更 | 批准/驳回按钮（同上） |
| M03.F06.I05 | 变更 | 报告批准 act 三动作（同上；I06/I07 废弃语义并入） |
| M03.F07.I01 | 变更 | 发放队列（同上） |
| M03.F07.I02 | 变更 | 发放（生成报告编号）按钮（同上；编号后端 act 语义生成，UI 显示 reportCode） |
| M03.F07.I05 | 变更 | 报告发放 act 三动作（同上；I06/I07 废弃语义并入） |
| M03.F08.I01 | 变更 | 归档队列（同上） |
| M03.F08.I02 | 变更 | 归档完成按钮（同上） |
| M03.F08.I05 | 变更 | 报告归档 act 三动作（同上；I06/I07 废弃语义并入） |

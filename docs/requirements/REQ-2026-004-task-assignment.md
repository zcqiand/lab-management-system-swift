# REQ-2026-004 任务分配（M03.F02 流程第二环节）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-28 |
| 优先级 | P1 |
| 状态 | **已评审**（三项澄清已裁，2026-09-28；待开工） |
| 关联 ADR | ADR-0019（operator 临时解本期退役，见 Q3） |
| 上游 | REQ-2026-001（接样管理，流程第一环节）；REQ-2026-003（登录落地，真会话身份前置） |

## 1. 需求描述

**用户原话**（2026-09-28，三项裁决）：

> 范围 = 跟家族已上线三件；分配形态 = 手填姓名+日期；act 操作人 = 真会话身份（接样 act 同批改造）

**背景**：

- 家族 vue/react 已上线 M03.F02 三件：分配队列、安排/取消检测人员与计划日期、
  act 三动作（提交/退回/撤回）。Swift 仓停在接样环节，流程线断在第二环节。
- **契约零改动**：shared 生成物已含全部四件 API 面（§4 只认生成物）——
  `receiptsListReceipts(flowStatus:keyword:page:pageSize:)`、
  `receiptsAssignTask(id:assignTaskRequest:)`（AssignTaskRequest），
  `receiptsActFlowAssigning(flowActionRequest:)`（FlowActionRequest），
  `SampleReceipt.assigneeId/assigneeName/plannedTestDate`。本仓纯消费。
- REQ-2026-002 的 operator 逐次显式输入是 ADR-0019 临时解；登录已落地
  （REQ-2026-003），会话里有真身份（`store.user.username`），该退役了。

**范围**：

- **任务分配页（I01）**：队列列表 = `flowStatus=task_assignment` 过滤
  （page 1 / pageSize 50 + keyword 搜索），镜像家族 TaskAssignmentList。
- **安排/取消（I02）**：对话框手填「检测人员姓名 + 计划检测日期」两个文本框
  （assigneeId 不用，家族同款）；保存调 `receiptsAssignTask`；取消安排 =
  两字段清空提交。安排/取消成功后整表刷新。
- **act 三动作（I05）**：`POST /receipts/assigning/act`，body.action =
  {submit、return、withdraw}；提交→进数据录入、退回→打回接样、撤回→本阶段
  重置。operator 取真会话身份。
- **接样 act 同批改造**：M03.F01 接样 act 的 operator 同样改为真会话身份，
  删除手输 operator 输入框（ADR-0019 临时解退役）。

**非范围**：

- I03 清空分配（家族也是规划态）、I04 任务分配三态过滤器（同）——后续需求。
- M03.F03 及之后的数据录入/报告四阶段流——各自独立需求。

### 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 本期范围：家族已上线三件 vs 连规划态 I03/I04 一起做？ | **跟家族已上线三件**（I01 队列 + I02 安排/取消 + I05 act 三动作）；I03/I04 保持规划态与家族对齐，后续需求再补。 | zcqiand | 2026-09-28 |
| Q2 分配形态：手填姓名+日期 vs 选人（assigneeId）？ | **手填姓名+日期**（家族同款，assigneeId 不传）；零契约改动，镜像实现。 | zcqiand | 2026-09-28 |
| Q3 act 的 operator：沿用逐次手输（ADR-0019 临时解）vs 真会话身份？ | **真会话身份**（`store.user.username`）；M03.F01 接样 act 同批改造对齐，手输 operator 输入框删除，ADR-0019 临时解退役。 | zcqiand | 2026-09-28 |

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | 已登录，存在 task_assignment 态接样单 | 进任务分配页 | 队列只显示 task_assignment 态单子；keyword 过滤生效 |
| AC-2 | 队列中未分配单子 | 填姓名+日期保存 | assigneeName/plannedTestDate 落库，列表刷新呈现；两输入框空 = 保存禁用 |
| AC-3 | 已分配单子 | 取消安排 | assignee/plannedTestDate 清空，单子回未分配呈现 |
| AC-4 | 队列勾选单子 | act 三动作 | submit → 单子离队（进 data_entry）；return → 回接样；withdraw → 本阶段重置；operator = 会话用户名 |
| AC-5 | 接样页 act 提交 | 无手输 operator | operator = 会话用户名；手输框不存在 |
| AC-6 | act/安排失败（网络或后端拒） | 观察列表与会话态 | 列表保持原状，错误信息呈现，无半写状态 |

## 3. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：M03.F02 子项登记（I01/I02/I05，镜像家族编号，I06/I07 家族已废弃语义并入 I05 不复用）→ 人批 → 规划态登记；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit：AssignTaskViewModel（安排/取消，红先行 7 测试）+ ReceivingFlowViewModel 身份缺席 fail-fast（missingOperator，I05/F01 共用）；队列复用 ReceiptListViewModel（flowStatus 预设） | 完成（旧树红 → 48/48 绿） |
| T-2 | App 页面：TaskAssignmentView（队列 + AssignSheet 安排对话框 + act 菜单）+ 列表页 checklist 入口；ActConfirmSheet operator 改会话身份注入（手输框删除）+ ActEndpoint 端点档位；APIGlue +assignTask/assigningAct | 完成（BUILD SUCCEEDED） |
| T-3 | trace_cmd 36 测试挂 14 ID（I01/I02/I05 入账）+ 功能树/设计映射开发中 + 全门绿（L2 98s / L4 47s / L5 软告警 0）+ push | 完成 |

## 4. 功能影响

| 功能 ID | 影响类型 | 说明 |
|---|---|---|
| M03.F02.I01 | 变更 | 任务分配队列（规划态子项，tree-change 批准后登记） |
| M03.F02.I02 | 变更 | 安排/取消检测人员与计划日期（同上） |
| M03.F02.I05 | 变更 | 任务分配 act 三动作（同上；I06 退回/I07 家族已废弃语义并入） |
| M03.F01.I08 | 变更 | 接样 act 三动作 operator 改真会话身份（行为变更，行说明不变） |
| M03.F01.I04 | 变更 | 提交接样单同批（operator 来源随 I08） |

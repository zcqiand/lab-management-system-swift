# REQ-2026-001 M03.F01 接样管理（SwiftUI iOS 首个功能切片）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-27 |
| 优先级 | P0 |
| 状态 | 已评审 |
| 关联 ADR | — |

## 1. 需求描述

**用户原话**（2026-09-27，范围决策）：

> 需求基线 = 应该是 shared 仓，lab 只做 M03 实验过程管理，api 接口使用 shared 仓生成

**我的理解**：本仓（lab-management-system-swift）第一个落地功能 = **M03.F01 接样管理**。需求与 API 基线 = `lab-management-system-shared` TypeSpec SSOT：

- 行为规格读 `tsp/routes/sample-receipts.tsp` + `tsp/models/sample-receipt.tsp`（本需求消费的端点）：
  - `GET /api/v1/receipts` —— 列表（page/pageSize/keyword/contractId/flowStatus/filter 三态过滤）
  - `GET /api/v1/receipts/{id}` —— 详情（接样信息+样品+检测数据+flowHistory）
  - `POST /api/v1/receipts` —— 创建（CreateSampleReceiptRequest）
  - `PUT /api/v1/receipts/{id}` —— 更新（PATCH 语义）
  - `DELETE /api/v1/receipts/{id}` —— 删除
  - `GET /api/v1/receipts/{id}/history` —— 流程历史 FlowHistoryEntry[]
  - `POST /api/v1/receipts/receiving/act` —— 接样阶段流程动作（body.action={SUBMIT、RETURN、WITHDRAW}）
- Swift API client **只用 shared 仓 `generated/openapi/openapi.yaml` 生成物**（openapi-generator `swift5`，本需求内实证并钉 exact 版本），禁手写接口层（suite 硬规则 §4）。
- UI/交互参照 `../lab-management-system-react` 的接样单列表/表单/详情页（参照实现，非基线）。
- 后端可在 nextjs / springboot / aspnetcore 之间切换（家族 env 约定，无默认值兜底）。

### 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 会话来源：本仓范围裁掉了 react 树的「租户管理/会话」模块，M03.F01 调 API 需要租户级 token，token 从哪来？ | CoreKit 显式注入会话（baseURL+token 配置缺失即 fail-fast，不兜底）；登录 UI 走后续需求。 | zcqiand | 2026-09-27 |
| Q2 UI 层节奏：SwiftUI 页面需要 Xcode 工程（xcodebuild 门禁，当前远程门只有 swift build/swift test 的 SPM 链）。本需求是否先落 CoreKit，UI 层待工程门禁就绪后另开需求？ | 本需求**连带建 Xcode 工程**：`project.yml`（XcodeGen）入仓，远程门 L2/L4 扩 xcodebuild（模拟器目标 iOS 18.2），CoreKit 测试仍走 swift test。 | zcqiand | 2026-09-27 |
| Q3 I07（接样单 ext 字段补录，PUT /api/samples/{id}/ext）：react F01 含此子项，但它依赖检测类别 extFields 目录数据（inspection-catalog 端点）。 | 自裁：**延后**到独立需求（届时一并评估 catalog 只读依赖的最小面），本需求不实现；功能树照登记（状态=规划）。 | Claude（待追认） | 2026-09-27 |

## 2. 验收标准

> 写不出「则」的，不是验收标准，是愿望。AC 挂 CoreKit 侧 XCTest（red-first，home-mac 跑）。

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | 生成 client 已就绪、后端可达 | 拉取接样单列表（首页） | 发 `GET /api/v1/receipts?page=1&pageSize=20`，按 `Page<SampleReceipt>` 生成模型解析成功；分页字段与家族约定对齐（page 1-based） |
| AC-2 | 列表页可筛选 | 分别选「全部 / 未提交 / 已提交」三态 | 分别发不传 filter、`filter=not_yet`、`filter=submitted`（三态语义由后端实现，前端只负责传参与 UI 态一一对应）；叠加 keyword/contractId/flowStatus 时参数正确拼接 |
| AC-3 | 表单必填项齐备 | 提交新建 | 发 `POST /api/v1/receipts`，body 为 CreateSampleReceiptRequest 必填集（contractId、commissionCode、commissionDate、categoryCode、receivedBy、sampleSource、testCategory）；成功后新单 flowStatus=receiving |
| AC-4 | 已有接样单 | 编辑部分字段保存 | 发 `PUT /api/v1/receipts/{id}`，仅携带变更字段（PATCH 语义） |
| AC-5 | 已有接样单 | 删除并确认 | 发 `DELETE /api/v1/receipts/{id}`；成功后从列表移除 |
| AC-6 | 已有接样单 | 打开详情页流程历史 | 发 `GET /api/v1/receipts/{id}/history`，按 `FlowHistoryEntry[]` 渲染时间线 |
| AC-7 | 停在 receiving 环节的接样单 | 执行提交 | 发 `POST /api/v1/receipts/receiving/act`，`body.action=SUBMIT`；返回 FlowActionResult[]；退回/撤回同端点 `action=RETURN/WITHDRAW` |
| AC-8 | 后端地址配置 | 切换 nextjs/springboot/aspnetcore | base URL 全部来自显式配置，缺失即 fail-fast（禁 env 默认值兜底，硬规则 §1）；API 面只认生成物 |
| AC-9 | CI 门禁 | `python scripts/gate.py -p lab-management-system-swift` | exit 0（L2/L4 走 home-mac 远程 swift build/test） |

## 3. 任务拆解

| 任务 ID | 任务描述 | 类型 | 负责人 | 预估 | 状态 |
|---|---|---|---|---|---|
| T-1 | shared 产物消费链：`scripts/gen-shared.sh` 拉 shared `generated/openapi/openapi.yaml` → openapi-generator CLI `swift5` 生成到 `Generated/`（禁手改）；钉 exact 版本进 `version-lock.json`，codegen.md「候选」标记收口 | 基建 | Claude | 0.5d | 待开始 |
| T-2 | CoreKit：APIClient 配置（baseURL + 会话显式注入，fail-fast，AC-8；Q1 结论） | 基建 | Claude | 0.5d | 待开始 |
| T-3 | red-first XCTest：AC-1..AC-7 的请求构造与响应解析（home-mac 远程跑红→绿） | 测试 | Claude | 1d | 待开始 |
| T-4 | CoreKit ViewModel：列表/表单/详情/act 状态机（纯 Swift，禁 import SwiftUI） | 实现 | Claude | 1d | 待开始 |
| T-5 | Xcode 工程：`project.yml`（XcodeGen）入仓 + App target（SwiftUI 页面：列表三态过滤/表单/详情时间线/act 确认）；远程门 L2/L4 扩 xcodebuild（Q2 结论） | 基建+实现 | Claude | 1.5d | 待开始 |
| T-6 | gate 全绿 + `/handoff` | 收尾 | Claude | 0.5h | 待开始 |

## 4. 功能影响（需求与功能对齐的唯一位置）

> ID 均已存在于 `docs/functions/function-tree.md`（I 级本次随本需求拆出，同 commit 登记）。

| 功能 ID | 功能名称 | 影响类型 | 说明 | 关联任务 |
|---|---|---|---|---|
| M03.F01 | 接样管理（CRUD + 三态过滤） | 变更 | 状态 规划 → 开发中（首个需求引用）；I 级拆分见功能树 | T-1..T-6 |
| M03.F01.I01 | 接样单列表（三态过滤） | 变更 | 新拆 I 级，登记状态=规划 | T-3、T-4、T-5 |
| M03.F01.I02 | 新建/编辑接样单 | 变更 | 同上 | T-3、T-4、T-5 |
| M03.F01.I03 | 删除接样单 | 变更 | 同上 | T-3、T-4、T-5 |
| M03.F01.I04 | 提交接样单（receiving → task_assignment） | 变更 | 同上 | T-3、T-4 |
| M03.F01.I06 | 接样单流程历史 | 变更 | 同上 | T-3、T-4 |
| M03.F01.I08 | 接样-提交（act 三动作） | 变更 | 同上 | T-3、T-4 |
| M03.F01.I07 | 接样单 ext 字段补录 | 变更 | 新拆 I 级登记=规划；**本需求不实现**（Q3 延后） | — |

## 5. 流程影响

本仓 `docs/design/flow-function-map.md` 无既有流程步骤引用（首切片）；无影响。

## 6. 风险与回滚

| 风险 | 影响面 | 缓解 | 回滚方式 |
|---|---|---|---|
| openapi-generator `swift5` 产物不满足家族约定（URLSession/async-await、Codable 命名） | T-1 阻塞 | 候选期已标注；不行则评估 `swift5` 配置项或备选生成器，停下问人（ADR-0036 式决策） | 回退到手写最小 client 是**违规路径**（硬规则 §4）——只能换生成器配置重生成 |
| home-mac 离线（休眠）导致 L2/L4 挂 | 门禁 | caffeinate + Tailscale 探活后再跑 | 重跑 |
| 会话/token 缺口径（Q1）就开工 | T-2 返工 | Q1 澄清前不开工 T-2 之后的任务 | — |

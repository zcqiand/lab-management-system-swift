# REQ-2026-002 M03.F01 UI 壳（SwiftUI 页面全套 + trace 挂 ID）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-28 |
| 优先级 | P1 |
| 状态 | 已评审 |
| 关联 ADR | — |
| 上游 | REQ-2026-001（CoreKit / Xcode 工程已落地；本需求是其 T-5 中 UI 部分的兑现） |

## 1. 需求描述

**背景**：REQ-2026-001 T-5 实际只落了 project.yml + LabSharedGenerated/CoreKit/CoreKitTests 三个 target，
App target 与 SwiftUI 页面未建（T-6 收口时明确留待下一需求）。CoreKit 侧已有 18 测全绿的
ViewModel（列表/act），API 面全部来自 shared 生成物。本需求把 UI 接上，并把 trace 挂 ID 链接通。

**用户原话**（2026-09-28，三项澄清裁决）：

> 会话注入入口 = 首启配置页（推荐项被选）；trace 机制 = 源码字面扫描（推荐项被选）；UI 范围 = 全套（推荐项被选）

**范围**：

- **App target**：project.yml 新增 `LabManagement` App target（SwiftUI `@main`），依赖 CoreKit；远程门 L2 的 xcodebuild 段扩到 App target 编译（仍是 build，模拟器 test 段维持撤出，见风险 R1）。
- **首启配置页**（Q1 裁决）：App 启动检测未配置（baseURL/token 缺一）→ 全屏配置页，输入保存进 UserDefaults；已配置 → 直进列表页。fail-fast 语义 = 未配置绝不发任何 API 请求、代码里无默认值兜底（硬规则 §1；UserDefaults 是用户显式输入的持久化，不是代码兜底，L0.no_fallback 口径不受影响）。
- **页面全套**（Q3 裁决，对齐 `../lab-management-system-react` 参照页）：
  - 列表页：三态过滤（全部/待提交/已提交）+ keyword 搜索 + 分页加载更多（I01）
  - 新建/编辑表单：CreateSampleReceiptRequest 必填集校验（I02）
  - 删除确认弹窗（I03）
  - 详情页：接样信息 + 样品 + 检测数据 + 流程历史时间线（I06）
  - act 确认：SUBMIT/RETURN/WITHDRAW（退回需 reason），结果回填列表（I04、I08）
- **trace 挂 ID**（Q2 裁决）：`scripts/trace_cmd.py` 扫 `Tests/` 源码 `// fn: Mxx.Fxx.Ixx` 字面 →
  产出 `.state/trace.json`（禁手写，硬规则）；`.harness/stack.json` 的 `trace_cmd` 接线；
  既有 18 测补挂 ID 字面。机制同 contract-test SSOT 解析器思路（只扫源码字面）。

### 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 App target 从哪拿 baseURL+token（Q1-001 已裁登录 UI 走后续需求）？ | 首启配置页：未配置 → 全屏配置页，UserDefaults 持久化；已配置直进列表。未配置绝不发请求。 | zcqiand | 2026-09-28 |
| Q2 Swift XCTest 无 pytest marker 生态，trace.json 怎么产出？ | 源码字面扫描：trace_cmd 扫 Tests/ 的 `// fn: <ID>` 字面 → .state/trace.json。局限与各家栈相同（证明「存在声称覆盖的测试」，不证明真执行到）。 | zcqiand | 2026-09-28 |
| Q3 UI 一次到位还是切片？ | 全套：6 个开发中 I 项（I01-I04/I06/I08）一次接上 UI。 | zcqiand | 2026-09-28 |

## 2. 验收标准

> 挂 CoreKit 侧 XCTest（red-first，home-mac 远程跑）；UI 绑定层以 xcodebuild 编译过为验收（R1）。

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | App 未配置（首次启动/清空配置） | 启动 | 呈现配置页，零 API 调用；输入合法 baseURL+token 保存后进列表页 |
| AC-2 | 已配置 | 列表页切三态 | 分别发不传 filter / `filter=not_yet` / `filter=submitted`；行为与既有 ReceiptListViewModel 测试一致 |
| AC-3 | 表单必填项缺一 | 点保存 | 不发请求，逐项标错；必填集齐 → `POST /api/receipts` body 为 CreateSampleReceiptRequest 必填集 |
| AC-4 | 已有接样单 | 编辑部分字段保存 | 发 `PUT /api/receipts/{id}` 仅携带变更字段（PATCH 语义） |
| AC-5 | 已有接样单 | 删除确认 | 发 `DELETE /api/receipts/{id}`；成功后列表移除 |
| AC-6 | 已有接样单 | 打开详情 | 并发拉 `GET /api/receipts/{id}` + `GET /api/receipts/{id}/history`，FlowHistoryEntry[] 渲染时间线 |
| AC-7 | receiving 环节接样单 | act 三动作 | 发 `POST /api/receipts/receiving/act`，action=SUBMIT/RETURN/WITHDRAW（RETURN 带 reason）；结果按 id 回填列表 |
| AC-8 | 任意工作树状态 | 跑 `trace_cmd` | `.state/trace.json` 生成且含 I01-I04/I06/I08 引用；L4 trace 消费不红；手改 trace.json 后重跑 trace_cmd 即被覆盖（证非手写） |
| AC-9 | CI 门禁 | `python scripts/gate.py -p lab-management-system-swift` | exit 0（L2 含 App target 编译） |

## 3. 任务拆解

| 任务 ID | 任务描述 | 类型 | 负责人 | 预估 | 状态 |
|---|---|---|---|---|---|
| T-1 | `scripts/trace_cmd.py`（扫 Tests/ 字面 → .state/trace.json，幂等）+ stack.json `trace_cmd` 接线 + 既有 18 测补 `// fn:` 字面 + 全门验证 AC-8 | 基建 | Claude | 0.5d | 待开始 |
| T-2 | CoreKit 扩展（red-first）：SessionStore 配置状态机（AC-1）+ 表单校验/详情/删除 ViewModel（AC-3..AC-6 请求构造与解析） | 测试+实现 | Claude | 1d | 待开始 |
| T-3 | App target 入 project.yml + SwiftUI 页面全套（配置/列表/表单/详情/act 确认/删除确认）绑定既有与新增 ViewModel；L2 xcodebuild 段扩 App target 编译 | 实现 | Claude | 1.5d | 待开始 |
| T-4 | gate 全绿 + design-function-map 状态对齐 + `/handoff` | 收尾 | Claude | 0.5h | 待开始 |

## 4. 功能影响（需求与功能对齐的唯一位置）

> ID 均已存在于 `docs/functions/function-tree.md`，状态均已=开发中（REQ-2026-001 登记）。**全部为变更引用，无新增/废弃，不走 /tree-change。**

| 功能 ID | 功能名称 | 影响类型 | 说明 | 关联任务 |
|---|---|---|---|---|
| M03.F01.I01 | 接样单列表（三态过滤） | 变更 | UI 列表页接上（此前仅 ViewModel） | T-2、T-3 |
| M03.F01.I02 | 新建/编辑接样单 | 变更 | UI 表单 + 表单 ViewModel | T-2、T-3 |
| M03.F01.I03 | 删除接样单 | 变更 | UI 删除确认 + 删除 ViewModel | T-2、T-3 |
| M03.F01.I04 | 提交接样单（receiving → task_assignment） | 变更 | act 确认页 SUBMIT 入口 | T-3 |
| M03.F01.I06 | 接样单流程历史 | 变更 | 详情页时间线 + 详情 ViewModel | T-2、T-3 |
| M03.F01.I08 | 接样-提交（act 三动作） | 变更 | act 确认页三动作 + reason | T-3 |

## 5. 流程影响

本仓 `docs/design/flow-function-map.md` 无流程步骤引用；无影响。

## 6. 风险与回滚

| 风险 | 影响面 | 缓解 | 回滚方式 |
|---|---|---|---|
| R1 模拟器 xcodebuild test 机器态 3 连红未解（REQ-2026-001 遗留） | UI 层验收强度 | 本需求 UI 验收 = L2 编译 + L4 swift test（ViewModel）；XCUITest 不进本需求，模拟器段恢复后人裁补 | — |
| R2 UserDefaults 持久化被误判为 env 兜底 | L0.no_fallback | 口径已写明：用户显式输入的持久化 ≠ 代码默认值；trace_cmd/门禁若误报按 exit 2 停下问人 | — |
| R3 trace 字面扫描的固有局限（声称≠执行） | 测试可信度 | 与全家各栈同限；挂 ID 纪律 = 人审 diff（ID 必须挂在真覆盖该功能的测试上） | — |

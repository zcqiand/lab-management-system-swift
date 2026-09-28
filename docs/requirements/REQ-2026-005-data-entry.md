# REQ-2026-005 数据录入（M03.F03 流程第三环节）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-29 |
| 优先级 | P1 |
| 状态 | **已评审**（三项澄清已裁，2026-09-29；待 tree-change 批准后开工） |
| 关联 ADR | ADR-0019（operator=真会话身份已随 REQ-2026-004 落地，本需求沿用） |
| 上游 | REQ-2026-004（任务分配，流程第二环节）；REQ-2026-003（登录，会话身份前置） |

## 1. 需求描述

**用户原话**（2026-09-29，三项裁决）：

> 范围 = 跟家族已上线四件；录入形态 = 同款录入 sheet（选样品+选参数+填表单，存在即更新否则创建）；verdict = 随 save body

**背景**：

- 家族 vue/react 已上线 M03.F03 四件：录入页（data_entry 队列→录入对话框）、
  保存检测记录、人工改判 verdict、act 三动作。Swift 仓流程线断在第三环节。
- **契约零改动**：shared 生成物已含全部 API 面（§4 只认生成物）——
  `samplesListSamples(receiptId:page:pageSize:)`、
  `inspectionDictionaryListParameters(page:pageSize:)`、
  `testRecordsListTestRecords(sampleId:page:pageSize:)`、
  `testRecordsCreateTestRecord` / `testRecordsUpdateTestRecord`（Create/Update
  Request 均带 verdict 可选字段）、`receiptsActFlowDataEntry`（FlowActionRequest，
  operator=会话身份沿用 REQ-2026-004 模式）。本仓纯消费。

**范围**：

- **录入页（I01）**：队列列表 = `flowStatus=data_entry` 过滤（page 1 /
  pageSize 50 + keyword），行点「录入结果」弹 sheet：样品 Picker（按
  receiptId 拉样品）+ 参数 Picker（字典参数）+ 表单（result 必填 +
  requirement/standardCode/verdict），已有记录回填，按
  `sampleId#parameterCode` 判断更新或创建——家族同款。
- **保存检测记录（I02）**：调 `testRecordsCreateTestRecord` 或
  `testRecordsUpdateTestRecord`（按是否存在同键记录），result 必填
  fail-fast；保存成功后该样品记录刷新。
- **人工改判 verdict（I03）**：改判 = 表单内 verdict 选择器改值随保存请求体
  一并提交（家族 vue+react 实证均走 save body；生成物专用
  `testRecordsSetVerdict` 端点家族录入页未用，本仓同样不用）。
- **act 三动作（I12）**：`POST /receipts/data-entry/act`，body.action =
  {submit、return、withdraw}；operator = 真会话身份（REQ-2026-004 已建立的
  ActConfirmSheet 会话注入模式，新增 `.dataEntry` 端点档位）。

**非范围**：

- I04 更新样品、I06~I09 记录列表/详情/创建/更新接口行（家族也是规划态）。
- I15 数据录入三态过滤器（家族开发中，Swift 后续需求）。
- M03.F05~F08 报告四阶段——各自独立需求。

### 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 本期范围：家族已上线四件 vs 连规划态接口行一起登记？ | **跟家族已上线四件**（I01 录入页 + I02 保存 + I03 改判 + I12 act）；I04/I06-I09 保持规划态与家族对齐，I15 家族开发中也不占。 | zcqiand | 2026-09-29 |
| Q2 录入页形态：家族同款 sheet vs 参数矩阵页？ | **同款录入 sheet**（队列行点「录入结果」→ 选样品 + 选参数 + 填表单，按 sampleId#parameterCode 存在即更新否则创建）；零契约改动，镜像实现。 | zcqiand | 2026-09-29 |
| Q3 verdict 改判走哪条端点：随 save body vs 专用 setVerdict？ | **随 save body**（家族 vue+react 两仓实证一致；setVerdict 端点在生成物里但家族 UI 未用）。 | zcqiand | 2026-09-29 |

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | 已登录，存在 data_entry 态接样单 | 进数据录入页 | 队列只显示 data_entry 态单子；keyword 过滤生效 |
| AC-2 | 队列单子，无同键记录 | 录入 sheet 选样品+参数，填 result 保存 | 走 create；verdict/requirement/standardCode 随请求体提交；记录列表刷新呈现 |
| AC-3 | 同 sampleId#parameterCode 已有记录 | 打开录入 sheet | 表单回填已有记录；改 result/verdict 保存走 update |
| AC-4 | 队列单子 | act 三动作 | submit → 单子离队进下一环节；return → 打回上一环节；withdraw → 本阶段重置；operator = 会话用户名 |
| AC-5 | result 为空 | 保存 | fail-fast 校验拒绝，请求不发出，错误信息呈现 |
| AC-6 | 保存/act 失败（网络或后端拒） | 观察表单与列表 | 表单保持用户输入，列表原状，错误信息呈现，无半写状态 |

## 3. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：M03.F03 子项登记（I01/I02/I03/I12，镜像家族编号，I13/I14 家族已废弃语义并入 I12 不复用）→ 人批 → 登记 + F03 规划→开发中；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit 红先行：DataEntryViewModel（样品/参数/记录装载 + sampleId#parameterCode 键控 create-vs-update 请求构建，result 必填 fail-fast，verdict 随 body）+ 队列复用 ReceiptListViewModel（flowStatus=.dataEntry 预设） | 完成（旧树红 `cannot find 'DataEntryViewModel'` → 55/55 绿，+7 测试） |
| T-2 | App 页面：DataEntryView（队列 + EntrySheet 录入对话框：样品/参数 Picker + 表单）+ act 菜单（ActConfirmSheet + ActEndpoint `.dataEntry` 档位）；APIGlue +receiptSamples/parameters/testRecords/persistTestRecord/dataEntryAct | 完成（BUILD SUCCEEDED） |
| T-3 | trace_cmd 挂 ID（I01/I02/I03/I12）+ 功能树/设计映射开发中 + 全门绿 + push | 进行中（trace 42 测试挂 18 ID，F03 四件入账） |

## 4. 功能影响

| 功能 ID | 影响类型 | 说明 |
|---|---|---|
| M03.F03.I01 | 变更 | 样品 + 检测数据录入页（tree-change 批准后登记） |
| M03.F03.I02 | 变更 | 保存检测记录（同上；verdict 随 body，Q3 裁定） |
| M03.F03.I03 | 变更 | 人工改判 verdict（同上；改判=表单改值随保存提交，不走专用 setVerdict） |
| M03.F03.I12 | 变更 | 数据录入 act 三动作（同上；I13 退回/I14 家族已废弃语义并入；operator=会话身份） |

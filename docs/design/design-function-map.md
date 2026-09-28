# 设计与功能对齐 — 实验室管理系统（lab-management-system-swift）

> 人填、人评审。机器只检查功能 ID 存在性。
> 回答一个问题：**这个功能子项，落到哪段代码、哪张表、哪个权限码上？**
> 答不上来的行，说明设计没做完，别开工。

## 映射表

> 前端 only 仓：数据表列恒为 —（不落表，表在家族后端仓）；接口列 = shared TypeSpec SSOT
> 生成物路径（Generated/Sources/APIs/ReceiptsAPI.swift，主路由 `/api`，无 /v1 前缀）。
> 权限码 = 功能子项 ID（约定 1）；登录 UI 已落地（REQ-2026-003 T-3），按钮级权限判断仍按按钮归属页面自查。

| 功能子项 ID | 页面/组件 | 接口 | 数据表 | 权限码 | 设计稿 | 状态 |
|---|---|---|---|---|---|---|
| M00.F01 | AccountView（当前用户 + 会话恢复） | GET /api/auth/me；登录响应快照持久化 | — | M00.F01 | ../lab-management-system-react 顶栏账户区 | 开发中 |
| M00.F02.I01 | AccountView 租户切换器 | POST /api/auth/switch-tenant | — | M00.F02.I01 | ../lab-management-system-react 租户切换 | 开发中 |
| M01.F05.I02 | APIGlue.run 401 拦截 + bootstrap Bearer 注入 | 全部 /api/*（拦截器语义） | — | M01.F05.I02 | — | 开发中 |
| M01.F05.I04 | AccountView 登出按钮 | POST /api/auth/logout | — | M01.F05.I04 | ../lab-management-system-react 顶栏登出 | 开发中 |
| M01.F05.I06 | LoginView（用户名+密码原生表单） | POST /api/auth/native-login | — | M01.F05.I06 | ../lab-management-system-react 登录页 | 开发中 |
| M03.F01.I01 | ReceiptListView（列表：三态过滤/keyword/分页） | GET /api/receipts | — | M03.F01.I01 | ../lab-management-system-react 接样单列表页 | 开发中 |
| M03.F01.I02 | ReceiptFormView（新建/编辑表单） | POST /api/receipts；PUT /api/receipts/{id} | — | M03.F01.I02 | ../lab-management-system-react 接样单表单页 | 开发中 |
| M03.F01.I03 | ReceiptListView 删除确认弹窗 | DELETE /api/receipts/{id} | — | M03.F01.I03 | ../lab-management-system-react 接样单列表页 | 开发中 |
| M03.F01.I04 | ReceiptActView（act 确认 · SUBMIT） | POST /api/receipts/receiving/act | — | M03.F01.I04 | ../lab-management-system-react 接样单详情页 | 开发中 |
| M03.F01.I06 | ReceiptDetailView（流程历史时间线） | GET /api/receipts/{id}/history | — | M03.F01.I06 | ../lab-management-system-react 接样单详情页 | 开发中 |
| M03.F01.I08 | ReceiptActView（act 确认 · SUBMIT/RETURN/WITHDRAW） | POST /api/receipts/receiving/act | — | M03.F01.I08 | ../lab-management-system-react 接样单详情页 | 开发中 |
| M03.F02.I01 | TaskAssignmentView（分配队列，ReceiptListViewModel 复用 + flowStatus 预设） | GET /api/receipts（flowStatus=task_assignment） | — | M03.F02.I01 | ../lab-management-system-react TaskAssignmentPage | 开发中 |
| M03.F02.I02 | AssignSheet（手填姓名+日期对话框，AssignTaskViewModel） | PUT /api/receipts/{id}/assign-task | — | M03.F02.I02 | ../lab-management-system-react TaskAssignmentList 安排对话框 | 开发中 |
| M03.F02.I05 | ActConfirmSheet（act 三动作，operator=会话身份） | POST /api/receipts/assigning/act | — | M03.F02.I05 | ../lab-management-system-react FlowStagePage | 开发中 |
| M03.F03.I01 | DataEntryView（data_entry 队列）+ EntrySheet（样品/参数 Picker + 表单，DataEntryViewModel 键控） | GET /api/receipts（flowStatus=data_entry）；GET /api/samples（receiptId）；GET /api/inspection-dictionary/parameters；GET /api/test-records（sampleId） | — | M03.F03.I01 | ../lab-management-system-react DataEntryPage | 开发中 |
| M03.F03.I02 | EntrySheet 保存（DataEntryViewModel create-vs-update 按同键记录，result 必填 fail-fast） | POST /api/test-records；PUT /api/test-records/{id} | — | M03.F03.I02 | ../lab-management-system-react DataEntryPage 录入对话框 | 开发中 |
| M03.F03.I03 | EntrySheet verdict 选择器（改判随保存 body，不走专用 setVerdict） | POST /api/test-records；PUT /api/test-records/{id} | — | M03.F03.I03 | ../lab-management-system-react DataEntryPage 录入对话框 | 开发中 |
| M03.F03.I12 | ActConfirmSheet（act 三动作，endpoint=.dataEntry，operator=会话身份） | POST /api/receipts/data-entry/act | — | M03.F03.I12 | ../lab-management-system-react FlowStagePage | 开发中 |
| M03.F01.I07 | （ext 字段补录，REQ-2026-001 Q3 延后） | PUT /api/samples/{id}/ext | — | M03.F01.I07 | — | 规划 |

## 约定

1. **权限码 = 功能子项 ID。** 前端按钮的权限判断直接写 ID。
2. 一个接口服务多个子项时，多行重复写。不要为表好看而合并 —— 合并后看不清接口还有没有别的调用方。
3. 状态列必须与功能清单一致。不一致以功能清单为准。

## 评审时问这三个问题

1. 有没有子项没有权限码？→ 那它就是任何人都能点的按钮
2. 有没有一张表被三个以上模块直接写入？→ 边界破了
3. 「开发中」的行里接口和表填了吗？→ 没填就是还在纸上，别报进度

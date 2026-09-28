# lab-management-system-swift 功能树

> 建筑工程实验室管理系统 — SwiftUI iOS 前端。consumes `lab-management-system-shared` TypeSpec SSOT（需求与 API 基线；API 只用 shared 生成物）。
> **范围**：2026-09-27 人决策裁剪 **M03 实验过程管理**；2026-09-28 REQ-2026-003（登录 UI）扩入
> **M00 租户管理 / M01 认证管理**的登录相关行（tree-change 提案人批）。M02/M04/M05/M06 仍不在范围
> （M/F 编号沿用 react 仓功能树 = shared BASE 双账本，扩范围时按该编号对齐，不另起编号）。
> **前端 only 仓**：不实现任何后端；后端可在 `lab-management-system-nextjs` / `-springboot` / `-aspnetcore` 之间切换（同契约异实现）。
> 状态推进路径：规划 → 开发中 → 已上线。子项级（I 级）等第一个需求落地时再拆，不预拆。

## 模块总览

| 模块 ID | 模块名称 | 说明 | 状态 |
|---|---|---|---|
| M00 | 租户管理 | 当前用户关联租户列表、登录选租户、切换租户 | 规划 |
| M01 | 认证管理 | 权限管理（RBAC/路由守卫/动态菜单）、认证（登录/SSO/JWT） | 规划 |
| M03 | 试验过程管理 | 接样 → 任务分配 → 4 阶段报告流 | 规划 |

---

## M00 租户管理

| 功能 ID | 功能名称 | 说明 | 状态 |
|---|---|---|---|
| M00.F01 | 当前用户会话 | 账户页展示当前用户 + 会话恢复；接口 `GET /auth/me` | 开发中 |
| M00.F02 | 登录选租户 | 多租户账号登录后按 currentTenantId 直进 | 规划 |
| M00.F02.I01 | 租户切换器 | 按钮：`POST /auth/switch-tenant` 换发新租户 token，切换后列表整表刷新（REQ-2026-003） | 开发中 |

---

## M01 认证管理

| 功能 ID | 功能名称 | 说明 | 状态 |
|---|---|---|---|
| M01.F05 | 认证管理（登录/SSO/JWT） | 原生登录 + token 生命周期（Keychain）；web 端走 SSO | 规划 |
| M01.F05.I02 | Token 注入与失效跳登录 | 接口：401 拦截跳登录 + token 注入请求头（REQ-2026-003） | 开发中 |
| M01.F05.I03 | SSO OAuth 2.0 授权码流（原生形态） | 接口：ASWebAuthenticationSession 消费（shared A+B 契约支撑）；后续需求 | 规划 |
| M01.F05.I04 | 登出 | 按钮：logout + Keychain 清空 → 回登录页（REQ-2026-003） | 开发中 |
| M01.F05.I06 | 原生登录（非浏览器表单） | 页面：用户名+密码 → `POST /auth/native-login` 换 lab JWT（REQ-2026-003 Q4-C；I01 家族已废弃号不回收，I05 已用取下一号） | 开发中 |

---

## M03 试验过程管理

| 功能 ID | 功能名称 | 说明 | 状态 |
|---|---|---|---|
| M03.F01 | 接样管理（CRUD + 三态过滤） | 接样单列表/新建/编辑/删除 + act 提交/退回/撤回；REQ-2026-001 | 开发中 |
| M03.F01.I01 | 接样单列表（三态过滤） | 页面：`GET /receipts` + filter 三态（全部/未提交/已提交） | 开发中 |
| M03.F01.I02 | 新建/编辑接样单 | 按钮：POST/PUT `/receipts`（PATCH 语义） | 开发中 |
| M03.F01.I03 | 删除接样单 | 按钮：DELETE `/receipts/{id}` | 开发中 |
| M03.F01.I04 | 提交接样单（receiving → task_assignment） | 按钮：act `action=SUBMIT` | 开发中 |
| M03.F01.I06 | 接样单流程历史 | 接口：`GET /receipts/{id}/history` 渲染时间线 | 开发中 |
| M03.F01.I07 | 接样单 ext 字段补录 | 接口：`PUT /api/samples/{id}/ext`；延后独立需求（REQ-2026-001 Q3） | 规划 |
| M03.F01.I08 | 接样-提交（act 三动作） | 接口：`POST /receipts/receiving/act`，body.action={SUBMIT、RETURN、WITHDRAW} | 开发中 |
| M03.F02 | 任务分配（安排检测人员/计划日期） | 分配队列 + 安排/取消 + act 三动作 | 开发中 |
| M03.F02.I01 | 任务分配队列 | 页面：`GET /receipts`（flowStatus=task_assignment）+ keyword；REQ-2026-004 | 开发中 |
| M03.F02.I02 | 安排/取消检测人员与计划日期 | 按钮：`PUT /receipts/{id}/assign-task`，手填姓名+日期（assigneeId 不传）；REQ-2026-004 | 开发中 |
| M03.F02.I05 | 任务分配-提交（act 三动作） | 接口：`POST /receipts/assigning/act`，body.action={submit、return、withdraw}；operator=会话身份 | 开发中 |
| M03.F03 | 数据录入（样品检测数据 + 人工改判） | 检测记录 CRUD + 人工改判 verdict + act 三动作 | 规划 |
| M03.F05 | 报告审核流程 | review 阶段队列 + act 提交/退回/撤回 | 规划 |
| M03.F06 | 报告批准流程 | approval 阶段队列 + act 提交/退回/撤回 | 规划 |
| M03.F07 | 报告发放流程 | issuance 阶段队列 + 发放（生成报告编号） | 规划 |
| M03.F08 | 报告归档流程 | archived 阶段队列 + 归档完成 | 规划 |
| M03.F09 | 接样单详情（接样+样品+检测数据+预览） | 详情页 + 流程历史时间线 + 报告预览 | 规划 |

---

## 已废弃功能子项

> 所有 `已废弃` / `已迁移` 状态的功能子项统一汇总到这里，**按子项 ID 顺序排列**。

| 子项 ID | 名称 | 模块归属 | 迁移去向 | 状态 |
|---|---|---|---|---|
| M03.F01.I09 | 接样-退回 | M03 | 语义并入 M03.F01.I08（act 端点 body.action=RETURN 区分，无独立端点） | 已废弃 |
| M03.F01.I10 | 接样-撤回 | M03 | 语义并入 M03.F01.I08（act 端点 body.action=WITHDRAW 区分，无独立端点） | 已废弃 |

---

## 维护约定

- 谁改功能，谁改表，同一个 commit。
- `规划` → `开发中`：必须先有需求文档引用它。
- **已废弃 / 已迁移 I 级子项**：从原 F 段移到「已废弃功能子项」段，不删除行。
- 子项级（I 级）拆分规则：等第一个需求来了再拆它涉及的子项，不预拆。

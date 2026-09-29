# 人工验收清单 — lab-management-system-swift（ready 态批次 2026-09-29）

> 目的：远门（91/91 + build + 全门绿）只证明「机器能验的部分」；本清单
> 收拢「要真后端 + 模拟器手动走一遍」的场景，验收通过后按 REQ 范围把
> 功能树「开发中」行翻「已上线」。
> 原则：每条对应 REQ 文档 AC 编号；结果列留空待人填；发现红走
> 「复红 → 修 → 远门重绿 → 复验」回路，不许跳过。

## 1. 环境前置（逐项打勾）

| # | 前置 | 说明 | ✓ |
|---|---|---|---|
| P1 | 真后端起来 | 任选一家族 lab 后端（aspnetcore `:5204` / springboot / nextjs，同契约异实现）；探针 `curl http://localhost:<port>/api/...` 业务通 | ☐ |
| P2 | 模拟器装 App | home-mac：`xcodegen generate && xcodebuild ... -scheme LabManagement build` 产物装 iPhone 模拟器（模拟器 xcodebuild **test** 不稳是已知机器态，手动跑 App 不受影响） | ☐ |
| P3 | App 配 baseURL | 配置页填后端地址（home-mac 上跨机填 Tailscale IP，如 `http://<win-ip>:5204`）；缺失 fail-fast 不兜底 | ☐ |
| P4 | 测试账号 | 家族 dev 凭据 `alice / dev123456`（多租户）；seed 含 task_assignment / data_entry / 报告四阶段各态单子 | ☐ |
| P5 | （仅 SSO 段）saas 白名单 | **人裁前置**：saas oauth_client 登记 iOS 回调 `labman://oauth/callback`（REQ-2026-010 Q2 跨仓数据变更）。未登记前 SSO 段跳过，不阻塞其余验收 | ☐ |

## 2. 分 REQ 场景（AC 编号见各 REQ 文档 §2）

### REQ-2026-003 / 009 登录 + 选租户直进

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 003-AC-3 | 冷启动无配置 | 配置页只收 baseURL，配后进登录页 | |
| 003-AC-2 | 登录页 alice/dev123456 | 换 JWT 进列表页；token 只在 Keychain | |
| 009-AC-1~2 | 无记忆多租户 / 单租户登录 | 直进首位 / 单一租户，不出现选租户阻塞页 | |
| 009-AC-3~4 | 切到非首位租户后登出重登 | 记忆租户压过首位；记忆已失效回落首位 | |
| 003-AC-5 | 账户页切租户 | 换发 token，列表整表刷新 | |
| 003-AC-4 | 后端停掉或改错 token 后任意操作 | 401 拦截回登录页，旧会话清除 | |
| 003-AC-6 | 登出 | logout + Keychain 清空回登录页 | |

### REQ-2026-001 / 002 接样管理 + UI 壳

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 001-AC-2 | 列表三态切换 + keyword | 三态与搜索参数生效 | |
| 001-AC-3 | 新建必填齐 | 成功落 receiving 态新单 | |
| 002-AC-3 | 必填缺一保存 | 不发请求逐项标错 | |
| 001-AC-4 | 编辑部分字段 | PUT PATCH 语义，只变更字段生效 | |
| 001-AC-5 | 删除确认 | 列表移除 | |
| 001-AC-6 | 开详情看历史 | 时间线渲染 | |
| 001-AC-7 | receiving 单 act 三动作 | SUBMIT 离队 / RETURN / WITHDRAW | |

### REQ-2026-004 任务分配

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 004-AC-1 | 进分配页 | 只见 task_assignment 态 + keyword | |
| 004-AC-2 | 未分配单填姓名+日期 | 落库刷新；两框空 = 保存禁用 | |
| 004-AC-3 | 已分配单取消 | 清空回未分配 | |
| 004-AC-4 | act 三动作 | submit 离队进 data_entry / return 回接样 / withdraw 重置；operator=会话用户名 | |

### REQ-2026-005 数据录入

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 005-AC-1 | 进录入页 | 只见 data_entry 态 + keyword | |
| 005-AC-2 | 新键录入保存 | create + verdict 随 body | |
| 005-AC-3 | 同键再开 sheet | 回填已有记录；改值走 update | |
| 005-AC-5 | result 留空保存 | fail-fast 标错，不发请求 | |
| 005-AC-4 | act 三动作 | 三向流转 + operator | |

### REQ-2026-006 报告四阶段

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 006-AC-1 | 四阶段队列各进一遍 | 各页只见本阶段态 | |
| 006-AC-2 | 各阶段 submit（审核通过/批准/发放/归档完成） | 本阶段 act 端点 + 离队 | |
| 006-AC-3 | 各阶段退回 | 回退一阶 | |
| 006-AC-4 | 发放 submit 后看行 | reportCode 呈现（后端生成） | |

### REQ-2026-007 接样单详情 + 预览

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 007-AC-2 | 观察接样信息表 | 家族全字段面，缺席显示 — | |
| 007-AC-3 | 看流程历史 | 按 at 倒序 | |
| 007-AC-1 | 点报告预览 | 按样品归集摘要 + reportCode | |
| 007-AC-4 | 无样品单点预览 | 空态/错误态不崩 | |

### REQ-2026-008 ext 补录

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 008-AC-1 | extFields 非空类别单子开预览 | 停在补录表单，预填现有 ext | |
| 008-AC-2 | 必填留空保存 | 阻断 + 标错，不打端点 | |
| 008-AC-3 | 填齐保存 | 合并 PUT ext，成功后继续装载预览 | |
| 008-AC-4 | 无 extFields 类别开预览 | 不出门直接预览 | |

### REQ-2026-010 SSO（依赖 P5）

| AC | 操作 | 期望 | 结果 |
|---|---|---|---|
| 010-AC-3 | 不配 SSO 点「SSO 登录」 | fail-fast 引导文案，不发 authorize / 不开浏览器 | |
| 010-AC-1 | 配置页存 client_id=`lab-management` + scheme=`labman` 后点 SSO 登录 | 浏览器会话跳 IdP → 登录 → 回跳换 JWT → ready 直进 | |
| 010-AC-5 | SSO 多租户账号 | settle 直进（同 009 口径） | |
| 010-AC-2 | 回跳 state 被换（篡改/重放旧回调） | 拒绝换 token，报 state 校验失败 | |
| 010-AC-4 | callback 失败（后端拒/码过期） | 失败态不进会话，可重试 | |

## 3. 通过后收口

1. 功能树：验收通过的 REQ 范围行「开发中」→「已上线」（同 commit 改树 + 台账）。
2. 台账 README 行状态同步。
3. 发现红的：修复走红先行 REQ 小补丁流程，全门重绿后复验该条。

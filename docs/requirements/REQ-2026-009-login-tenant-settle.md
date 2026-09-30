# REQ-2026-009 登录选租户直进（M00.F02）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-29 |
| 优先级 | P2 |
| 状态 | **已上线**（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） |
| 关联 ADR | ADR-0019（activeTenantId 非业务身份字段，属用户显式选择的会话 UI 态，落 UserDefaults 非密缝） |
| 上游 | REQ-2026-003（登录 UI/会话三态/切换器 I01 均已落地，本需求是父行收尾） |

## 1. 需求描述

**背景**：

- 家族 react auth-context `settleLogin` 已上线（2026-09-23 用户裁定，修 SSO
  回调冻结）：登录成功后目标租户 = **remembered**（activeTenantId 持久记忆
  ∩ 本次 tenants）**?? 单租户 ?? 首位**，直进 authenticated，不设选租户阻塞页。
- iOS 现状缺口（SessionStore 实读）：`adoptLogin` 快照 `currentTenantId`
  恒置 `nil`、无 activeTenantId 持久化、hydrate 无记忆、AccountView 切换器
  只取首位兜底。
- **契约零改动**：生成物 LoginResponse{token, refreshToken?, user, tenants}、
  CurrentUserSession.currentTenantId、POST /api/auth/switch-tenant 全在。

**范围**：

| 关注点 | 内容 |
|---|---|
| settle 直进 | SessionStore.adoptLogin 增加 activeTenantId 落账：目标 = remembered ?? 单租户 ?? 首位；快照 currentTenantId 同步写 settled 值 |
| 显式择定 | adoptLogin(response, preferredTenantId:) 新可选参——switch-tenant 换发落账时传入择定租户，压过旧记忆（M00.F02.I01 既有路径收尾） |
| hydrate | 重启恢复记忆租户（defaults 键 + 快照 currentTenantId 双源） |
| 清除 | logout/clear 清 activeTenantId（会话级状态不跨登录） |
| App | AccountView 切换器初值取 store.activeTenantId；AuthViewModel.switchTenant 传 preferredTenantId |

**非范围**：awaiting_tenant 空租户阻塞页（家族注释自述仅空租户列表可达，
iOS 以 activeTenantId=nil 呈现、UI 现状已兼容）；SSO（M01.F05.I03，明确
延后）；LabManagementApp 根路由改造（ready 态直进业务页已成立）。

## 2. 非范围补充说明

家族 awaiting_tenant 态在注释中自述「仅剩空租户列表可达」——即现网不可达
的防御态。iOS 不镜像防御态，直进语义天然覆盖：无租户 → activeTenantId=nil
→ 切换器呈现空（AccountView 现状已处理空列表）。此为语义等同裁剪，非缺口。

## 3. 验收标准

| 编号 | 场景（给定） | 操作（当） | 颲期（则） |
|---|---|---|---|
| AC-1 | 无记忆多租户账号 | 登录成功 | 直进首位租户（家族裁定），快照 currentTenantId 同步 |
| AC-2 | 单租户账号 | 登录成功 | 直进该租户 |
| AC-3 | 有记忆且记忆租户在列 | 重新登录 | 记忆压过新响应首位 |
| AC-4 | 记忆租户已不在本次 tenants | 重新登录 | 回落首位 |
| AC-5 | 账户页切租户成功 | 落账 | 择定租户进记忆并重启可恢复 |
| AC-6 | 登出 | 落账 | activeTenantId 清除，重启不残留 |

## 4. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：M00.F02 父行 规划→开发中；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit 红先行：SessionStore settle（activeTenantId 落账/记忆/显式择定/hydrate/清除）红测试 | 完成（2026-09-29，真红 `no member 'activeTenantId'` ×7 + `extra argument 'preferredTenantId'`，RED_EXIT=1 → 绿 6/6） |
| T-2 | App：AuthViewModel.switchTenant 传 preferredTenantId；AccountView 切换器初值取记忆 | 完成（2026-09-29） |
| T-3 | trace_cmd 挂 M00.F02 + 设计映射行 + 全门绿 + push + gitlink | 完成（2026-09-29，trace 69 测试 / 35 ID） |

## 5. 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 树行写「按 currentTenantId 直进」但生成层 LoginResponse 无 currentTenantId 字段 | **不冲突**：currentTenantId 是 CurrentUserSession（会话快照）契约字段（生成物在），登录响应里没有→由 settle 落账写进快照；activeTenantId defaults 键是记忆载体（家族 TOKEN_STORAGE_KEYS.activeTenantId 同义）。家族 settle 用 remembered ?? single ?? first 而非响应字段，iOS 同款 | 自裁（契约事实非语义分歧） | 2026-09-29 |
| Q2 logout 是否清 activeTenantId（家族行为未核） | **清**（声明语义）：会话级状态不跨登录；家族 SSO 路径待 M01.F05.I03 时再对齐 | 自裁 | 2026-09-29 |

## 6. 附注

- 存档：`.state/tree-change.json`（approved=true，base_sha 9c6059b0d0f0b367）
- 家族参照：`output/lab-management-system-react/src/state/auth-context.tsx`
  settleLogin（2026-09-23 用户裁定注释在案）
- 关联 REQ-2026-003（I01 切换器已上线路径收尾）；ADR-0019 口径：activeTenantId
  是用户显式选择的会话 UI 态，落 UserDefaults 非身份兜底

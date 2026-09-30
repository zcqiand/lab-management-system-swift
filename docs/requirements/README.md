# requirements/

一份需求一个文件：`REQ-YYYY-NNN-<短标题>.md`。

## 需求台账

| 需求 ID | 标题 | 优先级 | 状态 | 影响功能数 |
|---|---|---|---|---|
| REQ-2026-001 | M03.F01 接样管理（SwiftUI iOS 首个功能切片） | P0 | 已上线 | 1 F（7 I） |
| REQ-2026-002 | M03.F01 UI 壳（SwiftUI 页面全套 + trace 挂 ID） | P1 | 已评审 | 1 F（6 I） |
| REQ-2026-003 | 登录 UI（shared 契约先行 + 登录/账户/租户切换） | P1 | 已上线 | 6 I |
| REQ-2026-004 | M03.F02 任务分配（队列 + 安排/取消 + act 三动作） | P1 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 3 I |
| REQ-2026-005 | M03.F03 数据录入（录入页 + 保存记录 + verdict 改判 + act 三动作） | P1 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 4 I |
| REQ-2026-006 | M03.F05~F08 报告四阶段（四队列 + 操作按钮 + act 三动作 ×4） | P1 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 12 I |
| REQ-2026-007 | M03.F09 接样单详情（全字段表 + 时间线双挂 + 数据面报告预览） | P1 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 3 I |
| REQ-2026-008 | M03.F01.I07 样品扩展属性补录（预览前补录门 + 四型控件 + PUT ext） | P2 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 1 I |
| REQ-2026-009 | M00.F02 登录选租户直进（activeTenantId settle 落账 + 记忆/hydrate/清除） | P2 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 1 F |
| REQ-2026-010 | M01.F05.I03 SSO OAuth 2.0 授权码流原生形态（ASWebAuthenticationSession + state 防 CSRF） | P2 | 已上线（2026-09-30 人工验收通过，ACCEPTANCE-2026-09-29-ready-batch） | 1 I |

## 方向定死

- **需求文档**记录「这次动了哪些功能」（流水）
- **功能清单**记录「系统现在有哪些功能」（余额）

不要在余额表里记流水。

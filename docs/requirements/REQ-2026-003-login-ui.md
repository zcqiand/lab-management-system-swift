# REQ-2026-003 登录 UI（shared 契约先行 + SwiftUI 登录/账户/租户切换）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-28 |
| 优先级 | P1 |
| 状态 | **已评审**（三项裁决 + Q4=A+B+C 全做，2026-09-28；第一段待开工） |
| 关联 ADR | — |
| 上游 | REQ-2026-001 Q1（手动配置页是临时解）；家族 SSO 现行（react 树的 SSO 子项，2026-09-17 起密码登录废弃） |

## 1. 需求描述

**用户原话**（2026-09-28，三项裁决）：

> 登录方式 = shared 先增加功能；token 存储 = Keychain（推荐项被选）；租户 = 默认租户+账户页切换（推荐项被选）

**背景**：

- M03 各环节 act 的操作人目前靠用户逐次显式输入（REQ-2026-002 的 ADR-0019 临时解），
  F02 任务分配之后的报告流必须用真会话身份——登录是前置。
- 家族现行认证 = SSO 授权码流；**密码登录端点在 shared `auth.tsp` 已废弃**
  （2026-09-17 注释：op 暂留待消费仓同步后删）。iOS 登录不能建在待删端点上。
- shared 的 SSO 形制是 **web 浏览器假设**：state 存 HttpOnly Secure cookie、后端对
  cookie 校验（`SsoCallbackRequest` 注释）；原生 app（ASWebAuthenticationSession）
  在 dev http 后端上 cookie 不可靠（家族已有「state cookie 按 host 分档」先例）。
  这就是「shared 先增加功能」的落点：**先在 shared 仓补原生流契约支持，本仓再消费生成物落 UI**。

**范围**（两段，第一段是第二段的前置）：

- **第一段（shared 仓）**：SSO 原生流契约增补（Q4 裁定 A+B+C 全做）：
  - **A** state 验证双轨：cookie 之外支持服务端签发记录的一次性校验（ssoAuthorize 返回的 state 后端本就签发，可存服务端记录对账，解决 dev http 下 cookie 不落盘）
  - **B** redirect_uri 白名单放行自定义 scheme（`labmanagement://callback` 形态）——saas/lab 后端校验与部署配置，shared 侧注释明确
  - **C** 新增非浏览器原生登录端点（如 `/auth/native-login`，示例名，开工定）：原生表单提交用户名+密码 → 直接返回 lab JWT + refreshToken。与已废弃的密码登录对表：这是**为原生客户端新开的通道**，非恢复 web 密码端点
- **第二段（本仓）**：
  - `gen-shared.sh` 重生成（API 面只认生成物，§4）
  - 配置页瘦身：只收 baseURL（显式注入不变）；token 字段退役——token 由登录产出
  - SessionStore 存储缝抽象：token/refreshToken 进 **Keychain**，UserDefaults 只留非敏感 baseURL
  - 登录页：**原生 SwiftUI 表单**（用户名+密码 → 原生登录端点换 lab JWT）；ASWebAuthenticationSession SSO 流（A+B 支撑）登记为规划子项，后续需求消费
  - 失效处理：401 拦截 → 跳登录页（对齐 react 树的「Token 注入与失效跳登录」）
  - 账户页：当前用户 + 租户展示；租户切换走 switchTenant 换发 token，切换后列表整表刷新
  - 登出：logout + Keychain 清空 → 回登录页

### 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 登录方式：家族现行是 SSO（密码登录已废弃），iOS 走哪条路？ | **shared 先增加功能**——不搭待删的密码端点；原生 SSO 支持从 shared 契约层起步。 | zcqiand | 2026-09-28 |
| Q2 token 存哪？ | Keychain；SessionStore 存储缝抽象化，UserDefaults 只留 baseURL 等非敏感配置。 | zcqiand | 2026-09-28 |
| Q3 租户做到什么程度？ | 登录后按会话 currentTenantId 直进；账户页留切换入口（对齐 react 树的「登录选租户」子项），多租户账号才可见。 | zcqiand | 2026-09-28 |
| Q4 **shared 增补范围**： | **裁定 A+B+C 全做**（zcqiand 2026-09-28）：A state 验证双轨（cookie 之外支持服务端签发记录一次性校验，解决 dev http 下原生 app cookie 不落盘）；B redirect_uri 白名单放行自定义 scheme（`labmanagement://callback` 形态）；C 新增非浏览器原生登录端点（原生表单换 lab JWT）。登录页形态定为**原生 SwiftUI 表单**；ASWebAuthenticationSession SSO 流登记规划子项后续消费。C 端点与已废弃密码登录对表：为原生客户端新开通道，非恢复 web 密码端点。 | zcqiand | 2026-09-28 |

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | shared 增补落地 | 跑 shared 仓与全家族门 | shared gate 绿；全消费仓 codegen 幂等绿（硬规则 §2：契约改动同 commit 同步 contract-test 断言） |
| AC-2 | 本仓冷启动、无会话 | 呈现登录页 | 原生表单提交 → 原生登录端点换 lab JWT 进列表页；token/refreshToken 仅存 Keychain |
| AC-2b | 本仓冷启动、无会话 | （后续需求）SSO 原生流 | A+B 契约支撑已落地；SwiftUI 侧 ASWebAuthenticationSession 消费登记为规划子项 |
| AC-3 | baseURL 未配置 | 启动 | 配置页只收 baseURL（无 token 输入框）；配置后进登录页 |
| AC-4 | token 失效/后端 401 | 任意 API 调用 | 拦截跳登录页，旧 Keychain 会话清除 |
| AC-5 | 账户页 | 切换租户 | switchTenant 换发新 token；切换后列表整表刷新（家族口径） |
| AC-6 | 已登录 | 登出 | logout 端点调用 + Keychain 清空 → 回登录页 |
| AC-7 | 任意工作树 | 跑 trace_cmd | 登录相关测试挂树中登记的 ID；trace.json 由 trace_cmd 产出 |
| AC-8 | CI 门禁 | 全门 | exit 0（两仓） |

## 3. 任务拆解

| 任务 ID | 任务描述 | 类型 | 仓 | 状态 |
|---|---|---|---|---|
| T-0 | shared `auth.tsp` 增补：**C 原生登录端点**（新 op + DTO）+ **A state 双轨**注释/语义 + **B scheme 白名单**注释 + contract-test 同步断言（硬规则 §2 同 commit） | 契约 | shared + saas/lab 后端 | 待开工 |
| T-1 | shared 门绿 + 全家族消费仓 codegen 重跑幂等 | 契约 | 全家族 | 待 T-0 |
| T-2 | 本仓重生成；SessionStore Keychain 化（存储缝抽象，red-first）；配置页瘦身 | 实现 | 本仓 | 完成 |
| T-3 | 登录页（原生 SwiftUI 表单）+ 401 拦截跳登录 + 账户页 + 租户切换 + 登出 | 实现 | 本仓 | 完成 |
| T-4 | 功能树 tree-change 登记（提案已备，待人批准）+ trace 挂 ID + 全门绿 + `/handoff` | 收尾 | 本仓 | 待 T-3 |

## 4. 功能影响

> **ID 未登记**：本仓功能树当前 M03-only（REQ-2026-001 范围裁剪）。登录相关功能 ID 按
> 「react 树编号对齐，不另起编号」走 **tree-change 提案**，评审批准拿到 ID 后回填本表。
> 拟登记（编号对齐 react 树）：租户管理/认证管理两模块 + 会话、租户切换、Token 注入与失效跳登录、
> SSO（原生形态）、登出，以及**新增原生登录子项（react 树该功能段用到第 5 号，号不回收，取下一号）**。
> **2026-09-28 tree-change 已批**：上表 ID 已登记（shared 侧同批登记 native-login 端点行 M01.F05.I06）。
> Q4-C 裁定后，登录页形态 = 原生表单（新子项），SSO 原生流登记规划行后续需求消费。

| 功能 ID | 功能名称 | 影响类型 | 说明 | 关联任务 |
|---|---|---|---|---|
| M00.F01 | 当前用户会话 | 新增 | 账户页 + 会话恢复 | T-3 |
| M00.F02.I01 | 租户切换 | 新增 | 账户页 switchTenant | T-3 |
| M01.F05.I02 | Token 注入与失效跳登录 | 新增 | 401 拦截 + Keychain | T-2、T-3 |
| M01.F05.I06 | 原生登录（非浏览器表单） | 新增 | 登录页主路径（Q4-C） | T-3 |
| M01.F05.I04 | 登出 | 新增 | 登出按钮 + Keychain 清空 | T-3 |
| M01.F05.I03 | SSO 授权码流（原生） | 新增 | A+B 契约支撑；SwiftUI 消费后续需求 | — |

## 5. 流程影响

无既有流程步骤引用；新增登录流程时随 T-4 补 flow-function-map。

## 6. 风险与回滚

| 风险 | 影响面 | 缓解 | 回滚方式 |
|---|---|---|---|
| R1 shared 契约变更波及全家族 | 9 仓 | 硬规则 §2 同步断言同 commit；codegen 全仓重跑幂等门；先 saas 后 lab 分批迁移 | shared tsp revert + 生成物回退 |
| R2 dev http 后端 cookie 缝 | T-0（shared 侧） | Q4-A 双轨 state 即为此设计；shared 增补后 dev 联调 cookie 缝消除 | shared tsp revert + 生成物回退 |
| R3 Keychain 在模拟器/CI 的行为差异 | T-2 | swift test 用注入存储缝的 fake，Keychain 实现只在 App target 绑定层 | — |
| R4 原生登录端点与家族「密码登录已废弃」决策的观感冲突 | T-0 | C 裁定已明确「为原生客户端新开通道，非恢复 web 密码端点」；shared tsp 注释写清这个边界，防后人误读为废弃决策回滚 | shared tsp revert |

# REQ-2026-010 SSO OAuth 2.0 授权码流原生形态（M01.F05.I03）

| 项 | 值 |
|---|---|
| 提出人 | zcqiand |
| 提出日期 | 2026-09-29 |
| 优先级 | P2 |
| 状态 | **开发中**（T-0 完成 2026-09-29；tree-change 已批，sha 44f760fcb787cbd0） |
| 关联 ADR | ADR-0019（client_id/回调 scheme 用户显式配置，缺失 fail-fast 不兜底字面量） |
| 上游 | REQ-2026-003（登录 UI）、REQ-2026-009（settle 直进复用）；树行既定「后续需求」入队 |

## 1. 需求描述

**背景**：

- 家族 react LoginPage 已上线 SSO（RFC 6749 §4.1 两阶段）：authorize
  （response_type=code + client_id + redirect_uri + state 防 CSRF）→
  SsoRedirect.authorizeUrl 跳 IdP（saas）→ 回跳验 state（一次性）→
  sso/callback（grant_type=authorization_code 四字段）换 lab 自家 JWT →
  LoginResponse → settle 进业务页。
- iOS 原生形态（树行既定）：ASWebAuthenticationSession 消费 authorizeUrl，
  回跳自定义 scheme 回调；client_secret 仅后端持有，saas token 不出 lab 后端。
- **契约零改动**：生成物 AuthAPI.authSsoAuthorize / authSsoCallback、
  SsoRedirect{authorizeUrl, state}、SsoCallbackRequest{grantType, code,
  redirectUri, state}、OAuthResponseType.code、
  OAuthGrantType.authorizationCode、BackendFeatures.sso 全在。

**范围**：

| 关注点 | 内容 |
|---|---|
| CoreKit | SsoViewModel：authorize / exchange / openWebSession 三缝注入；state 生成（32 字节 base64url）与一次性校验为纯函数；state 不匹配不打 exchange；config 缺失 fail-fast；成功走 store.adoptLogin（settle 直进复用 REQ-2026-009） |
| SessionStore | ssoClientId / ssoCallbackScheme 显式配置落账（saveSsoConfig 空值拒存；重启恢复；logout 保留、clear 全清） |
| App | LoginView「SSO 登录」按钮 + ASWebAuthenticationSession（AuthenticationServices，prefersEphemeral）+ Info.plist CFBundleURLTypes 注册回调 scheme + ConfigView SSO 配置字段（client_id / 回调 scheme） |

**非范围**：saas 端 redirect 白名单注册 iOS scheme（oauth_client 数据变更，
跨仓协调人裁，ADR-0029 精神）；refresh token 自动续期（authRefresh 端点
本期不接）；saas 端 single logout；web 端 `?from=` 深链恢复语义（iOS 无
对应物）。

## 2. 验收标准

| 编号 | 场景（给定） | 操作（当） | 预期（则） |
|---|---|---|---|
| AC-1 | SSO 配置齐（client_id + 回调 scheme） | 点「SSO 登录」 | authorize → 浏览器会话跳 IdP → 回跳换 JWT → ready 直进业务页 |
| AC-2 | 回跳 state 与发出 state 不一致 | 落回 App | 拒绝换 token，报「state 校验」失败态，不打 exchange 端点 |
| AC-3 | SSO 配置缺失（空 client_id/scheme） | 点「SSO 登录」 | fail-fast 报配置缺失，不发 authorize / 不开浏览器会话 |
| AC-4 | callback 换 token 失败（后端错/INVALID_GRANT） | 落回 App | 报失败态不进会话，可重试 |
| AC-5 | SSO 成功多租户账号 | 落回 App | 走 settle 直进（REQ-2026-009 同款） |

## 3. 任务拆解

| 任务 | 内容 | 状态 |
|---|---|---|
| T-0 | tree-change 提案：M01.F05 父行 + I03 规划→开发中；REQ 台账行 | 完成（2026-09-29 批准） |
| T-1 | CoreKit 红先行：SsoViewModel（三缝 + state 纯函数 + fail-fast）+ SessionStore.saveSsoConfig | 完成（远端 test 91/91 绿，真红实证 cannot find SsoViewModel ×10 + no member saveSsoConfig） |
| T-2 | App：LoginView SSO 按钮 + ASWebAuthenticationSession + Info.plist scheme + ConfigView 字段 | 完成（WebAuthSession.swift prefersEphemeral；CFBundleURLTypes 注册 labman） |
| T-3 | trace_cmd 挂 I03 + 设计映射行 + 全门绿 + push + gitlink | 进行中 |

## 4. 功能影响

| 功能 ID | 影响类型 | 说明 |
|---|---|---|
| M01.F05 | 变更 | 父行 规划→开发中（I02/I04/I06 在册，SSO 补齐收口） |
| M01.F05.I03 | 变更 | 既有行「后续需求」入队，规划→开发中，落地实现；接口/表不变 |

## 5. 澄清记录

| 疑问 | 澄清结论 | 澄清人 | 日期 |
|---|---|---|---|
| Q1 client_id 来源：家族 env 注入 vs iOS 端配置 | **ConfigView 用户显式配置**（SessionStore 落账，ADR-0019 口径）：iOS 无构建期 env 注入惯例，家族注释亦证后端权威持有、前端值被忽略——客户端只须传库值 'lab-management' 形态的字符串 | 自裁（ADR-0019 既定口径推演，非语义分歧） | 2026-09-29 |
| Q2 iOS 回调 redirect_uri 如何过 saas 白名单 | **已批并落地（2026-09-29 人裁「协调 saas 仓注册」）**：saas-shared d294477 + saas-nextjs 92af9e4 种子登记 `labman://oauth/callback`，saas_dev 已重灌入库实证；契约零动（redirectUris 是数据字段） | 人裁（zcqiand 批准跨仓数据变更） | 2026-09-29 |

## 6. 附注

- 存档：`.state/tree-change.json`（approved=true，base_sha 44f760fcb787cbd0）
- 家族参照：`output/lab-management-system-react/src/pages/LoginPage.tsx`
  （阶段 1 验 state 一次性 / 阶段 2 authorize 跳转；state 生成 base64url 32 字节）
- 真后端联调前置：saas 白名单注册（Q2）；msw/真后端 BackendFeatures.sso 均 true

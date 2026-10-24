# 实验室管理系统 · SwiftUI iOS 前端

实验室管理系统的 SwiftUI iOS 前端 —— **仅 M03 实验过程管理**。需求与 API 基线 = `lab-management-system-shared` TypeSpec SSOT；react 仓仅为 UI/交互参照实现。

本仓**不绑书稿**：技术栈基线（Xcode 16.2 + Swift 6.0 + iOS 18 SDK，受构建机 Intel Air / macOS 14.5 天花板约束）。API 面只认 `lab-management-system-shared` TypeSpec 生成物（openapi.yaml → Swift client），后端可在 nextjs / springboot / aspnetcore 之间切换。

## 快速开始

```bash
# 本机 Windows：无 Swift 工具链，只有 suite 门禁（L0/L5）
python scripts/gate.py -p lab-management-system-swift   # 在 suite 根目录跑

# 真构建在构建机 home-mac（Tailscale）：Xcode 16.2 + Swift 6.0
git push && ssh home-mac "git -C <仓路径> pull && swift build && swift test"
```

## 功能特性

范围裁剪（2026-09-27）：本仓只做 **M03 实验过程管理**（接样 → 任务分配 → 数据录入 → 审核 → 批准 → 发放 → 归档，8 F）。需求与 API 基线 = shared TypeSpec SSOT；react 仓其余模块不在本仓范围，M/F 编号沿用家族功能树（react 功能树 = shared BASE 双账本）便于跨仓对照（见 `docs/functions/function-tree.md`，全部 `规划`）。

## 技术栈

| 技术 | 版本 |
| :--- | :--- |
| Xcode | 16.2（构建机 home-mac，Intel Air / macOS 14.5） |
| Swift | 6.0 |
| SwiftUI | iOS 18 SDK |
| 门禁档 | generic（L0/L5；L2/L4 待接 home-mac 远程命令） |

> 依赖版本与 `version-lock.json` 的 `version_lock` 一致，不引入 lock 外的库。

## 需求基线

- **需求与 API 基线 = `lab-management-system-shared` TypeSpec SSOT**：行为规格读 `tsp/*.tsp`，API client 只用 shared 仓 `generated/openapi/openapi.yaml` 生成的 Swift 代码（禁手写接口层，suite 硬规则 §4）。
- 范围：仅 M03 实验过程管理 8 F；M/F 编号沿用 react 仓功能树（同 shared BASE 双账本），便于跨仓对照。
- UI/交互参照：`../lab-management-system-react`（参照实现，非基线）。

## 配套书籍及章节映射

> 同一案例仓后续接入其他书籍时，在此节下新增书籍小节。

### 书一《Swift从入门到项目实践》（第二部分）

- 书稿定位：xr-know-013，第 24、25、28、29、30、31 章正文代码块挂本仓 `source=` 锚点
- 配套版本：`v0.1.1-20261004`（registry 冻结 tag，代码以此为准）

| 章 | 章题 | 对应源文件 |
| :--- | :--- | :--- |
| 24 | 列表与导航：接样单列表、详情页与流程时间线 | `Sources/App/ReceiptDetailView.swift` |
| 25 | 表单与校验：新建、编辑与删除接样单 | `Sources/App/ReceiptFormView.swift` + `Sources/App/APIGlue.swift` |
| 28 | 网络请求：URLSession 与 REST API | `Sources/App/APIGlue.swift` |
| 29 | JSON 解析与 Codable 模型 | `Sources/App/APIGlue.swift` |
| 30 | 异步与并发实战 | `Sources/App/APIGlue.swift` |
| 31 | 登录与会话：原生登录、令牌注入与登出 | `Sources/App/LoginView.swift` + `Sources/CoreKit/APIClient.swift` + `Sources/CoreKit/AuthViewModel.swift` |

## 快速链接

- [CLAUDE.md](CLAUDE.md) — 开发约定与编码规范
- [系统架构.md](docs/ARCHITECTURE.md) — 结构 / 边界 / 数据流 / 决策
- [功能规格.md](docs/functions/function-tree.md) — 功能名称、描述与验收标准
- [未来开发计划](PLAN.md) — 待办与迭代方向
- [更新日志](CHANGELOG.md) — 版本变更记录

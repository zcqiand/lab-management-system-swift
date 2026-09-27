// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LabManagementSystem",
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        // swift5 生成器对自由 object（jsonb ext/config 类字段）的硬依赖：
        // 模型属性用 AnyCodable 类型，import 有 canImport 守卫但 usage 没有——
        // 缺包必炸。首次 swift build 需要网络 resolve，之后进本地缓存。
        .package(url: "https://github.com/Flight-School/AnyCodable", .exact("0.6.7")),
    ],
    targets: [
        // shared 契约生成物（openapi-generator swift5，scripts/gen-shared.sh）。
        // 禁手改：改契约 = 改 shared .tsp → 重新 gen-shared。
        // Swift 5 语言模式：生成器 7.24 产物是 Swift 5 并发模型代码
        // （Configuration/Models 带 static 可变单例），Swift 6 严格并发会拒编译。
        .target(
            name: "LabSharedGenerated",
            dependencies: ["AnyCodable"],
            path: "Generated/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // CoreKit：纯 Swift 层（模型 / API client / 业务逻辑）。
        // 铁律：本 target 禁止 import SwiftUI / UIKit —— 必须保持任何 Swift 工具链可编译，
        // 远程门禁 swift build/test 直接锁它。
        .target(name: "CoreKit", dependencies: ["LabSharedGenerated"]),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
    ]
)

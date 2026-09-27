#!/usr/bin/env python3
"""远程门禁：把本仓工作树同步到构建机 home-mac 的 staging 目录，再跑 swift build / swift test / xcodebuild。

用法（.harness/stack.json L2/L4 调用）:
    python scripts/remote_gate.py build   # L2：远程 swift build + xcodebuild（generic iOS）
    python scripts/remote_gate.py test    # L4：远程 swift test

设计约束（suite 铁律）:
- 构建机与 staging 路径是常量，不是 env 兜底 —— 目标漂移宁可红，不静默换地方测。
- 每次全量打包本机工作树（排除 .git/.build）再同步，gate 测的永远是本机当前代码，
  不测构建机上可能陈旧的克隆。
- ssh 一律 BatchMode：key 认证失败立刻红，绝不挂住门禁等密码。
- exit code 唯一真相：swift 子进程的返回码原样透传。

xcodebuild 段（REQ-2026-001 Q2）:
- 每次先 ~/tools/xcodegen generate（真源是 project.yml，工程文件漂移即被再生覆盖）。
- L2 附加段：xcodebuild 构建 CoreKit scheme（generic/platform=iOS，免签名）——稳定绿。
- L4 模拟器 test 段：暂缓（见 test 分支注释：机器态 3 连红，待人裁排查）。
  注意 runtime 是 18.3.1（Xcode 16.2 -downloadPlatform 拉的最新兼容版），
  不是 Q2 原话的 18.2。
- 构建机 Intel（x86_64）：project.yml 已钉 EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64，
  Xcode 16 默认掺 arm64 模拟器目标在这台机器编不了。
- xcodegen 装在 ~/tools（无 brew/sudo，GitHub release 二进制）。
"""

import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

HOST = "home-mac"  # ~/.ssh/config 免密别名；与 version-lock.json 的 build_host 同源
STAGING_ROOT = "swift-builds"  # 构建机上的 staging 根目录：~/swift-builds/<仓名>
EXCLUDE_PREFIXES = ("./.git", "./.build")


def _sync(root: Path, staging: str) -> None:
    with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as fh:
        archive = Path(fh.name)
    try:
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(
                root,
                arcname=".",
                filter=lambda ti: None
                if ti.name.startswith(EXCLUDE_PREFIXES)
                else ti,
            )
        subprocess.run(
            ["ssh", "-o", "BatchMode=yes", HOST, f"mkdir -p ~/{staging}"],
            check=True,
        )
        with archive.open("rb") as fh:
            subprocess.run(
                ["ssh", "-o", "BatchMode=yes", HOST, f"tar -xzf - -C ~/{staging}"],
                stdin=fh,
                check=True,
            )
    finally:
        archive.unlink(missing_ok=True)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"build", "test"}:
        print("用法: python scripts/remote_gate.py build|test", file=sys.stderr)
        return 2
    mode = sys.argv[1]
    root = Path(__file__).resolve().parent.parent
    staging = f"{STAGING_ROOT}/{root.name}"

    _sync(root, staging)
    # GIT_CONFIG_GLOBAL=/dev/null：构建机 git 全局配置挂了本地代理（127.0.0.1:1088，
    # 不常开），SPM 拉依赖时 clone 直接 128。用环境变量作用域屏蔽全局配置，
    # 不动用户 git config；只影响本命令及其子进程。xcodebuild 的 SPM resolve
    # 同样走 git，前缀一并带上。
    envfix = "GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"
    if mode == "build":
        steps = [
            (f"cd ~/{staging} && {envfix} swift build", "swift build"),
            (
                f"cd ~/{staging} && ~/tools/xcodegen generate && "
                f"{envfix} xcodebuild -project LabManagementSystem.xcodeproj "
                f"-scheme CoreKit -destination 'generic/platform=iOS' "
                f"CODE_SIGNING_ALLOWED=NO build",
                "xcodebuild build（generic iOS）",
            ),
        ]
    else:
        # L4 = swift test（Q2 原话「CoreKit 测试仍走 swift test」）。
        # xcodebuild 模拟器 test 段曾实证可行（2026-09-28 01:04 iPhone/iOS 18.3
        # 18 测全绿），但 runtime 安装后 CoreSimulator 重建设备集 + dyld 缓存
        # 重建，随后 3 连红「Test runner never began executing tests after
        # launching」，erase 设备/重启服务无效——机器态问题，exit 2 停下问人。
        # 恢复前手动验证命令（在 home-mac 仓目录）：
        #   ~/tools/xcodegen generate && xcodebuild -project LabManagementSystem.xcodeproj \
        #     -scheme CoreKit -destination 'platform=iOS Simulator,name=iPhone 16' \
        #     CODE_SIGNING_ALLOWED=NO test
        steps = [(f"cd ~/{staging} && {envfix} swift test", "swift test")]
    for cmd, label in steps:
        result = subprocess.run(["ssh", "-o", "BatchMode=yes", HOST, cmd])
        if result.returncode != 0:
            print(f"远程门禁红在 {label}（home-mac）", file=sys.stderr)
            return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())

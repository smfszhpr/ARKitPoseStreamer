# 用 GitHub Actions 编译 IPA（无 Mac）

适用于本仓库 `ARKitPoseStreamer`。免费 Apple ID 7 天授权过期后，用这个流程重新生成 IPA → 用 Sideloadly 在 Windows/iPhone 重装。

## 一次性准备

1. 把本仓库 push 到 GitHub（公开仓库免费，私有仓库 GitHub Free 每月也有免费 macOS runner 分钟数）
2. workflow 文件已就位：[.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml)

## 每次重新出 IPA

1. 打开 GitHub 仓库网页 → `Actions` 标签 → 左侧选 `Build unsigned iOS IPA`
2. 右上 `Run workflow` → 选分支 → `Run workflow`
3. 等 5–10 分钟跑完
4. 点进刚跑完的那次 → 页面底部 `Artifacts` 里下载 `ARKitPoseStreamer-unsigned-ipa.zip`
5. 解压得到 `ARKitPoseStreamer-unsigned.ipa`
6. Windows 上打开 Sideloadly，登录 Apple ID，把 ipa 拖进去，连 iPhone → Start，即装即用（7 天后再重跑一次本流程）

## 与 GPT 模板的差异（已在 workflow 里改好）

| 项 | 模板 | 本项目 |
|---|---|---|
| 项目类型 | `-workspace YourApp.xcworkspace` | `-project ARKitPoseStreamer.xcodeproj`（没用 CocoaPods）|
| scheme | `YourScheme` | `ARKitPoseStreamer` |
| CocoaPods | `pod install` | 不需要，已删 |
| iOS 部署目标 | 默认 | 项目里写的是 iOS **26.4**，GitHub `macos-latest` 还没那么新；用 `IPHONEOS_DEPLOYMENT_TARGET=17.0` 覆盖编出能跑在 iOS 17+ 设备上的二进制 |
| `DEVELOPMENT_TEAM` | 不带 | 显式置空，避免 xcodebuild 因为找不到团队证书报错 |
| artifact 名 | YourApp | ARKitPoseStreamer |

## 这种"不签名 ipa"会有什么坑？

App 用到的能力：
- ARKit ✅（标准能力，免费 Apple ID 可用）
- 局域网 UDP ✅（同上）
- 相机权限 ✅（Info.plist 已声明，用户首次启动同意即可）

**没有**用 Push Notification / iCloud / App Groups / Associated Domains / HealthKit / NFC / Sign in with Apple 等需要付费开发者账号的能力，所以这条免费路径完全没问题。

## 如果 workflow 失败

最可能的两个原因：
1. **找不到 iOS 26 SDK** —— `macos-latest` 的 Xcode 版本太老。把 `runs-on: macos-latest` 改成 `runs-on: macos-15` 试试更老的镜像；或者如果 Apple 又升级了 runner，可改成 `macos-26`。覆盖 deployment target 是关键。
2. **`xcpretty` 没装报错** —— workflow 里加了 `|| true` 容错，xcodebuild 真正失败仍会被 set -o pipefail 捕获。

跑失败时去 Actions 页打开那次 run 的日志，把 `Build .app` 步骤的红色报错贴回来即可定位。

## 仓库本地变更（已做）

```
.github/workflows/build-ipa.yml   ← 新增
```

不影响 Xcode 本地构建。

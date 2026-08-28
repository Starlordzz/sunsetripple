# HarmonyOS NEXT 构建说明

`harmonyos/` 是一套**独立的原生 ArkTS 实现**（不是 Flutter-ohos 移植），
需用 DevEco Studio 构建。CI 只做工程校验与源码打包，**不产出 `.hap`**。

## 为什么 CI 不产出 .hap

### 1. 真 HAP 不是 zip

一个可安装的 HAP 需要 hvigor 完成这些步骤：

- ArkTS（`.ets`）编译成 `.abc` 字节码
- restool 把 `resources/` 编译成二进制 `resources.index`
- `module.json5` → `module.json`（去注释、去 json5 语法）
- 生成 `pack.info`
- 用证书签名

历史版本（≤ v0.1.0-alpha.8）的 CI 只是把 `ets/` 源码、`module.json5`
和 `resources/` 打了个 zip 改名成 `.hap`，产物 13 KB。这个文件
`hdc app install` 会直接拒绝，已从发布流程中移除。

### 2. 工具链拿不到

DevEco 命令行工具与 HarmonyOS SDK 需华为开发者账号登录后才能下载，
没有可供公共 CI 直接拉取的公开地址。

### 3. 签名绕不过

鸿蒙 NEXT 零售机只接受两种签名的 HAP：

- **AGC 调试证书**——需在 AppGallery Connect 登记设备 UDID，上限 100 台
- **应用市场发布签名**——需通过华为审核上架

不存在「未签名侧载」这条路（不同于 Android 的直接安装，也不同于 iOS
可用第三方工具重签）。所以即便解决了前两点，也做不出「下载即装」的包。

## 本地构建步骤

1. 安装 DevEco Studio 5.0 及以上（对应 `compatibleSdkVersion 5.0.0(12)`）
2. 打开 `harmonyos/` 目录，IDE 会自动生成 hvigor wrapper
   （`hvigorw`、`hvigor/hvigor-wrapper.js`）并执行 `ohpm install`
3. 在 AppGallery Connect 创建应用，`bundleName` 填
   `host.msknet.sunsetripple`
4. 申请调试证书（`.p12`）与调试 Profile（`.p7b`），登记目标设备 UDID
5. `File > Project Structure > Signing Configs` 填入证书，
   或直接写进 `build-profile.json5` 的 `signingConfigs`
   （当前该数组为空）
6. `Build > Build Hap(s)/APP(s) > Build Hap(s)`
7. `hdc app install entry/build/default/outputs/default/entry-default-signed.hap`

## CI 校验了什么

`package-harmonyos` job 会在打包前检查这类会让 hvigor 直接失败的问题：

- `app.json5` / `module.json5` 里所有 `$media:` `$string:` `$color:`
  `$profile:` 引用是否都有对应资源文件
- hvigor 构建入口文件是否齐备（`build-profile.json5`、`oh-package.json5`、
  `hvigorfile.ts`、`hvigor/hvigor-config.json5`）
- `AppScope/app.json5` 的 `versionCode` 是否与 `pubspec.yaml` 的
  build number 对齐

加这些校验的直接原因：v0.1.0-alpha.8 时 `$media:app_icon` 被引用 3 次，
而整个 `harmonyos/` 目录**没有 `media/` 目录**——真构建会立刻失败，
但因为 CI 只做 zip，这个问题一直没被发现。同期 `versionName` 还停在
`0.1.0-alpha.7`、`versionCode` 停在 8，与 Flutter 侧脱节。

## 与 Flutter 核心的关系

`harmonyos/entry/src/main/ets/` 下是**手写的第二套实现**，
协议编解码（`model/Frame.ets`）、会话状态机（`session/HarmonyRoomSession.ets`）、
发现（`transport/LanRoomDiscovery.ets`）都与 Dart 侧平行维护，
存在漂移风险。修改 `lib/core/protocol/` 时需同步检查
`harmonyos/entry/src/main/ets/model/Frame.ets`。

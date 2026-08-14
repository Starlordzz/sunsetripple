# 落日后残波（SunsetRipple）

Android 近场语音对讲应用。当前 `0.1.0-alpha.1` 提供 WiFi Direct 全双工房间与蓝牙按住说话房间，面向小范围、无互联网场景。

## 当前能力

- WiFi Direct：无需路由器，最多 6 台设备，全双工语音。
- 蓝牙 RFCOMM：最多 6 台设备，按住说话（PTT）。
- 普通成员短暂断线后自动重连并保留成员身份。
- 通信音频模式、音频焦点、只听模式、前台服务、WakeLock 与 WifiLock。
- 固定竖屏，以及与应用图标一致的夕照波纹界面。

Nearby 房与锁屏通知交互不属于当前 alpha 范围。

## 系统要求

- Android 8.0（API 26）或更高版本。
- WiFi Direct 房需要设备支持 WiFi P2P。
- 蓝牙房需要设备支持经典蓝牙 RFCOMM。
- 创建或加入房间时需要麦克风及对应的附近设备权限。

## 开发验证

项目使用 JDK 17。Windows PowerShell：

```powershell
$env:JAVA_HOME='D:\LEARNING\tools\jdk-17'
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

## 发布签名

首次发布前，在 Git Bash 中运行签名向导：

```bash
bash scripts/setup-release-signing.sh
```

向导会在本地生成 `release/sunset-ripple-release.p12` 与 `keystore.properties`。两者均被 Git 忽略，不得提交或丢失；后续版本必须持续使用同一密钥。

生成签名后构建 APK 与 Android App Bundle：

```powershell
$env:JAVA_HOME='D:\LEARNING\tools\jdk-17'
.\gradlew.bat :app:testDebugUnitTest :app:lintRelease :app:assembleRelease :app:bundleRelease
```

产物位于：

- `app/build/outputs/apk/release/app-release.apk`
- `app/build/outputs/bundle/release/app-release.aab`

可通过 `-PsunsetRipple.signingProperties=<绝对路径>` 使用 CI 或临时签名配置。

## 已知限制

- 房主退出会结束房间，尚不支持自动转移房主。
- Nearby 房当前隐藏且不再验收。
- 锁屏通知显示与通知按钮交互当前不保证可用。
- 本版本为 alpha，正式稳定版前仍需完成多机真机验收。

完整变更记录见 [CHANGELOG.md](CHANGELOG.md)。

# 落日后残波（SunsetRipple）

Android 近场语音对讲应用。当前 `0.1.0-alpha.1` 提供 WiFi Direct 全双工房间与蓝牙按住说话房间，面向小范围、无互联网场景。

## 当前能力

- WiFi Direct：无需路由器，最多 6 台设备，全双工语音。
- 蓝牙 RFCOMM：最多 6 台设备，按住说话（PTT）。
- 普通成员短暂断线后自动重连并保留成员身份。
- 房主主动离房，或房主进程崩溃、被系统终止、主链路断开且普通重连耗尽时，自动把房主转给仍在线且最早入房的成员。
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

发布签名配置与密钥仅保存在本地，不进入版本库。`keystore.properties` 与密钥文件均被 Git 忽略；后续版本必须持续使用同一密钥。

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

- 异常接管依赖客户端已收到最新快照；房间刚建立即断电、所有候选设备同时离线或无线环境完全隔离时无法恢复。
- WiFi 房转移需要重建 WiFi Direct 组，期间语音会短暂中断，系统可能再次显示连接确认。
- Nearby 房当前隐藏且不再验收。
- 锁屏通知显示与通知按钮交互当前不保证可用。
- 本版本为 alpha，WiFi 与蓝牙的连续 A→B→C 房主转移仍需完成多机真机验收。

完整变更记录见 [CHANGELOG.md](CHANGELOG.md)。

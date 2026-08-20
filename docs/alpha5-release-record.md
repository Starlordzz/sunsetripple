# Alpha 5 发布记录

日期：2026-08-18

## 发布结果

- 版本：`0.1.0-alpha.5`（versionCode 6）
- Tag：`v0.1.0-alpha.5`
- 发布页：https://github.com/Starlordzz/sunsetripple/releases/tag/v0.1.0-alpha.5
- 合并 PR：https://github.com/Starlordzz/sunsetripple/pull/1
- 合并提交：`0c49259eb2567a3cdd2daa03d5a0fec7ffcf6ac7`
- 发布工作流：https://github.com/Starlordzz/sunsetripple/actions/runs/32109571705
- 工作流结果：成功，耗时 5 分 43 秒

发布附件：

- `SunsetRipple-v0.1.0-alpha.5.apk`
- `SunsetRipple-v0.1.0-alpha.5.aab`
- `update.json`
- `updates-prerelease/update.json` 滚动更新通道

## 已完成范围

- 阶段 0：应用编排与导航状态整理。
- 阶段 1：关于页、GitHub 入口、签名清单、APK 校验和系统安装确认。
- 阶段 2：简体中文与英文资源化及资源一致性测试。
- 阶段 3：持久设备身份、签名握手、AES-GCM 安全核心和设备指纹。
- 阶段 5：音频质量指标、网络质量显示、Baseline Profile 和 Macrobenchmark 模块。
- 阶段 6：连接状态辅助功能、诊断导出和 GitHub Issue 预填。
- GitHub Actions：从版本 Tag 自动构建签名 APK/AAB、生成并签署更新清单、发布 GitHub Release。

## 验证证据

以下本地门禁通过：

```powershell
.\gradlew.bat --no-daemon `
  :app:testDebugUnitTest `
  :app:lintRelease `
  :app:assembleRelease `
  :app:bundleRelease
```

首次远端发版工作流成功完成，已验证：发布 keystore 恢复、更新私钥匹配、Release lint、签名 APK/AAB、`update.json` 上传和滚动更新通道更新。

## 未完成与限制

- 阶段 4 的三机以上真机可靠性矩阵按本次范围跳过，连续交接和锁屏恢复尚未验收。
- 安全核心已发布；WiFi Direct、Bluetooth 和 Nearby transport 的强制端到端加密仍待兼容验证后启用。
- Macrobenchmark 与 Baseline Profile 已发布，真实帧时间和端到端音频延迟仍需在目标设备记录。
- 此版本为 alpha 预发布版本，不代表稳定版发布门槛已满足。

## 发布后发现的问题

真机试用暴露出三个问题，详见 [Alpha 5 已知问题](alpha5-known-issues.md)：

- A5-01：安卓与鸿蒙 4（NEXT 之前）手机在 WiFi 房互相搜不到，跨系统 WiFi 房不可用。**待定位。**
- A5-02：WiFi 搜房界面缺少「重新扫描」按钮（蓝牙搜房页已有）。已修复，待下一版发布。
- A5-03：房内「离开」按钮视觉过暗，看上去像禁用态。已修复，待下一版发布。

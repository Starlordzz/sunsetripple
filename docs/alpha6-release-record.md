# Alpha 6 发布与进度记录

日期：2026-08-20

## 发布结果

- 版本：`0.1.0-alpha.6`（versionCode 7）
- Tag：`v0.1.0-alpha.6`
- 发布页：https://github.com/Starlordzz/sunsetripple/releases/tag/v0.1.0-alpha.6
- 主分支提交：`4cb3504`
- 发布工作流：https://github.com/Starlordzz/sunsetripple/actions/runs/32388038782
- 工作流结果：成功（耗时 5 分 14 秒，已覆盖最新发布附件）

发布附件：

- `SunsetRipple-v0.1.0-alpha.6.apk`
- `SunsetRipple-v0.1.0-alpha.6.aab`
- `update.json`
- `updates-prerelease/update.json` 滚动更新通道

## 本轮解决的问题与完成范围

1. **A5-01 跨系统 WiFi Direct 互搜兼容性修复**：
   - 房主（GO）在 `createGroup()` 建组成功后主动调用 `startHostDiscovery()`（执行 `discoverPeers()`），保持射频芯片在 1/6/11 社交信道上的监听与 Probe Request 应答，解决华为 EMUI / 鸿蒙 4 与标准安卓设备之间双向互搜为空的问题。
   - 补充 `p2pReasonText()` 错误码语义转译（`ERROR` / `P2P_UNSUPPORTED` / `BUSY` / `NO_SERVICE_REQUESTS`）。
   - 增强对端列表变更与连接状态广播日志输出，包含设备名、MAC、状态码与 GO IP 信息。
2. **A5-02 WiFi 搜房页增加「重新扫描」按钮**：
   - `WifiDirectManager` 新增 `discovering: StateFlow<Boolean>`，由 `WIFI_P2P_DISCOVERY_CHANGED_ACTION` 广播驱动。
   - `ScanScreen` 增加「重新扫描」按钮并在扫描中显示禁用态与文案切换，解决系统发现窗口超时后页面定格的缺陷（与蓝牙搜房页拉齐）。
3. **A5-03 房内「离开」按钮对比度过低修复**：
   - 将房内离开按钮从主题槽位 `SoftCoral` 改为固定浅珊瑚红配色，消除深色背景下被误判为 disabled 禁用态的问题。
4. **底层传输层稳定性与离房竞争修复**：
   - 修复 `BluetoothHostTransport` 与 `WifiHostTransport` 中 `dropClient` 在写线程先报错时静默丢弃读线程主动离房（`FrameType.LEAVE`）导致成员被误判为重连中、占用 ID 的竞争问题。
   - 消除多客户端测试套件中的并发握手竞态，保障 CI 高负载下的确定性验证。
5. **工程与文档治理**：
   - 脱敏公开文档中的开发机绝对路径，补齐 `.gitignore` 中的 `*.hprof` 堆转储忽略规则，防止签名私钥泄露。
   - 同步更新 `README.md` 与 Wiki（`Home.md`、`构建与发布.md`）中的版本号与发版指引。

## 验证证据

以下本地门禁全部通过：

```powershell
$env:JAVA_HOME='D:\LEARNING\tools\jdk-17'
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

- **单元测试**：253 个纯 JVM 单元测试全部通过。
- **代码分析**：Lint Debug 无阻塞性警告/错误。
- **打包产物**：Debug APK 与 Release 配置验证通过。
- **远程推送**：`master` 分支与 `v0.1.0-alpha.6` Tag 已同步推送到 GitHub。

## 后续待办与已知限制

- **规划项 1：自动更新下载进度条与大小指示**：
  - 扩展 `UpdateState.Downloading`（包含 `progress: Float`、`downloadedBytes: Long`、`totalBytes: Long`）。
  - `AndroidUpdateService` 下载循环中按字节流读取进度计算百分比并向 `AboutUpdateCoordinator` 回调。
  - `AboutUpdateScreen` 增加 `LinearProgressIndicator`、已下载/总大小（MB）与百分比展示，并在未知总大小时回退至不定进度动画。
- **规划项 2：真机矩阵与互搜验证**：
  - 在 Android ↔ 鸿蒙 4 真机组合上进行 WiFi 房互搜与连接建链现场验收。
  - 连续 A→B→C 房主转移与锁屏状态下后台语音保活真机验证。
- **规划项 3：传输层安全加固**：
  - 传输层强制 AEAD 端到端加密在完成多机与交接兼容性测试后评估开启。

# Alpha 5 已知问题

版本：`0.1.0-alpha.5`（versionCode 6）
记录日期：2026-08-19
来源：真机试用反馈

| 编号 | 概述 | 类型 | 影响 | 状态 |
| --- | --- | --- | --- | --- |
| A5-01 | 安卓与鸿蒙 4（NEXT 之前）手机在 WiFi 房互相搜不到 | 兼容性 | 阻断 | 待定位 |
| A5-02 | WiFi 搜房界面缺少「重新扫描」按钮 | 功能缺失 | 高 | 已修复（未发版） |
| A5-03 | 房内「离开」按钮视觉过暗，像不可点击 | 视觉 | 中 | 已修复（未发版） |

---

## A5-01 安卓与鸿蒙 4 手机在 WiFi 房互相搜不到

### 现象

一台安卓手机与一台鸿蒙 4（HarmonyOS NEXT 之前、仍是 AOSP 框架的版本）手机之间，WiFi 房**双向**都发现不了对方：

- 鸿蒙机建房、安卓机加入 → 安卓机的搜房列表始终为空。
- 安卓机建房、鸿蒙机加入 → 鸿蒙机的搜房列表同样为空。

两台安卓机之间的 WiFi 房此前工作正常，问题只出现在跨系统组合。

### 影响

跨品牌 WiFi 房完全不可用。这是本 App 的主场景（WiFi 房是唯一支持多人和高音质的房型），对持有华为/荣耀鸿蒙 4 机型的用户等同于功能不可用。蓝牙房不受影响。

### 复现步骤

1. 两台手机分别装 alpha5，都开 WiFi、都授予定位/附近设备权限。
2. 一台点「建 WiFi 房」，等待页头提示进入房间。
3. 另一台点「加入 WiFi 房」，停在搜房页观察。
4. 列表持续显示「等待发现」，无设备条目。反向重复同样为空。

### 代码位置

- `app/src/main/kotlin/host/msknet/sunsetripple/transport/wifi/WifiDirectManager.kt:124` `createGroup()` — 房主侧建自治组（autonomous GO），建组后**不再调用 `discoverPeers()`**。
- `app/src/main/kotlin/host/msknet/sunsetripple/transport/wifi/WifiDirectManager.kt:130` `discoverPeers()` — 成员侧发起扫描，无参数、无 channel/listen channel 指定。
- `app/src/main/kotlin/host/msknet/sunsetripple/MainActivity.kt:913` — 点「加入 WiFi 房」时**只调用一次** `discoverPeers()`。
- `app/src/main/kotlin/host/msknet/sunsetripple/transport/wifi/WifiDirectManager.kt:71` — 对端列表完全由 `WIFI_P2P_PEERS_CHANGED_ACTION` 广播驱动，系统不广播就永远是空列表。

### 可疑成因（均未验证，需真机日志确认）

1. **房主侧不参与发现。** 现在房主只 `createGroup()` 建自治组，从不 `discoverPeers()`。原生安卓的 GO 会应答 probe request，所以安卓↔安卓能搜到；部分厂商 P2P 栈要求两端同时处于发现状态才互相可见。这是最省事、也最值得先试的一条。
2. **信道不匹配。** `createGroup()` 未指定工作信道，系统可能落在 5GHz 或某个非社交信道上，而对端扫描只覆盖 2.4GHz 社交信道（1/6/11）。
3. **P2P MAC 随机化 / 设备名策略。** 华为系对 P2P 接口 MAC 与设备名有自己的处理，可能导致 `deviceAddress` 不稳定或设备根本不上报。
4. **鸿蒙侧后台扫描限制。** 系统可能对非系统应用的 P2P 发现有额外的省电或权限限制，需要检查是否被静默拒绝（`ActionListener.onFailure` 的 code）。

### 定位手段

- 两端同时抓 `TransportLog`，看 `discoverPeers` 的 `onFailure(code)` 是否被静默拒（`BUSY=2` / `ERROR=0` / `P2P_UNSUPPORTED=1`）。
- 用系统自带的「WLAN 直连」页面互测：如果系统级也互相搜不到，问题在设备/系统层，不在 App；如果系统能搜到而 App 搜不到，问题在本 App 的发现调用方式。
- 房内「诊断导出」（`diagnostics/DiagnosticExporter.kt`）在进不了房时用不上，只能靠 logcat。

### 修复方向

先做成本最低的一条：房主 `createGroup()` 成功后也周期性 `discoverPeers()`，同时给成员侧加重试（与 A5-02 的「重新扫描」按钮天然合流）。若仍不通，再排查信道与厂商策略。

---

## A5-02 WiFi 搜房界面缺少「重新扫描」按钮

### 现象

WiFi 搜房页只有一个「返回首页」按钮。扫描是进页面时一次性发起的，之后没有任何手段重新触发。安卓的 `discoverPeers` 发现窗口有限（约两分钟后自行停止），窗口过后列表就此定格，用户只能退回首页再点一次「加入 WiFi 房」，而界面上没有任何东西提示需要这么做。

### 影响

放大了 A5-01 的痛感：用户面对空列表无事可做，也无从判断是"还没搜到"还是"已经不搜了"。

### 代码位置

- `app/src/main/kotlin/host/msknet/sunsetripple/ui/ScanScreen.kt:91` — 底部只有 `onBack` 一个 `OutlinedButton`。
- 对照：`app/src/main/kotlin/host/msknet/sunsetripple/ui/BluetoothScanScreen.kt:102` 蓝牙搜房页**已经有**「重新扫描」按钮，带 `discovering` 态禁用与文案切换。两个搜房页行为不一致。

### 修复方向

照搬蓝牙搜房页的做法即可，所需资源已存在：

- 字符串 `R.string.scan_again`（重新扫描）与 `R.string.scanning`（正在扫描）已在 `values/strings.xml:97-98` 和 `values-en/strings.xml` 中定义，无需新增翻译。
- `ScanScreen` 增加 `onScanAgain: () -> Unit` 参数，`MainActivity.kt:1018` 处接 `wifi.discoverPeers()`。
- 建议同时引入扫描中状态：`WifiDirectManager` 目前不暴露"是否正在发现"，需要补一个 `StateFlow`，否则按钮无法像蓝牙页那样做禁用与文案切换。

### 已实施的修复（2026-08-19）

- `WifiDirectManager` 新增 `discovering: MutableStateFlow<Boolean>`，由系统的 `WIFI_P2P_DISCOVERY_CHANGED_ACTION` 广播驱动。取广播而非"调用过 `discoverPeers` 就算在扫"，是因为框架的发现窗口到点自行停止且不通知调用方——那正是本 bug 的成因。`discoverPeers()` 里乐观置位以消除广播到达前的空窗，失败与 channel 断开时回落，`unregister()` 时清零以免卡在"正在扫描"。
- `ScanScreen` 新增 `discovering` 与 `onScanAgain` 参数、底部「重新扫描」按钮（扫描中禁用并切文案），与蓝牙搜房页行为一致。
- 列表计数文案分出四态：扫描中且无设备→`scan_waiting`，扫描中有设备→`scanning_count`，已停止且无设备→**新增** `scan_stopped`，已停止有设备→`nearby_device_count`。
- `wifi_scan_hint`（"扫描中……"）改为仅在 `discovering` 为真时显示，此前发现停止后仍长挂，是误导的一半来源。
- 新增字符串 `scan_stopped`，中英文同步，`ResourceParityTest` 通过。

---

## A5-03 房内「离开」按钮视觉过暗，像不可点击

### 现象

进房后底部工具栏最右侧的「离开」按钮，底色和文字都明显比旁边的「静音」「扬声器」暗一档，看上去是禁用态，给人点不下去的错觉。实际功能正常，点了就能离房。

### 影响

不影响功能，但会让用户在想退出时犹豫、误以为通话中不能离开。属于首次上手就会遇到的观感问题。

### 代码位置

`app/src/main/kotlin/host/msknet/sunsetripple/ui/RoomScreen.kt:556-576`，`RoomToolbarButton` 的 destructive 分支：

| 槽位 | 离开（destructive） | 普通未选中 |
| --- | --- | --- |
| 底色 | 白 5.5% 透明度 | 白 7% 透明度 |
| 图标 | `SoftCoral` | 白 88% |
| 文字 | `SoftCoral` 82% | 白 70% |
| 描边 | `SoftCoral` 46% | 白 16% |

问题的根子是 `SoftCoral` 这个槽位被当成前景色用了。它并不是珊瑚红——白天是米色 `#E8D8D1`，**夜间是深藏蓝 `#22344F`**，本职是底色（搜房页那条提示条的背景就是它，配 `Ink` 文字）。而房内工具栏永远画在 backdrop 渐变的深色一端（白天 `#392832`，夜间 `#101A2E`），昼夜皆然——旁边的普通按钮正因如此才写死 `Color.White` 透明度，没有跟着主题走。

于是：

- **夜间主题**：图标与文字 `#22344F` 画在近黑上，对比度约 1.4:1，基本不可见。这是"暗得像禁用"的主因。
- **白天主题**：前景尚可辨认，但底色 5.5% 比普通按钮的 7% 还淡、文字再叠 82% 透明度，同时压低底色与前景——正好凑齐 Material 表达 disabled 的两个特征。

alpha4 修过同一类 bug（见 CHANGELOG："扫描页提示条、麦克风检查按钮与房内工具栏选中态在深色配色下前景与底色同为深色"），当时漏了 destructive 这一支。

另外按钮独自贴在 `Alignment.CenterEnd`（`RoomScreen.kt:530`），与居中的那组分离，进一步弱化了它的存在感。

### 已实施的修复（2026-08-19）

`RoomScreen.kt` 新增文件内私有常量 `RoomDestructive = Color(0xFFFF9E90)`，一个固定的浅珊瑚红，destructive 的四个槽位全部改取它：

| 槽位 | 修复前 | 修复后 |
| --- | --- | --- |
| 图标 | `SoftCoral`（夜间深藏蓝） | `RoomDestructive` |
| 文字 | `SoftCoral` 82% | `RoomDestructive` |
| 底色 | 白 5.5%（比普通按钮还淡） | `RoomDestructive` 15% |
| 描边 | `SoftCoral` 46% | `RoomDestructive` 62% |

取固定值而非调色板槽位，是与旁边普通按钮写死白色透明度的同一个理由：这块表面昼夜都是深色，颜色不该跟主题走。浅珊瑚红在两套 backdrop 上的对比度都在 7:1 以上，既明确可用，又靠色相而非亮度保持"危险操作"的区分，设计上"降低视觉体量"的原意不变。

按钮贴右的布局未动——它与居中那组分离是刻意的，把颜色推回可用态后已不构成误导。深色主题的真机观感仍需核对。

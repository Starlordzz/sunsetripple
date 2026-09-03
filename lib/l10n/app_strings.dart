import 'package:flutter/material.dart';

/// App-wide typed bilingual strings.
class AppStrings {
  final bool isEn;

  const AppStrings({this.isEn = false});

  static const AppStrings zh = AppStrings(isEn: false);
  static const AppStrings en = AppStrings(isEn: true);

  static AppStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    if (locale == null) return zh;
    return locale.languageCode == 'en' ? en : zh;
  }

  // App & Branding
  String get appName => isEn ? 'SunsetRipple' : '落日后残波';
  String get tagline => isEn ? 'Nearby voice rooms' : '近场语音房';
  String get nicknameLabel => isEn ? 'Your name' : '你的称呼';
  String get nicknamePlaceholder => isEn ? 'Enter a nickname' : '输入昵称';

  // Modes & Descriptions
  String get wifiRoom => isEn ? 'WiFi room' : 'WiFi 房';
  String get wifiDirect => isEn ? 'WiFi Direct' : 'WiFi 直连';
  String get wifiDescription =>
      isEn ? 'Router-free, for multi-person conversation' : '无需路由器，适合多人同时通话';
  String get bluetoothRoom => isEn ? 'Bluetooth room' : '蓝牙房';
  String get bluetoothDescription =>
      isEn ? 'Hold to talk for close-range offline work' : '按住说话，适合无网络的近距离协作';
  String get fullDuplex => isEn ? 'Full duplex' : '全双工';
  String get pttMode => isEn ? 'PTT mode' : '对讲模式';

  // Actions & Buttons
  String get createRoom => isEn ? 'Create Room' : '创建房间';
  String get createWifiRoom => isEn ? 'Create WiFi Room' : '创建 WiFi 房';
  String get createBleRoom => isEn ? 'Create Bluetooth Room' : '创建蓝牙房';
  String get joinRoom => isEn ? 'Join' : '加入';
  String get scanning => isEn ? 'Scanning…' : '正在扫描…';
  String get scanAgain => isEn ? 'Scan again' : '重新扫描';
  String get checkMicrophone =>
      isEn ? 'Check microphone and headset' : '检查麦克风与耳机';
  String get backHome => isEn ? 'Back to home' : '返回首页';
  String get leaveRoom => isEn ? 'Leave room' : '离开房间';
  String get mute => isEn ? 'Mute' : '静音';
  String get unmute => isEn ? 'Unmute' : '开启麦克风';
  String get micOn => isEn ? 'Mic On' : '麦克风开';
  String get speaker => isEn ? 'Speaker' : '扬声器';
  String get earpiece => isEn ? 'Earpiece' : '听筒';
  String get phoneMic => isEn ? 'Phone Mic' : '手机麦';
  String get headsetMic => isEn ? 'Headset Mic' : '耳机麦';

  // Diagnostics & Quality
  String get diagnosticsTitle =>
      isEn ? 'Network & Audio Diagnostics' : '网络与音质诊断';
  String get exportDiagnostics =>
      isEn ? 'Export Diagnostics' : '导出诊断信息 (可附在 Issue)';
  String get copyReport => isEn ? 'Copy Diagnostic Report' : '复制诊断报告';
  String get reportCopied => isEn ? 'Copied to clipboard' : '已复制到剪贴板';
  String get qualityGood => isEn ? 'Good' : '优良';
  String get qualityFair => isEn ? 'Fair' : '一般';
  String get qualityPoor => isEn ? 'Poor' : '较差';

  // Host Election & Transfer
  String get transferHost => isEn ? 'Transfer Host' : '转移房主';
  String get selectNewHost => isEn ? 'Select New Host' : '选择新房主';
  String get transferHostTip =>
      isEn ? 'Tap member avatar or list to transfer host' : '点击头像或下方列表可转移房主';
  String get bluetoothTransferUnsupported =>
      isEn ? 'Host transfer is not supported in Bluetooth rooms' : '蓝牙房暂不支持房主转移';
  String transferTo(String name) => isEn ? 'Transfer to $name' : '设为房主';
  String transferHostConfirm(String name) =>
      isEn ? 'Transfer host role to $name?' : '确定将房主身份转移给 $name？';
  String get hostTag => isEn ? 'Host' : '房主';
  String get memberTag => isEn ? 'Member' : '成员';
  String get cancel => isEn ? 'Cancel' : '取消';
  String get confirm => isEn ? 'Confirm' : '确定';

  // Status & Notifications
  String roomOnlineCount(int count) =>
      isEn ? '$count online' : '$count 人在线';
  String get roomConnected => isEn ? 'Connected' : '已连接';
  String get speaking => isEn ? 'Speaking' : '正在说话';
  String get muted => isEn ? 'Muted' : '已静音';

  // About & Updates
  String get aboutTitle => isEn ? 'About & Updates' : '关于与更新';
  String get aboutProduct => isEn ? 'SunsetRipple Voice Intercom' : '落日后残波 近场对讲';
  String currentVersion(String ver) => isEn ? 'Version: $ver' : '当前版本: $ver';
  String get updateNetworkNote => isEn
      ? '※ SunsetRipple does not access internet except when checking updates.'
      : '※ 本软件在对讲过程中完全不联网，仅在点击下方检查更新时才会访问 GitHub。';
  String get checkUpdate => isEn ? 'Check GitHub Releases' : '检查 GitHub Releases 更新';
  String get updateIdle => isEn ? 'Click above to check for latest release' : '点击上方按钮获取最新版本';
  String get updateChecking => isEn ? 'Checking GitHub…' : '正在查询 GitHub…';
  String get updateCurrent => isEn ? 'Up to date' : '已是最新版本';
  String updateAvailable(String ver) => isEn ? 'New version available: $ver' : '发现新版本: $ver';
  String updateFailed(String msg) => isEn ? 'Check failed: $msg' : '检查失败: $msg';
  String get changelogTitle => isEn ? 'Changelog' : '更新日志 (CHANGELOG)';
  String get changelogBody => isEn
      ? '• 0.1.0-alpha.8:\n  - AES-GCM sealed frames built in (off by default until compatibility is verified)\n  - Bilingual localization\n  - Host transfer on WiFi rooms (Bluetooth rooms still dissolve if the host leaves)\n  - Diagnostics sanitizer & GitHub report export'
      : '• 0.1.0-alpha.8:\n  - AES-GCM 密封帧已内置（默认关闭，待兼容性验证后启用）\n  - 中英双语\n  - WiFi 房支持房主转移（蓝牙房仍是房主离开即散会）\n  - 诊断脱敏导出';
  String get licenseTitle => isEn ? 'Open Source License' : '开源协议 (License)';
  String get licenseBody => isEn
      ? 'Apache License 2.0\nLicensed under the Apache License, Version 2.0.\nhttps://www.apache.org/licenses/LICENSE-2.0'
      : 'Apache License 2.0\n遵循 Apache 2.0 开源许可证。\nhttps://www.apache.org/licenses/LICENSE-2.0';
  String get privacyTitle => isEn ? 'Privacy Notice' : '隐私与网络说明';
  String get privacyBody => isEn
      ? 'SunsetRipple transmits audio and control data strictly over local Wi-Fi / Bluetooth.\nNo audio or personal data is collected or uploaded.'
      : '落日后残波仅在本地 WiFi / 蓝牙局域网传输音频与控制指令。\n绝无任何后台音频上传或隐私收集。';

  // Theme
  String themeDescription(String current) =>
      isEn ? 'Theme: $current (Tap to switch)' : '当前主题: $current (点击切换)';
  String get themeLight => isEn ? 'Sunset Warm' : '暖金落日';
  String get themeDark => isEn ? 'Moonlit Ocean' : '月夜深海';

  // Home & Stage
  String get appSubheading => isEn
      ? 'The sun has set, the ripples linger, whispering words unsaid.'
      : '夕阳已远，涟漪未散，犹诉未尽之言。';
  String get defaultNickname => isEn ? 'Explorer' : '探索者';
  String get nicknameValidationEmpty => isEn ? 'Please enter a nickname' : '请输入昵称';
  String get emptyRoomListHint => isEn
      ? 'No nearby rooms found\nTap the button above to create a room'
      : '未发现附近的房间\n点击上方按钮即可创建房间';
  String get nearFieldDirect => isEn ? 'Direct P2P' : '近场直连';
  String get nearbyWifiRoom => isEn ? 'Nearby WiFi Room' : '附近 WiFi 房';
  String get directP2PExplanation => isEn
      ? 'Direct P2P connects directly without router'
      : '近场直连将自动建立免网连接并加入';
  String get scanRooms => isEn ? 'Scan Rooms' : '扫描房间';
  String get nearbyRoomsTitle => isEn ? 'Nearby Voice Rooms' : '附近的对讲房间';
  String get detectingRooms => isEn ? 'Probing…' : '正在探测...';
  String get noRoomsDiscoveredHint => isEn
      ? 'No nearby rooms or devices found\nTap "Scan Rooms" above or join the same hotspot / Bluetooth to discover'
      : '未发现附近的房间或设备\n点击上方「扫描房间」或同连热点/蓝牙即可自动发现';
  String get wifiRoomChipSubtitle =>
      isEn ? 'Same WiFi / Hotspot / Direct · Full Duplex' : '同连WiFi/热点/直连 · 畅聊';
  String get bleRoomChipSubtitle =>
      isEn ? 'Close-range Pairing-free · Hold to talk' : '近场免配对 · 按住对讲';
  String get nearbyDevice => isEn ? 'Nearby device' : '附近设备';
  String connectingTo(String target) => isEn ? 'Connecting ($target)...' : '正在连接 ($target)...';
  String get directConnectFailed => isEn
      ? 'Failed to establish Wi-Fi Direct connection. Please get closer and try again.'
      : '未能成功建立 Wi-Fi Direct 直连，请靠近重试';
  String get directConnectPermissionFailed => isEn
      ? 'Direct connection failed. Please make sure the peer accepted the connection.'
      : '近场连接失败，请确认对端已允许连接';
  String roomHostInfo(String host, int count, int max) =>
      isEn ? 'Host: $host · $count/$max devices' : '房主: $host · $count/$max 台';
  String deviceCount(int count, int max) =>
      isEn ? '$count / $max devices' : '$count / $max 台';
  String defaultWifiRoomTitle(String name) =>
      isEn ? "$name's WiFi Room" : '$name 的 WiFi 房';
  String defaultBleRoomTitle(String name) =>
      isEn ? "$name's Bluetooth Room" : '$name 的 蓝牙房';
  String get connecting => isEn ? 'Connecting…' : '正在连接…';
  String joinFailed(String msg) => isEn ? 'Failed to join: $msg' : '加入房间失败: $msg';

  // Stage Header
  String get tooltipInfoAndUpdates => isEn ? 'About & Updates' : '详情与更新';
  String get tooltipToggleTheme => isEn ? 'Toggle Day/Night Theme' : '切换昼夜主题';
  String get tooltipLeaveRoom => isEn ? 'Leave Room' : '离开房间';
  String get tooltipDiagnostics => isEn ? 'Connection Diagnostics' : '连接诊断';
  String get hostBroadcastingStatus => isEn ? 'Host · Broadcasting' : '我是房主 · 房间广播中';
  String get memberConnectedStatus => isEn ? 'Joined · Voice Encrypted' : '已加入房间 · 语音加密互通中';

  // Room Audio State
  String get micMutedStatus => isEn ? 'Microphone muted' : '麦克风已静音';
  String get speakingStatus => isEn ? 'Speaking…' : '正在说话...';
  String get inCallStatus => isEn ? 'In call' : '通话中';
  String get pttHoldingToTalk => isEn ? 'Speaking' : '正在讲话';
  String get pttHoldToTalk => isEn ? 'Hold to talk' : '按住说话';
  String get leave => isEn ? 'Leave' : '离开';
  String get microphone => isEn ? 'Microphone' : '麦克风';

  // Diagnostics Sheet
  String get currentOnlineMembers => isEn ? 'Online Members' : '当前在线成员';
  String get roundTripLatency => isEn ? 'RTT Latency' : '往返延迟 (RTT)';
  String get packetLossRateTitle => isEn ? 'Packet Loss Rate' : '网络丢包率';
  String get audioCodecFormat => isEn ? 'Audio Codec' : '音频编码格式';
}

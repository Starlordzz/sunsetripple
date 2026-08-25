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
}

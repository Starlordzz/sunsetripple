#!/usr/bin/env bash
set -euo pipefail
target="${1:-final-artifacts/release-notes.md}"

cat >> "$target" <<'EOF'

---

### 各产物怎么装

| 产物 | 平台 | 安装方式 |
| --- | --- | --- |
| `SunsetRipple-*.apk` | Android 8.0+ | 直接安装 |
| `SunsetRipple-flutter-*-unsigned.ipa` | iOS 15+ | **未签名**，需用 AltStore / Sideloadly 以自己的 Apple ID 在本地重签后安装 |
| `SunsetRipple-HarmonyOS-source-*.zip` | HarmonyOS NEXT | 源码工程，需用 DevEco Studio 打开自行构建并签名 |

iOS 未提供「下载即装」包：Apple 要求安装包必须经过签名，而签名需要
Apple Developer Program（99 美元/年）证书；ad-hoc 分发还需预先登记设备 UDID。

HarmonyOS NEXT 未提供 `.hap`：鸿蒙零售机只接受 AGC 调试证书（绑定设备 UDID）
或应用市场发布包签名的 HAP，且 DevEco 命令行工具需华为开发者账号登录才能获取，
无法在公共 CI 上构建。
EOF
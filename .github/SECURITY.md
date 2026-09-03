# Security Policy

## 🔒 Supported Versions (支持维护的版本)

SunsetRipple 遵循语义化版本规范。在 Alpha / Beta 预览期内，仅最新发布的 Minor / Patch 版本会持续接收安全补丁修复：

| Version | Supported | Notes |
| :--- | :--- | :--- |
| `0.1.0-alpha.10` / 最新版本 | ✅ 支持 | 包含最新安全与协议补丁 |
| `< 0.1.0-alpha.9` | ❌ 不再维护 | 存在旧版原生或协议接口，建议升级 |

---

## 🛡️ Reporting a Vulnerability (安全漏洞报告机制)

我们高度重视 SunsetRipple 的安全性，特别是涉及**近场音频传输窃听、端到端会话握手劫持、重放攻击以及平台原生 HAL 越界访问**等潜在安全缺陷。

如果您在本项目中发现了潜在安全漏洞，**请切勿直接提交公开的 Issue 或 Pull Request**，请通过以下私密通道进行负责任的漏洞披露：

### 1. 优先通道：GitHub 私密漏洞报告（Private Vulnerability Reporting）
* 进入仓库的 [Security Advisories 页面](https://github.com/Starlordzz/sunsetripple/security/advisories)。
* 点击 **"Report a vulnerability"** 按钮。
* 填写漏洞详情、复现步骤、PoC 或影响范围，该报告将直接私密递交给仓库核心维护团队。

### 2. 备用通道：邮件联系
若无法通过 GitHub 提交，可将漏洞详情发送至维护者邮箱（请在邮件标题注明 `[SunsetRipple Security Disclosure]`）：
* **Contact**: [starlordzz@users.noreply.github.com](mailto:starlordzz@users.noreply.github.com)

---

## ⏱️ Response & Disclosure Lifecycle (响应与披露流程)

1. **初始确认 (Acknowledgment)**：我们将在收到漏洞报告后的 **48 小时** 内进行初步确认与风险评估。
2. **评估与复现 (Triage)**：验证漏洞严重程度，确定受影响平台（Android / iOS / HarmonyOS）与会话链路（WiFi / Bluetooth / Wi-Fi Direct）。
3. **修复与验证 (Patch & Verification)**：在私有安全分支中完成补丁修复并执行全平台回归验证。
4. **协调发布 (Coordinated Release)**：发布新版本 tag 并发布官方 GitHub Security Advisory，向致谢贡献者。

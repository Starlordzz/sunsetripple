import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/diagnostics/diagnostic_report.dart';
import '../../core/update/update_installer.dart';
import '../../core/update/update_manifest.dart';
import '../../core/update/update_service.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class AboutPage extends StatefulWidget {
  final bool isNight;

  const AboutPage({super.key, required this.isNight});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final UpdateService _updateService = UpdateService();
  final UpdateInstaller _installer = UpdateInstaller();
  UpdateState _updateState = const UpdateIdle();
  bool _changelogExpanded = false;
  bool _licenseExpanded = false;
  bool _privacyExpanded = false;

  /// 下载进度：0.0–1.0；null 表示当前没有在下载（按钮态）。
  double? _installProgress;
  String? _installError;
  StreamSubscription<double>? _installSubscription;

  @override
  void dispose() {
    _installSubscription?.cancel();
    _installSubscription = null;
    super.dispose();
  }

  void _checkUpdate() async {
    _installSubscription?.cancel();
    _installSubscription = null;
    setState(() {
      _updateState = const UpdateChecking();
      _installProgress = null;
      _installError = null;
    });
    final result = await _updateService.checkUpdate();
    if (!mounted) return;
    setState(() {
      _updateState = result;
    });
  }

  /// 「下载并安装」。
  ///
  /// Android 且有签名清单时：拉 `update.json` → **验签** → 下载 APK（边下边算
  /// SHA-256）→ 摘要比对 → 交给系统安装器。任何一步失败都只展示可读原因，
  /// 绝不降级成「静默安装」或「静默失败」。
  ///
  /// iOS 的沙箱不允许 App 自装，桌面端也没有安装器；这两种情况退化成
  /// 「打开下载页让用户手动更新」，并明确告知，而不是假装已经装好了。
  Future<void> _startUpdate() async {
    final state = _updateState;
    if (state is! UpdateAvailable) return;
    final s = AppStrings.of(context);
    final manifestUrl = state.manifestUrl;

    if (!UpdateInstaller.supportsInAppInstall || manifestUrl == null) {
      try {
        await _installer.openReleasePage(state.downloadUrl);
      } catch (error) {
        if (!mounted) return;
        setState(() => _installError = _describeUpdateError(error));
      }
      return;
    }

    setState(() {
      _installError = null;
      _installProgress = 0;
    });

    try {
      final manifest = await _installer.fetchManifest(manifestUrl);
      final download = _installer.downloadAndInstall(manifest);
      _installSubscription = download.progress.listen(
        (progress) {
          if (mounted) setState(() => _installProgress = progress);
        },
        onError: (Object error) {
          if (mounted) {
            setState(() => _installError = _describeUpdateError(error));
          }
        },
      );
      await download.done;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.updateHandedToInstaller),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _installError = _describeUpdateError(error));
    } finally {
      await _installSubscription?.cancel();
      _installSubscription = null;
      if (mounted) setState(() => _installProgress = null);
    }
  }

  /// 更新链路的错误都自带可读 message；其余兜底成 toString。
  String _describeUpdateError(Object error) {
    if (error is UpdateManifestException) return error.message;
    if (error is UpdateInstallerException) return error.message;
    return error.toString();
  }

  /// 本地中英切换。
  ///
  /// 更新安装相关的几个新文案还没有进 `AppStrings`（那份文件由发布链路统一维护），
  /// 先在页面内按 [AppStrings.isEn] 取词；等 `AppStrings` 补了对应 getter，
  /// 这里应当直接删掉换成 getter。
  void _showDiagnostics() {
    final s = AppStrings.of(context);
    final report = DiagnosticReport.create(
      appVersion: UpdateService.currentVersion,
      roomType: 'Idle / Standby',
      recentErrors: AppLog.recent.map((e) => e.message).toList(),
      // 平台/宿主版本有助于定位平台通道差异，且会先过脱敏。
      environmentNotes: [
        'host: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'log entries retained: ${AppLog.recent.length}',
      ],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isNight ? const Color(0xFF1E2638) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.diagnosticsTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.isNight ? Colors.white : Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.isNight
                            ? const Color(0xFF141926)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: SelectableText(
                          report.encode(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: widget.isNight
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: report.encode()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.reportCopied)),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: Text(s.copyReport),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.sunsetCoral,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final bgGradient = isNight
        ? [AppTheme.nightAbyss, AppTheme.nightDeepOcean]
        : [AppTheme.lightBg, AppTheme.sunsetCoral.withValues(alpha: 0.15)];
    final textPrimary =
        isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final cardBg = isNight
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = isNight
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bgGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.aboutTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // Content List
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  children: [
                    // App Info Header
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.sunsetCoral,
                                  AppTheme.sunWarmYellow
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.sunsetCoral
                                      .withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.waves,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            s.aboutProduct,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.currentVersion(UpdateService.currentVersion),
                            style: TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.updateNetworkNote,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Update Button
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _checkUpdate,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(s.checkUpdate),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.sunsetCoral,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Update Status Display
                    _buildUpdateStatusWidget(s, textPrimary, textSecondary),

                    const SizedBox(height: 20),

                    // Expandable Section: CHANGELOG
                    _buildExpandableCard(
                      title: s.changelogTitle,
                      body: s.changelogBody,
                      isExpanded: _changelogExpanded,
                      onToggle: () => setState(
                          () => _changelogExpanded = !_changelogExpanded),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),

                    const SizedBox(height: 12),

                    // Expandable Section: License
                    _buildExpandableCard(
                      title: s.licenseTitle,
                      body: s.licenseBody,
                      isExpanded: _licenseExpanded,
                      onToggle: () =>
                          setState(() => _licenseExpanded = !_licenseExpanded),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),

                    const SizedBox(height: 12),

                    // Expandable Section: Privacy
                    _buildExpandableCard(
                      title: s.privacyTitle,
                      body: s.privacyBody,
                      isExpanded: _privacyExpanded,
                      onToggle: () =>
                          setState(() => _privacyExpanded = !_privacyExpanded),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),

                    const SizedBox(height: 24),

                    // Export Diagnostics Button
                    OutlinedButton.icon(
                      onPressed: _showDiagnostics,
                      icon: const Icon(Icons.bug_report_outlined, size: 18),
                      label: Text(s.exportDiagnostics),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Back Home Button
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(s.backHome),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateStatusWidget(
    AppStrings s,
    Color textPrimary,
    Color textSecondary,
  ) {
    if (_updateState is UpdateChecking) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.updateChecking,
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
            ),
          ],
        ),
      );
    } else if (_updateState is UpdateUpToDate) {
      return Center(
        child: Text(
          s.updateCurrent,
          style: TextStyle(fontSize: 13, color: Colors.green.shade400),
        ),
      );
    } else if (_updateState is UpdateAvailable) {
      final avail = _updateState as UpdateAvailable;
      final canInstall =
          UpdateInstaller.supportsInAppInstall && avail.manifestUrl != null;
      final progress = _installProgress;
      return Column(
        children: [
          Text(
            s.updateAvailable(avail.versionName),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.sunWarmYellow),
          ),
          const SizedBox(height: 10),
          if (progress != null)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // 服务端没给 Content-Length 时进度未知，走不定量动画。
                    value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
                    minHeight: 6,
                    backgroundColor:
                        AppTheme.sunWarmYellow.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.sunWarmYellow),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress > 0
                      ? '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                      : s.updatePreparing,
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startUpdate,
                icon: Icon(
                  canInstall
                      ? Icons.download_for_offline_outlined
                      : Icons.open_in_new,
                  size: 18,
                ),
                label: Text(
                  canInstall
                      ? s.updateDownloadAndInstall
                      : s.updateOpenDownloadPage,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.sunsetCoral,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_installError != null) ...[
            const SizedBox(height: 8),
            Text(
              _installError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.red.shade400),
            ),
          ],
        ],
      );
    } else if (_updateState is UpdateFailed) {
      return Center(
        child: Text(
          s.updateCheckFailed,
          style: TextStyle(fontSize: 12, color: Colors.red.shade400),
        ),
      );
    }
    return Center(
      child: Text(
        s.updateIdle,
        style: TextStyle(fontSize: 12, color: textSecondary),
      ),
    );
  }

  Widget _buildExpandableCard({
    required String title,
    required String body,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: textSecondary,
                      size: 20,
                    ),
                  ],
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 10),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

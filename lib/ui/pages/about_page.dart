import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/diagnostics/diagnostic_report.dart';
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
  UpdateState _updateState = const UpdateIdle();
  bool _changelogExpanded = false;
  bool _licenseExpanded = false;
  bool _privacyExpanded = false;

  void _checkUpdate() async {
    setState(() {
      _updateState = const UpdateChecking();
    });
    final result = await _updateService.checkUpdate();
    if (!mounted) return;
    setState(() {
      _updateState = result;
    });
  }

  void _showDiagnostics() {
    final s = AppStrings.of(context);
    final report = DiagnosticReport.create(
      appVersion: UpdateService.currentVersion,
      roomType: 'Idle / Standby',
      recentErrors: AppLog.recent.map((e) => e.message).toList(),
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
                            Clipboard.setData(ClipboardData(text: report.encode()));
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
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                                colors: [AppTheme.sunsetCoral, AppTheme.sunWarmYellow],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.sunsetCoral.withValues(alpha: 0.3),
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
                      onToggle: () => setState(() => _changelogExpanded = !_changelogExpanded),
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
                      onToggle: () => setState(() => _licenseExpanded = !_licenseExpanded),
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
                      onToggle: () => setState(() => _privacyExpanded = !_privacyExpanded),
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
            Text(
              s.updateChecking,
              style: TextStyle(fontSize: 13, color: textSecondary),
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
      return Center(
        child: Text(
          s.updateAvailable(avail.versionName),
          style: const TextStyle(fontSize: 13, color: AppTheme.sunWarmYellow),
        ),
      );
    } else if (_updateState is UpdateFailed) {
      final fail = _updateState as UpdateFailed;
      return Center(
        child: Text(
          s.updateFailed(fail.message),
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
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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

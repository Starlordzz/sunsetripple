import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/diagnostics/diagnostic_report.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Diagnostics & Connection Quality Sheet.
class DiagnosticsSheet extends StatelessWidget {
  final bool isNight;
  final int memberCount;
  final int packetLossRate;
  final int roundTripTimeMs;

  const DiagnosticsSheet({
    super.key,
    required this.isNight,
    this.memberCount = 1,
    this.packetLossRate = 0,
    this.roundTripTimeMs = 12,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final bg = isNight ? AppTheme.darkBg : AppTheme.lightBg;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final report = DiagnosticReport.create(
      appVersion: '0.1.0-alpha.8',
      roomType: 'Intercom Active',
      connected: true,
      memberCount: memberCount,
      receivedFrames: 100,
      concealedFrames: packetLossRate,
      networkQuality: packetLossRate > 5 ? s.qualityFair : s.qualityGood,
      recentErrors: AppLog.recent.map((e) => e.message).toList(),
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.diagnosticsTitle,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _MetricRow(
                title: "Online",
                value: s.roomOnlineCount(memberCount),
                cardBg: cardBg,
                textPrimary: textPrimary,
              ),
              const SizedBox(height: 8),
              _MetricRow(
                title: "RTT",
                value: "$roundTripTimeMs ms",
                cardBg: cardBg,
                textPrimary: textPrimary,
              ),
              const SizedBox(height: 8),
              _MetricRow(
                title: "Loss",
                value: "$packetLossRate %",
                cardBg: cardBg,
                textPrimary: textPrimary,
              ),
              const SizedBox(height: 8),
              _MetricRow(
                title: "Audio Codec",
                value: "Opus 16kHz Mono 20ms",
                cardBg: cardBg,
                textPrimary: textPrimary,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report.encode()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(s.reportCopied),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(s.copyReport, style: const TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.sunsetCoral,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String title;
  final String value;
  final Color cardBg;
  final Color textPrimary;

  const _MetricRow({
    required this.title,
    required this.value,
    required this.cardBg,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

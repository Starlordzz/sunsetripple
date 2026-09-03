import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            title: s.currentOnlineMembers,
            value: s.deviceCount(memberCount, 6),
            cardBg: cardBg,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            title: s.roundTripLatency,
            value: "$roundTripTimeMs ms",
            cardBg: cardBg,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            title: s.packetLossRateTitle,
            value: "$packetLossRate %",
            cardBg: cardBg,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            title: s.audioCodecFormat,
            value: "Opus 16kHz Mono 20ms",
            cardBg: cardBg,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 24),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: textPrimary, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


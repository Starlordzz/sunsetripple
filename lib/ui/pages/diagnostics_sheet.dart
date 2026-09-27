import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/diagnostics/session_metrics.dart';
import '../../l10n/app_strings.dart';

/// Diagnostics & Connection Quality Sheet.
class DiagnosticsSheet extends StatelessWidget {
  final bool isNight;
  final int memberCount;

  /// 会话实测丢包率（%）。
  final int packetLossRate;

  /// 会话实测往返延迟（毫秒）。客户端尚未测到（例如房主侧）时为 null。
  final int? roundTripTimeMs;

  /// 结构化指标快照。给了它之后，指标区会以它为唯一数据源并额外列出
  /// 收/丢帧数、隐藏帧、网络质量与会话时长。
  final SessionMetrics? metrics;

  const DiagnosticsSheet({
    super.key,
    required this.isNight,
    required this.memberCount,
    required this.packetLossRate,
    required this.roundTripTimeMs,
    this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final bg = isNight ? AppTheme.darkBg : AppTheme.lightBg;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary =
        isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final m = metrics;
    // 给了结构化指标就以它为准，避免同一行在两处各写一遍导致数字打架。
    final members = m?.memberCount ?? memberCount;
    final rtt = m != null ? m.roundTripTimeMs : roundTripTimeMs;
    final loss = m?.lossPercent ?? packetLossRate;

    final rows = <Widget>[
      _MetricRow(
        title: s.currentOnlineMembers,
        value: s.deviceCount(members, 6),
        cardBg: cardBg,
        textPrimary: textPrimary,
      ),
      _MetricRow(
        title: s.roundTripLatency,
        value: rtt == null ? '—' : '$rtt ms',
        cardBg: cardBg,
        textPrimary: textPrimary,
      ),
      _MetricRow(
        title: s.packetLossRateTitle,
        value: '$loss%',
        cardBg: cardBg,
        textPrimary: textPrimary,
      ),
      if (m != null) ...[
        _MetricRow(
          title: s.metricReceivedFrames,
          value: '${m.receivedFrames}',
          cardBg: cardBg,
          textPrimary: textPrimary,
        ),
        _MetricRow(
          title: s.metricLostFrames,
          value: '${m.lostFrames}',
          cardBg: cardBg,
          textPrimary: textPrimary,
        ),
        _MetricRow(
          title: s.metricConcealedFrames,
          value: '${m.concealedFrames}',
          cardBg: cardBg,
          textPrimary: textPrimary,
        ),
        _MetricRow(
          title: s.metricNetworkQuality,
          value: m.networkQuality.label(s),
          cardBg: cardBg,
          textPrimary: textPrimary,
        ),
        _MetricRow(
          title: s.metricUptime,
          value: s.metricDuration(m.uptimeSeconds),
          cardBg: cardBg,
          textPrimary: textPrimary,
        ),
      ],
      _MetricRow(
        title: s.audioCodecFormat,
        value: s.audioCodecDescription,
        cardBg: cardBg,
        textPrimary: textPrimary,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // 指标行从 4 行涨到最多 9 行，而 bottom sheet 的可视高度被
      // 屏幕高度挡住（矮屏手机上只有三百多逻辑像素）——不滚动就会溢出。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    s.diagnosticsTitle,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              rows[i],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

extension _NetworkQualityLabel on NetworkQuality {
  String label(AppStrings s) {
    switch (this) {
      case NetworkQuality.good:
        return s.qualityGood;
      case NetworkQuality.fair:
        return s.qualityFair;
      case NetworkQuality.poor:
        return s.qualityPoor;
      case NetworkQuality.unknown:
        return s.metricPendingMeasurement;
    }
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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 6,
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

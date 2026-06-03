import 'dart:math';
import 'package:flutter/material.dart';
import '../../../data/models/source_health_record.dart';

class HealthTrendChart extends StatelessWidget {
  final List<SourceHealthRecord> records;

  const HealthTrendChart({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (records.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        child: const Text(
          '暂无健康数据历史，诊断后将生成首条数据。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '30天健康度走势图 (双轴)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text('成功率 (左)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(width: 12),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text('延迟 (右)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: HealthTrendPainter(records: records, isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class HealthTrendPainter extends CustomPainter {
  final List<SourceHealthRecord> records;
  final bool isDark;

  HealthTrendPainter({required this.records, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 35.0;
    const rightMargin = 40.0;
    const bottomMargin = 18.0;
    const topMargin = 8.0;

    final drawWidth = size.width - leftMargin - rightMargin;
    final drawHeight = size.height - bottomMargin - topMargin;

    if (drawWidth <= 0 || drawHeight <= 0) return;

    // Grid details
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawText(String text, double x, double y, Color color, {Alignment alignment = Alignment.center}) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 8, fontFamily: 'monospace'),
      );
      textPainter.layout();
      
      var finalX = x;
      var finalY = y;
      if (alignment == Alignment.center) {
        finalX = x - textPainter.width / 2;
        finalY = y - textPainter.height / 2;
      } else if (alignment == Alignment.centerRight) {
        finalX = x - textPainter.width;
        finalY = y - textPainter.height / 2;
      } else if (alignment == Alignment.centerLeft) {
        finalY = y - textPainter.height / 2;
      }

      textPainter.paint(canvas, Offset(finalX, finalY));
    }

    // Draw horizontal grid lines (3 levels: 0%, 50%, 100%)
    for (int i = 0; i <= 2; i++) {
      final y = topMargin + drawHeight * (1 - i / 2.0);
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), gridPaint);
      
      // Left axis label (Success Rate %)
      final pct = (i * 50).toString();
      drawText('$pct%', leftMargin - 4, y, isDark ? Colors.grey[500]! : Colors.grey[600]!, alignment: Alignment.centerRight);
    }

    // Scaling latency: find max latency, round to nearest 1000
    int maxLatency = 1000;
    for (final r in records) {
      if (r.avgResponseTimeMs > maxLatency) maxLatency = r.avgResponseTimeMs;
    }
    maxLatency = ((maxLatency + 999) ~/ 1000) * 1000;
    if (maxLatency < 1000) maxLatency = 1000;

    // Right axis label (Latency ms)
    for (int i = 0; i <= 2; i++) {
      final y = topMargin + drawHeight * (1 - i / 2.0);
      final msVal = (i * (maxLatency ~/ 2)).toString();
      drawText('${msVal}ms', size.width - rightMargin + 4, y, isDark ? Colors.grey[500]! : Colors.grey[600]!, alignment: Alignment.centerLeft);
    }

    final int nPoints = records.length;
    final double stepX = nPoints > 1 ? drawWidth / (nPoints - 1) : drawWidth;

    // Draw X labels (Dates, e.g. "06-03")
    final labelStep = max(1, (nPoints / 4).round());
    for (int i = 0; i < nPoints; i += labelStep) {
      final x = leftMargin + i * stepX;
      final fullDate = records[i].date; // yyyy-MM-dd
      final mmdd = fullDate.length >= 10 ? fullDate.substring(5) : fullDate;
      drawText(mmdd, x, size.height - bottomMargin / 2, isDark ? Colors.grey[500]! : Colors.grey[600]!);
    }

    // Draw Success Line & Area Gradient
    final successPoints = <Offset>[];
    for (int i = 0; i < nPoints; i++) {
      final x = leftMargin + i * stepX;
      final rate = records[i].successRate;
      final y = topMargin + drawHeight * (1 - rate);
      successPoints.add(Offset(x, y));
    }

    if (successPoints.isNotEmpty) {
      final successLinePath = Path()..moveTo(successPoints[0].dx, successPoints[0].dy);
      final successAreaPath = Path()..moveTo(successPoints[0].dx, topMargin + drawHeight);
      successAreaPath.lineTo(successPoints[0].dx, successPoints[0].dy);

      for (int i = 1; i < successPoints.length; i++) {
        successLinePath.lineTo(successPoints[i].dx, successPoints[i].dy);
        successAreaPath.lineTo(successPoints[i].dx, successPoints[i].dy);
      }
      successAreaPath.lineTo(successPoints.last.dx, topMargin + drawHeight);
      successAreaPath.close();

      // Shaded area
      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF10B981).withOpacity(0.25),
            const Color(0xFF10B981).withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(leftMargin, topMargin, drawWidth, drawHeight));
      canvas.drawPath(successAreaPath, areaPaint);

      // Line
      final linePaint = Paint()
        ..color = const Color(0xFF10B981)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(successLinePath, linePaint);

      // Highlighting Dots
      final dotPaint = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill;
      final outerDotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      for (final pt in successPoints) {
        canvas.drawCircle(pt, 3.5, dotPaint);
        canvas.drawCircle(pt, 3.5, outerDotPaint);
      }
    }

    // Draw Latency Line (Orange dotted/dashed)
    final latencyPoints = <Offset>[];
    for (int i = 0; i < nPoints; i++) {
      final x = leftMargin + i * stepX;
      final val = records[i].avgResponseTimeMs;
      final double latRatio = val / maxLatency;
      final double cappedRatio = latRatio > 1.0 ? 1.0 : latRatio;
      final y = topMargin + drawHeight * (1 - cappedRatio);
      latencyPoints.add(Offset(x, y));
    }

    if (latencyPoints.isNotEmpty) {
      final latencyLinePath = Path()..moveTo(latencyPoints[0].dx, latencyPoints[0].dy);
      for (int i = 1; i < latencyPoints.length; i++) {
        latencyLinePath.lineTo(latencyPoints[i].dx, latencyPoints[i].dy);
      }

      // Draw dashed stroke manually
      final latencyPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      // Draw dashed path
      final pathMetrics = latencyLinePath.computeMetrics();
      for (final metric in pathMetrics) {
        double distance = 0.0;
        const dashLength = 4.0;
        const spaceLength = 3.0;
        bool draw = true;
        while (distance < metric.length) {
          final len = draw ? dashLength : spaceLength;
          if (draw) {
            canvas.drawPath(
              metric.extractPath(distance, min(distance + len, metric.length)),
              latencyPaint,
            );
          }
          distance += len;
          draw = !draw;
        }
      }

      // Highlighting Dots for Latency
      final latDotPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.fill;

      for (final pt in latencyPoints) {
        canvas.drawCircle(pt, 2.5, latDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HealthTrendPainter oldDelegate) {
    return oldDelegate.records != records || oldDelegate.isDark != isDark;
  }
}

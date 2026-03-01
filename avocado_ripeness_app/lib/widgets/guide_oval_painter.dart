import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';

/// ガイド楕円を描画するCustomPainter
/// 楕円の外側を半透明の暗いオーバーレイで覆い、楕円の枠線を描画する
class GuideOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalW = size.width * GuideOval.widthRatio;
    final ovalH = size.height * GuideOval.heightRatio;

    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalW,
      height: ovalH,
    );

    // 楕円の外側を半透明で塗りつぶし
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = AppColors.avocadoBrown.withValues(alpha: 0.40),
    );

    // 楕円の枠線
    final borderPaint = Paint()
      ..color = AppColors.avocadoLight.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5.w;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

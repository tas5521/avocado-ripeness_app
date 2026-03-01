import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/app_colors.dart';
import '../services/model_service.dart';

/// 推論結果オーバーレイ
class ResultOverlay extends StatelessWidget {
  final InferenceResult result;

  const ResultOverlay({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    // 期待値を0.0〜1.0に正規化（1.0〜3.0 → 0.0〜1.0）
    final normalized = ((result.expectedValue - 1.0) / 2.0).clamp(0.0, 1.0);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 28.w),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.overlayBg,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            result.className,
            style: TextStyle(
              color: AppColors.textOnOverlay,
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10.h),
          RipenessBar(value: normalized),
          SizedBox(height: 4.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '未熟',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
              ),
              Text(
                'やや未熟',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
              ),
              Text(
                '適熟',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
              ),
              Text(
                'やや過熟',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
              ),
              Text(
                '過熟',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.sp),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 緑→黄→赤のグラデーションバーにインジケーターを表示
class RipenessBar extends StatelessWidget {
  final double value;

  const RipenessBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28.h,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          final indicatorX = (value * barWidth).clamp(0.0, barWidth);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // グラデーションバー
              Container(
                height: 10.h,
                margin: EdgeInsets.only(top: 12.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5.r),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF4CAF50),
                      Color(0xFF8BC34A),
                      Color(0xFFFFEB3B),
                      Color(0xFFFF9800),
                      Color(0xFFF44336),
                    ],
                  ),
                ),
              ),
              // インジケーター
              Positioned(
                left: indicatorX - 13.w,
                top: 0,
                child: Icon(
                  Icons.arrow_drop_down,
                  color: AppColors.textOnOverlay,
                  size: 26.sp,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/app_colors.dart';

/// 初回起動時の免責事項ダイアログを表示
void showDisclaimerDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
      ),
      title: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: AppColors.avocadoGreen,
            size: 24.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'ご利用にあたって',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.avocadoBrown,
            ),
          ),
        ],
      ),
      content: Text(
        'このアプリは、アボカドの熟度を推定するものです。\n\nアボカドの鮮度や味を保証するものではありません。',
        style: TextStyle(
          fontSize: 14.sp,
          color: AppColors.avocadoBrown,
          height: 1.6,
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.avocadoGreen,
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
          child: Text(
            '理解しました',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Aboutダイアログを表示
void showAppAboutDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(
        'アボカド熟度チェッカー',
        style: TextStyle(fontSize: 18.sp, color: AppColors.avocadoBrown),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.avocadoBrown.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'アボカドの熟度をAIで判定するアプリです。',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.avocadoBrown,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              'データセット情報',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.avocadoGreen,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '本アプリは以下のデータセットを使用して学習しました：',
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.avocadoBrown,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              "'Hass' Avocado Ripening Photographic Dataset",
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.avocadoBrown,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'DOI: 10.17632/3xd9n945v8.1',
              style: TextStyle(
                fontSize: 11.sp,
                fontStyle: FontStyle.italic,
                color: AppColors.avocadoBrown.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '作成者: Pedro Xavier, Pedro Rodrigues, Cristina L. M. Silva',
              style: TextStyle(fontSize: 11.sp, color: AppColors.avocadoBrown),
            ),
            SizedBox(height: 4.h),
            Text(
              '機関: Centro de Biotecnologia e Quimica Fina',
              style: TextStyle(fontSize: 11.sp, color: AppColors.avocadoBrown),
            ),
            SizedBox(height: 4.h),
            Text(
              'ライセンス: CC BY 4.0',
              style: TextStyle(fontSize: 11.sp, color: AppColors.avocadoBrown),
            ),
            SizedBox(height: 8.h),
            Text(
              'https://data.mendeley.com/datasets/3xd9n945v8/1',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.avocadoGreen,
                decoration: TextDecoration.underline,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'データセットの引用元を参照してください。',
              style: TextStyle(
                fontSize: 11.sp,
                fontStyle: FontStyle.italic,
                color: AppColors.avocadoBrown.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showLicensePage(context);
            },
          child: Text(
            'ライセンス',
            style: TextStyle(color: AppColors.avocadoGreen),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '閉じる',
            style: TextStyle(color: AppColors.avocadoGreen),
          ),
        ),
      ],
    ),
  );
}

/// ライセンスページを表示
void _showLicensePage(BuildContext context) {
  showLicensePage(
    context: context,
    applicationName: 'アボカド熟度チェッカー',
    applicationVersion: '1.0.0',
  );
}

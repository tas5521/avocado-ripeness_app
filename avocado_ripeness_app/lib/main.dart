import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'constants/app_colors.dart';
import 'screens/camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('カメラの取得に失敗しました: $e');
  }

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'アボカド熟度チェッカー',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.avocadoGreen,
              primary: AppColors.avocadoGreen,
              surface: AppColors.background,
            ),
            scaffoldBackgroundColor: AppColors.background,
            useMaterial3: true,
          ),
          home: CameraScreen(cameras: cameras),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

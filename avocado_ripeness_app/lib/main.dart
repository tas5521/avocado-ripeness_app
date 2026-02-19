import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'services/model_service.dart';

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
          title: 'アボカド成熟度チェッカー',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
            useMaterial3: true,
          ),
          home: CameraScreen(cameras: cameras),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

/// アプリのライフサイクルを監視し、バックグラウンド/フォアグラウンドを検知
class _AppLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onPause;
  final VoidCallback onResume;

  _AppLifecycleObserver({required this.onPause, required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        onPause();
        break;
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.detached:
        onPause();
        break;
    }
  }
}

/// ガイド楕円の定数（画面比率で定義）
class _GuideOval {
  static double widthRatio = 0.55;
  static double heightRatio = 0.40;
}

class CameraScreen extends HookWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    final cameraController = useState<CameraController?>(null);
    final isCameraInitialized = useState<bool>(false);
    final errorMessage = useState<String?>(null);
    final isModelReady = useState<bool>(false);

    final resultNotifier = useMemoized(
      () => ValueNotifier<InferenceResult?>(null),
    );
    useEffect(() => resultNotifier.dispose, [resultNotifier]);

    final modelServiceRef = useRef<ModelService?>(null);
    final timerRef = useRef<Timer?>(null);
    final isProcessingRef = useRef<bool>(false);
    final isInForeground = useState<bool>(true);

    // アプリのライフサイクル監視（バックグラウンド時に推論を停止）
    useEffect(() {
      final observer = _AppLifecycleObserver(
        onPause: () => isInForeground.value = false,
        onResume: () => isInForeground.value = true,
      );
      WidgetsBinding.instance.addObserver(observer);
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, []);

    // モデルサービスの初期化
    useEffect(() {
      bool disposed = false;
      final service = ModelService();

      service
          .initialize()
          .then((_) {
            if (!disposed) {
              modelServiceRef.value = service;
              isModelReady.value = true;
              debugPrint('モデルの初期化が完了しました');
            }
          })
          .catchError((error) {
            if (!disposed) {
              errorMessage.value = 'モデルの読み込みに失敗: $error';
              debugPrint('モデル初期化エラー: $error');
            }
          });

      return () {
        disposed = true;
        service.dispose();
      };
    }, []);

    // カメラの初期化
    useEffect(() {
      if (cameras.isEmpty) {
        errorMessage.value = 'カメラが見つかりません';
        return null;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      controller
          .initialize()
          .then((_) {
            cameraController.value = controller;
            isCameraInitialized.value = true;
            debugPrint('カメラの初期化が完了しました');
          })
          .catchError((error) {
            errorMessage.value = 'カメラの初期化に失敗: $error';
            debugPrint('カメラ初期化エラー: $error');
          });

      return () {
        controller.dispose();
      };
    }, []);

    // 推論タイマー（フォアグラウンド時のみ動作）
    useEffect(() {
      if (!isInForeground.value ||
          !isCameraInitialized.value ||
          !isModelReady.value ||
          cameraController.value == null ||
          modelServiceRef.value == null) {
        timerRef.value?.cancel();
        timerRef.value = null;
        return null;
      }

      debugPrint('推論タイマーを開始します');

      timerRef.value = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _captureAndInfer(
          cameraController.value!,
          modelServiceRef.value!,
          isProcessingRef,
          resultNotifier,
        ),
      );

      return () {
        timerRef.value?.cancel();
        timerRef.value = null;
      };
    }, [isInForeground.value, isCameraInitialized.value, isModelReady.value]);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => _showAboutDialog(context),
            tooltip: 'アプリ情報',
          ),
        ],
      ),
      body: Stack(
        children: [
          // カメラプレビュー（アスペクト比を維持して画面全体をカバー）
          if (isCameraInitialized.value && cameraController.value != null)
            Positioned.fill(
              child: RepaintBoundary(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraController.value!.value.previewSize!.height,
                    height: cameraController.value!.value.previewSize!.width,
                    child: CameraPreview(cameraController.value!),
                  ),
                ),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  SizedBox(height: 16.h),
                  Text(
                    !isCameraInitialized.value
                        ? 'カメラを初期化しています...'
                        : 'モデルを読み込んでいます...',
                    style: TextStyle(fontSize: 16.sp),
                  ),
                ],
              ),
            ),

          // ガイド楕円枠オーバーレイ
          if (isCameraInitialized.value)
            Positioned.fill(child: CustomPaint(painter: _GuideOvalPainter())),

          // ガイドテキスト
          if (isCameraInitialized.value)
            Positioned(
              bottom: 120.h,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'ここにアボカドを合わせてください',
                    style: TextStyle(color: Colors.white, fontSize: 14.sp),
                  ),
                ),
              ),
            ),

          // エラーメッセージ
          if (errorMessage.value != null)
            Center(
              child: Container(
                padding: EdgeInsets.all(16.w),
                margin: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  errorMessage.value!,
                  style: TextStyle(color: Colors.white, fontSize: 16.sp),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // 推論結果オーバーレイ
          Positioned(
            top: 85.h,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: ValueListenableBuilder<InferenceResult?>(
                valueListenable: resultNotifier,
                builder: (context, result, _) {
                  if (result == null) return const SizedBox.shrink();
                  return _ResultOverlay(result: result);
                },
              ),
            ),
          ),

          // モデル初期化中インジケーター
          if (!isModelReady.value && isCameraInitialized.value)
            Positioned(
              bottom: 40.h,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'モデル読み込み中...',
                    style: TextStyle(color: Colors.white, fontSize: 12.sp),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Aboutダイアログを表示
  static void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アボカド成熟度チェッカー', style: TextStyle(fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Version 1.0.0',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text(
                'アボカドの成熟度をAIで判定するアプリです。',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              const Text(
                'データセット情報',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '本アプリは以下のデータセットを使用して学習しました：',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                "'Hass' Avocado Ripening Photographic Dataset",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'DOI: 10.17632/3xd9n945v8.1',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),
              const Text(
                '作成者: Pedro Xavier, Pedro Rodrigues, Cristina L. M. Silva',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 4),
              const Text(
                '機関: Centro de Biotecnologia e Quimica Fina',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 4),
              const Text('ライセンス: CC BY 4.0', style: TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              const Text(
                'https://data.mendeley.com/datasets/3xd9n945v8/1',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'データセットの引用元を参照してください。',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
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
            child: const Text('ライセンス'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// ライセンスページを表示
  static void _showLicensePage(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'アボカド成熟度チェッカー',
      applicationVersion: '1.0.0',
    );
  }

  /// カメラ画像座標でのCrop矩形を計算する
  ///
  /// FittedBox(cover)による表示変換を考慮し、画面上の楕円外接矩形を
  /// カメラ画像のピクセル座標に変換する。
  static CropRect _computeCropRect(CameraController controller) {
    final screenSize =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

    final screenW = screenSize.width;
    final screenH = screenSize.height;

    // カメラのプレビューサイズ（横向き基準）
    final camW = controller.value.previewSize!.height;
    final camH = controller.value.previewSize!.width;

    // FittedBox(cover)のスケール計算
    final scaleX = screenW / camW;
    final scaleY = screenH / camH;
    final coverScale = math.max(scaleX, scaleY);

    // カバー後の表示サイズ
    final displayW = camW * coverScale;
    final displayH = camH * coverScale;

    // オフセット（クリップされる分）
    final offsetX = (displayW - screenW) / 2.0;
    final offsetY = (displayH - screenH) / 2.0;

    // 画面上の楕円外接矩形
    final ovalW = screenW * _GuideOval.widthRatio;
    final ovalH = screenH * _GuideOval.heightRatio;
    final ovalLeft = (screenW - ovalW) / 2.0;
    final ovalTop = (screenH - ovalH) / 2.0;

    // 画面座標 → カメラ画像座標への変換
    final cropLeft = ((ovalLeft + offsetX) / coverScale).round();
    final cropTop = ((ovalTop + offsetY) / coverScale).round();
    final cropRight = (((ovalLeft + ovalW) + offsetX) / coverScale).round();
    final cropBottom = (((ovalTop + ovalH) + offsetY) / coverScale).round();

    // カメラ画像サイズでクランプ
    final camImgW = camW.round();
    final camImgH = camH.round();

    return CropRect(
      left: cropLeft.clamp(0, camImgW),
      top: cropTop.clamp(0, camImgH),
      right: cropRight.clamp(0, camImgW),
      bottom: cropBottom.clamp(0, camImgH),
    );
  }

  /// 1フレームだけキャプチャして推論を実行
  static Future<void> _captureAndInfer(
    CameraController controller,
    ModelService service,
    ObjectRef<bool> isProcessing,
    ValueNotifier<InferenceResult?> resultNotifier,
  ) async {
    if (isProcessing.value) return;
    if (!controller.value.isInitialized) return;

    isProcessing.value = true;

    try {
      // Crop矩形を計算
      final cropRect = _computeCropRect(controller);

      // 画像ストリームを開始して1フレームだけキャプチャ
      final completer = Completer<_FrameData>();

      controller.startImageStream((CameraImage image) {
        if (!completer.isCompleted) {
          completer.complete(_copyFrameData(image));
        }
      });

      final frameData = await completer.future;
      await controller.stopImageStream();

      final result = await service.predictFromBuffer(
        isBgra: frameData.isBgra,
        bgraBytes: frameData.bgraBytes,
        bgraBytesPerRow: frameData.bgraBytesPerRow,
        yBytes: frameData.yBytes,
        uBytes: frameData.uBytes,
        vBytes: frameData.vBytes,
        width: frameData.width,
        height: frameData.height,
        yBytesPerRow: frameData.yBytesPerRow,
        uvBytesPerRow: frameData.uvBytesPerRow,
        uvPixelStride: frameData.uvPixelStride,
        cropRect: cropRect,
      );

      if (result != null) {
        resultNotifier.value = result;
      }
    } catch (e) {
      debugPrint('推論サイクルエラー: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// CameraImageからデータをコピー
  static _FrameData _copyFrameData(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return _FrameData(
        isBgra: true,
        bgraBytes: Uint8List.fromList(image.planes[0].bytes),
        bgraBytesPerRow: image.planes[0].bytesPerRow,
        width: image.width,
        height: image.height,
      );
    }

    return _FrameData(
      isBgra: false,
      yBytes: Uint8List.fromList(image.planes[0].bytes),
      uBytes: Uint8List.fromList(image.planes[1].bytes),
      vBytes: Uint8List.fromList(image.planes[2].bytes),
      width: image.width,
      height: image.height,
      yBytesPerRow: image.planes[0].bytesPerRow,
      uvBytesPerRow: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
  }
}

/// コピー済みフレームデータ
class _FrameData {
  final bool isBgra;
  final Uint8List? bgraBytes;
  final int? bgraBytesPerRow;
  final Uint8List? yBytes;
  final Uint8List? uBytes;
  final Uint8List? vBytes;
  final int width;
  final int height;
  final int yBytesPerRow;
  final int uvBytesPerRow;
  final int uvPixelStride;

  _FrameData({
    required this.isBgra,
    this.bgraBytes,
    this.bgraBytesPerRow,
    this.yBytes,
    this.uBytes,
    this.vBytes,
    required this.width,
    required this.height,
    this.yBytesPerRow = 0,
    this.uvBytesPerRow = 0,
    this.uvPixelStride = 1,
  });
}

/// ガイド楕円を描画するCustomPainter
/// 楕円の外側を半透明の暗いオーバーレイで覆い、楕円の枠線を描画する
class _GuideOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalW = size.width * _GuideOval.widthRatio;
    final ovalH = size.height * _GuideOval.heightRatio;

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
      Paint()..color = Colors.black.withOpacity(0.45),
    );

    // 楕円の枠線
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 推論結果オーバーレイ
class _ResultOverlay extends StatelessWidget {
  final InferenceResult result;

  const _ResultOverlay({required this.result});

  @override
  Widget build(BuildContext context) {
    // 期待値を0.0〜1.0に正規化（1.0〜5.0 → 0.0〜1.0）
    final normalized = ((result.expectedValue - 1.0) / 4.0).clamp(0.0, 1.0);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 28.w),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            result.className,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10.h),
          _RipenessBar(value: normalized),
          SizedBox(height: 4.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '未熟',
                style: TextStyle(color: Colors.white70, fontSize: 13.sp),
              ),
              Text(
                'やや未熟',
                style: TextStyle(color: Colors.white70, fontSize: 13.sp),
              ),
              Text(
                '適熟',
                style: TextStyle(color: Colors.white70, fontSize: 13.sp),
              ),
              Text(
                'やや過熟',
                style: TextStyle(color: Colors.white70, fontSize: 13.sp),
              ),
              Text(
                '過熟',
                style: TextStyle(color: Colors.white70, fontSize: 13.sp),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 緑→黄→赤のグラデーションバーにインジケーターを表示
class _RipenessBar extends StatelessWidget {
  final double value;

  const _RipenessBar({required this.value});

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
                  color: Colors.white,
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

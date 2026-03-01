import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../services/model_service.dart';
import '../widgets/app_lifecycle_observer.dart';
import '../widgets/guide_oval_painter.dart';
import '../widgets/result_overlay.dart';
import '../widgets/about_dialog.dart';
import '../utils/camera_utils.dart';

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
    final emaRef = useRef<double?>(null);
    final isInForeground = useState<bool>(true);

    // アプリのライフサイクル監視（バックグラウンド時に推論を停止）
    useEffect(() {
      final observer = AppLifecycleObserver(
        onPause: () => isInForeground.value = false,
        onResume: () => isInForeground.value = true,
      );
      WidgetsBinding.instance.addObserver(observer);
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, []);

    // 初回起動時の免責事項ダイアログ表示
    useEffect(() {
      Future<void> checkFirstLaunch() async {
        final prefs = await SharedPreferences.getInstance();
        final hasShownDisclaimer =
            prefs.getBool('has_shown_disclaimer') ?? false;

        if (!hasShownDisclaimer) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              showDisclaimerDialog(context);
              prefs.setBool('has_shown_disclaimer', true);
            }
          });
        }
      }

      checkFirstLaunch();
      return null;
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
          .then((_) async {
            // 画面の向きをPortraitに固定
            await SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]);
            // カメラの向きもPortraitに固定
            try {
              await controller.lockCaptureOrientation();
            } catch (e) {
              debugPrint('カメラの向き固定に失敗: $e');
            }
            cameraController.value = controller;
            isCameraInitialized.value = true;
            debugPrint('カメラの初期化が完了しました');
          })
          .catchError((error) async {
            final status = await Permission.camera.status;
            if (!status.isGranted) {
              errorMessage.value = 'カメラ権限が拒否されました';
            } else {
              errorMessage.value = 'カメラの初期化に失敗: $error';
            }
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
        const Duration(milliseconds: 500),
        (_) => _captureAndInfer(
          cameraController.value!,
          modelServiceRef.value!,
          isProcessingRef,
          resultNotifier,
          emaRef,
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
            icon: Icon(
              Icons.info_outline,
              color: isCameraInitialized.value
                  ? Colors.white
                  : AppColors.avocadoGreen,
            ),
            onPressed: () => showAppAboutDialog(context),
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
          else if (errorMessage.value != null)
            Positioned.fill(
              child: Container(
                color: AppColors.background,
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            errorMessage.value!.contains('権限')
                                ? Icons.camera_alt_outlined
                                : Icons.error_outline,
                            size: 64.sp,
                            color: AppColors.avocadoGreen,
                          ),
                          SizedBox(height: 24.h),
                          Text(
                            errorMessage.value!,
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: AppColors.avocadoBrown,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (errorMessage.value!.contains('権限')) ...[
                            SizedBox(height: 12.h),
                            Text(
                              'アボカドの熟度を判定するためには\nカメラへのアクセスが必要です',
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: AppColors.avocadoBrown.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 32.h),
                            ElevatedButton.icon(
                              onPressed: () async {
                                await AppSettings.openAppSettings();
                              },
                              icon: const Icon(
                                Icons.settings,
                                color: Colors.white,
                              ),
                              label: Text(
                                '設定を開く',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.avocadoGreen,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 32.w,
                                  vertical: 14.h,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              color: AppColors.background,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.avocadoGreen),
                    SizedBox(height: 16.h),
                    Text(
                      'カメラを初期化しています...',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: AppColors.avocadoBrown,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ガイド楕円枠オーバーレイ
          if (isCameraInitialized.value)
            Positioned.fill(child: CustomPaint(painter: GuideOvalPainter())),

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
                    color: AppColors.pillBg,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'アボカドを枠に合わせてください',
                    style: TextStyle(
                      color: AppColors.textOnOverlay,
                      fontSize: 14.sp,
                    ),
                  ),
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
                  return ResultOverlay(result: result);
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
                    color: AppColors.pillBg,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'モデル読み込み中...',
                    style: TextStyle(
                      color: AppColors.textOnOverlay,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// EMAの重み（0に近いほど過去の値を重視、1で平滑化なし）
  static const double _emaAlpha = 0.5;

  /// 1フレームだけキャプチャして推論を実行
  static Future<void> _captureAndInfer(
    CameraController controller,
    ModelService service,
    ObjectRef<bool> isProcessing,
    ValueNotifier<InferenceResult?> resultNotifier,
    ObjectRef<double?> emaRef,
  ) async {
    if (isProcessing.value) return;
    if (!controller.value.isInitialized) return;

    isProcessing.value = true;

    try {
      final cropRect = computeCropRect(controller);

      final completer = Completer<FrameData>();

      controller.startImageStream((CameraImage image) {
        if (!completer.isCompleted) {
          completer.complete(copyFrameData(image));
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
        final prev = emaRef.value;
        final smoothed = prev == null
            ? result.expectedValue
            : prev * (1.0 - _emaAlpha) + result.expectedValue * _emaAlpha;
        emaRef.value = smoothed;

        final normalized = ((smoothed - 1.0) / 2.0).clamp(0.0, 1.0);

        // 3クラス判定（classIndex用）
        final labelIndex = normalized < (1.0 / 3.0)
            ? 0
            : normalized < (2.0 / 3.0)
            ? 1
            : 2;

        // 5段階ラベル（表示用）
        final String displayLabel;
        if (normalized < 0.2) {
          displayLabel = '未熟';
        } else if (normalized < 0.4) {
          displayLabel = 'やや未熟';
        } else if (normalized < 0.6) {
          displayLabel = '適熟';
        } else if (normalized < 0.8) {
          displayLabel = 'やや過熟';
        } else {
          displayLabel = '過熟';
        }

        resultNotifier.value = InferenceResult(
          classIndex: labelIndex,
          className: displayLabel,
          confidence: result.confidence,
          expectedValue: smoothed,
        );
      }
    } catch (e) {
      debugPrint('推論サイクルエラー: $e');
    } finally {
      isProcessing.value = false;
    }
  }
}

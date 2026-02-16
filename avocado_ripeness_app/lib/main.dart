import 'dart:async';
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
    print('カメラの取得に失敗しました: $e');
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

class CameraScreen extends HookWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    final cameraController = useState<CameraController?>(null);
    final isCameraInitialized = useState<bool>(false);
    final errorMessage = useState<String?>(null);
    final isModelReady = useState<bool>(false);

    // 推論結果はValueNotifierで管理（CameraScreenをリビルドしない）
    final resultNotifier =
        useMemoized(() => ValueNotifier<InferenceResult?>(null));
    useEffect(() => resultNotifier.dispose, [resultNotifier]);

    final modelServiceRef = useRef<ModelService?>(null);
    final timerRef = useRef<Timer?>(null);
    final isProcessingRef = useRef<bool>(false);

    // モデルサービスの初期化
    useEffect(() {
      bool disposed = false;
      final service = ModelService();

      service.initialize().then((_) {
        if (!disposed) {
          modelServiceRef.value = service;
          isModelReady.value = true;
          print('モデルの初期化が完了しました');
        }
      }).catchError((error) {
        if (!disposed) {
          errorMessage.value = 'モデルの読み込みに失敗: $error';
          print('モデル初期化エラー: $error');
        }
      });

      return () {
        disposed = true;
        service.dispose();
      };
    }, []);

    // カメラの初期化（startImageStreamは使わない）
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

      controller.initialize().then((_) {
        cameraController.value = controller;
        isCameraInitialized.value = true;
        print('カメラの初期化が完了しました');
      }).catchError((error) {
        errorMessage.value = 'カメラの初期化に失敗: $error';
        print('カメラ初期化エラー: $error');
      });

      return () {
        controller.dispose();
      };
    }, []);

    // 推論タイマー: 短くstreamを開いて1フレーム取得 → 推論
    useEffect(() {
      if (!isCameraInitialized.value ||
          !isModelReady.value ||
          cameraController.value == null ||
          modelServiceRef.value == null) {
        return null;
      }

      print('推論タイマーを開始します');

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
    }, [isCameraInitialized.value, isModelReady.value]);

    return Scaffold(
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

          // 推論結果オーバーレイ（ValueListenableBuilderで独立更新）
          Positioned(
            top: 60.h,
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
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
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
      // 1. 画像ストリームを開始して1フレームだけキャプチャ
      final completer = Completer<_FrameData>();

      controller.startImageStream((CameraImage image) {
        if (!completer.isCompleted) {
          // 即座にデータをコピー
          completer.complete(_copyFrameData(image));
        }
      });

      // 最初のフレームを取得
      final frameData = await completer.future;

      // 2. すぐにストリームを停止（カメラプレビューへの干渉を最小化）
      await controller.stopImageStream();

      // 3. 前処理を別Isolateで実行
      // 4. 推論実行（FFI、メインスレッドだが画像ストリームは停止済み）
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
      );

      if (result != null) {
        resultNotifier.value = result;
      }
    } catch (e) {
      print('推論サイクルエラー: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// CameraImageからデータをコピー（ストリームコールバック内で実行）
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

/// 推論結果オーバーレイ
class _ResultOverlay extends StatelessWidget {
  final InferenceResult result;

  const _ResultOverlay({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '成熟度',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            result.className,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8.h),
          Text(
            '信頼度: ${(result.confidence * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14.sp,
            ),
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: result.confidence,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                _getConfidenceColor(result.confidence),
              ),
              minHeight: 8.h,
            ),
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }
}

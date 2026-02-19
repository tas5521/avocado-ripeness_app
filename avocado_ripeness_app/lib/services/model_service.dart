import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:executorch_flutter/executorch_flutter.dart';
import 'package:flutter/services.dart';
import '../constants/class_names.dart';

/// モデル推論結果
class InferenceResult {
  final int classIndex;
  final String className;
  final double confidence;

  /// 期待値（1.0=未熟 〜 5.0=過熟）
  final double expectedValue;

  InferenceResult({
    required this.classIndex,
    required this.className,
    required this.confidence,
    required this.expectedValue,
  });
}

/// 楕円Crop領域（カメラ画像座標）
class CropRect {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get width => right - left;
  int get height => bottom - top;
  double get centerX => (left + right) / 2.0;
  double get centerY => (top + bottom) / 2.0;
  double get radiusX => width / 2.0;
  double get radiusY => height / 2.0;
}

/// Isolateに送る推論リクエスト
class _InferRequest {
  final SendPort replyPort;
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
  final CropRect? cropRect;

  _InferRequest({
    required this.replyPort,
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
    this.cropRect,
  });
}

/// Isolateから返る推論結果
class _InferResponse {
  final int? classIndex;
  final double? confidence;
  final double? expectedValue;
  final String? error;

  _InferResponse({
    this.classIndex,
    this.confidence,
    this.expectedValue,
    this.error,
  });
}

/// ExecuTorchモデル推論サービス
/// モデルの読み込みと推論を専用のバックグラウンドIsolateで実行する
class ModelService {
  static const String _modelPath = 'assets/models/avocado_ripeness_lite0.pte';
  static const int _inputSize = 224;
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std = [0.229, 0.224, 0.225];

  // 白背景の正規化済み値（事前計算）
  static final List<double> _whiteBgNormalized = [
    (1.0 - _mean[0]) / _std[0],
    (1.0 - _mean[1]) / _std[1],
    (1.0 - _mean[2]) / _std[2],
  ];

  Isolate? _isolate;
  SendPort? _sendPort;
  bool _isInitialized = false;

  /// バックグラウンドIsolateでモデルを初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('メインIsolate: アセットからモデルバイトを読み込み中...');
      final byteData = await rootBundle.load(_modelPath);
      final modelBytes = byteData.buffer.asUint8List();
      print('メインIsolate: モデルバイト読み込み完了 (${modelBytes.length} bytes)');

      final rootToken = RootIsolateToken.instance!;
      final receivePort = ReceivePort();

      _isolate = await Isolate.spawn(
        _isolateEntry,
        _IsolateInitParams(
          sendPort: receivePort.sendPort,
          rootToken: rootToken,
          modelBytes: modelBytes,
        ),
      );

      final firstMessage = await receivePort.first;
      if (firstMessage is SendPort) {
        _sendPort = firstMessage;
        _isInitialized = true;
        print('バックグラウンドIsolateでモデルの初期化が完了しました');
      } else if (firstMessage is String) {
        throw Exception(firstMessage);
      }
    } catch (e) {
      print('モデル初期化エラー: $e');
      throw Exception('モデルの読み込みに失敗しました: $e');
    }
  }

  /// 推論を実行（メインスレッドをブロックしない）
  Future<InferenceResult?> predictFromBuffer({
    required bool isBgra,
    Uint8List? bgraBytes,
    int? bgraBytesPerRow,
    Uint8List? yBytes,
    Uint8List? uBytes,
    Uint8List? vBytes,
    required int width,
    required int height,
    required int yBytesPerRow,
    required int uvBytesPerRow,
    required int uvPixelStride,
    CropRect? cropRect,
  }) async {
    if (!_isInitialized || _sendPort == null) return null;

    try {
      final responsePort = ReceivePort();

      _sendPort!.send(
        _InferRequest(
          replyPort: responsePort.sendPort,
          isBgra: isBgra,
          bgraBytes: isBgra ? Uint8List.fromList(bgraBytes!) : null,
          bgraBytesPerRow: bgraBytesPerRow,
          yBytes: !isBgra ? Uint8List.fromList(yBytes!) : null,
          uBytes: !isBgra ? Uint8List.fromList(uBytes!) : null,
          vBytes: !isBgra ? Uint8List.fromList(vBytes!) : null,
          width: width,
          height: height,
          yBytesPerRow: yBytesPerRow,
          uvBytesPerRow: uvBytesPerRow,
          uvPixelStride: uvPixelStride,
          cropRect: cropRect,
        ),
      );

      final response = await responsePort.first as _InferResponse;

      if (response.error != null) {
        print('推論エラー: ${response.error}');
        return null;
      }

      if (response.classIndex == null) return null;

      final expVal = response.expectedValue ?? 3.0;
      final normalized = ((expVal - 1.0) / 4.0).clamp(0.0, 1.0);
      final labelIndex = normalized < 0.2
          ? 0
          : normalized < 0.4
              ? 1
              : normalized < 0.6
                  ? 2
                  : normalized < 0.8
                      ? 3
                      : 4;

      return InferenceResult(
        classIndex: labelIndex,
        className: CLASS_NAMES[labelIndex] ?? 'Unknown',
        confidence: response.confidence ?? 0.0,
        expectedValue: expVal,
      );
    } catch (e) {
      print('推論エラー: $e');
      return null;
    }
  }

  /// リソースを解放
  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _isInitialized = false;
  }

  // ======== 以下はバックグラウンドIsolateで実行される ========

  static Future<void> _isolateEntry(_IsolateInitParams params) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(params.rootToken);

    try {
      print('バックグラウンドIsolate: ExecutorchManagerを初期化中...');
      await ExecutorchManager.instance.initialize();
      print('バックグラウンドIsolate: バイトからモデルを読み込み中...');
      final model = await ExecuTorchModel.loadFromBytes(params.modelBytes);
      print('バックグラウンドIsolate: モデル読み込み完了');

      final receivePort = ReceivePort();
      params.sendPort.send(receivePort.sendPort);

      await for (final message in receivePort) {
        if (message is _InferRequest) {
          final response = await _processRequest(model, message);
          message.replyPort.send(response);
        }
      }
    } catch (e) {
      print('バックグラウンドIsolateエラー: $e');
      params.sendPort.send('初期化エラー: $e');
    }
  }

  /// バックグラウンドIsolate内で前処理 + 推論を実行
  static Future<_InferResponse> _processRequest(
    ExecuTorchModel model,
    _InferRequest req,
  ) async {
    try {
      final inputTensor = _preprocess(req);

      final inputTensorData = TensorData(
        shape: [1, 3, _inputSize, _inputSize],
        dataType: TensorType.float32,
        data: inputTensor.buffer.asUint8List(),
      );

      final outputs = await model.forward([inputTensorData]);

      if (outputs.isEmpty) {
        return _InferResponse(error: '推論結果が空です');
      }

      final outputData = outputs[0].data.buffer.asFloat32List();
      final logits = outputData.toList();

      final expLogits = logits.map((x) => math.exp(x)).toList();
      final sumExp = expLogits.reduce((a, b) => a + b);
      final probabilities = expLogits.map((x) => x / sumExp).toList();

      double maxProb = 0.0;
      int maxIndex = 0;
      double expVal = 0.0;
      for (int i = 0; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
        // 期待値: クラス0→1, クラス1→2, ..., クラス4→5
        expVal += (i + 1) * probabilities[i];
      }

      return _InferResponse(
        classIndex: maxIndex,
        confidence: maxProb,
        expectedValue: expVal,
      );
    } catch (e) {
      return _InferResponse(error: '$e');
    }
  }

  /// 画像の前処理
  /// CropRectが指定されている場合:
  ///   1. 楕円領域内のピクセルを抽出
  ///   2. 楕円境界付近はフェザリング（カメラ画像と白背景をブレンド）
  ///   3. 楕円外は白背景(255,255,255)で埋める
  ///   4. Crop領域を224x224にリサイズして正規化
  static const double _featherWidth = 0.15;

  static Float32List _preprocess(_InferRequest req) {
    final totalSize = 3 * _inputSize * _inputSize;
    final tensor = Float32List(totalSize);
    final chSize = _inputSize * _inputSize;
    final crop = req.cropRect;

    if (crop != null && crop.width > 0 && crop.height > 0) {
      final scaleX = crop.width / _inputSize;
      final scaleY = crop.height / _inputSize;
      final cx = crop.centerX;
      final cy = crop.centerY;
      final rx = crop.radiusX;
      final ry = crop.radiusY;

      // フェザリング開始位置（楕円内側からブレンド開始）
      final featherStart = 1.0 - _featherWidth;

      for (int h = 0; h < _inputSize; h++) {
        for (int w = 0; w < _inputSize; w++) {
          final srcX = (crop.left + w * scaleX).round().clamp(0, req.width - 1);
          final srcY = (crop.top + h * scaleY).round().clamp(0, req.height - 1);

          final dx = (srcX - cx) / rx;
          final dy = (srcY - cy) / ry;
          final dist = dx * dx + dy * dy;

          final offset = h * _inputSize + w;

          if (dist <= featherStart * featherStart) {
            // 楕円内側: カメラ画像をそのまま使用
            _setPixelFromSource(tensor, offset, chSize, req, srcX, srcY);
          } else if (dist <= 1.0) {
            // フェザリング領域: カメラ画像と白背景をブレンド
            final d = math.sqrt(dist);
            final blend = (d - featherStart) / _featherWidth;
            _setBlendedPixel(tensor, offset, chSize, req, srcX, srcY, blend);
          } else {
            // 楕円外: 白背景
            tensor[offset] = _whiteBgNormalized[0];
            tensor[chSize + offset] = _whiteBgNormalized[1];
            tensor[chSize * 2 + offset] = _whiteBgNormalized[2];
          }
        }
      }
    } else {
      // Cropなし: 画像全体をリサイズ（従来動作）
      final scaleX = req.width / _inputSize;
      final scaleY = req.height / _inputSize;

      for (int h = 0; h < _inputSize; h++) {
        final srcY = (h * scaleY).toInt().clamp(0, req.height - 1);
        for (int w = 0; w < _inputSize; w++) {
          final srcX = (w * scaleX).toInt().clamp(0, req.width - 1);
          final offset = h * _inputSize + w;
          _setPixelFromSource(tensor, offset, chSize, req, srcX, srcY);
        }
      }
    }

    return tensor;
  }

  /// ソース画像のピクセルを正規化してテンソルに書き込む
  static void _setPixelFromSource(
    Float32List tensor,
    int offset,
    int chSize,
    _InferRequest req,
    int srcX,
    int srcY,
  ) {
    if (req.isBgra) {
      final i = srcY * req.bgraBytesPerRow! + srcX * 4;
      final bytes = req.bgraBytes!;
      tensor[offset] = (bytes[i + 2] / 255.0 - _mean[0]) / _std[0]; // R
      tensor[chSize + offset] =
          (bytes[i + 1] / 255.0 - _mean[1]) / _std[1]; // G
      tensor[chSize * 2 + offset] =
          (bytes[i] / 255.0 - _mean[2]) / _std[2]; // B
    } else {
      final yVal = req.yBytes![srcY * req.yBytesPerRow + srcX];
      final uvIdx =
          (srcY ~/ 2) * req.uvBytesPerRow + (srcX ~/ 2) * req.uvPixelStride;
      final uVal = req.uBytes![uvIdx];
      final vVal = req.vBytes![uvIdx];

      final r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.344 * (uVal - 128) - 0.714 * (vVal - 128))
          .round()
          .clamp(0, 255);
      final b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

      tensor[offset] = (r / 255.0 - _mean[0]) / _std[0];
      tensor[chSize + offset] = (g / 255.0 - _mean[1]) / _std[1];
      tensor[chSize * 2 + offset] = (b / 255.0 - _mean[2]) / _std[2];
    }
  }

  /// フェザリング: カメラ画像と白背景をブレンドしてテンソルに書き込む
  /// blend: 0.0 = カメラ画像のみ, 1.0 = 白背景のみ
  static void _setBlendedPixel(
    Float32List tensor,
    int offset,
    int chSize,
    _InferRequest req,
    int srcX,
    int srcY,
    double blend,
  ) {
    final b = blend.clamp(0.0, 1.0);
    final a = 1.0 - b;

    double rNorm, gNorm, bNorm;

    if (req.isBgra) {
      final i = srcY * req.bgraBytesPerRow! + srcX * 4;
      final bytes = req.bgraBytes!;
      rNorm = (bytes[i + 2] / 255.0 - _mean[0]) / _std[0];
      gNorm = (bytes[i + 1] / 255.0 - _mean[1]) / _std[1];
      bNorm = (bytes[i] / 255.0 - _mean[2]) / _std[2];
    } else {
      final yVal = req.yBytes![srcY * req.yBytesPerRow + srcX];
      final uvIdx =
          (srcY ~/ 2) * req.uvBytesPerRow + (srcX ~/ 2) * req.uvPixelStride;
      final uVal = req.uBytes![uvIdx];
      final vVal = req.vBytes![uvIdx];

      final r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.344 * (uVal - 128) - 0.714 * (vVal - 128))
          .round()
          .clamp(0, 255);
      final bv = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

      rNorm = (r / 255.0 - _mean[0]) / _std[0];
      gNorm = (g / 255.0 - _mean[1]) / _std[1];
      bNorm = (bv / 255.0 - _mean[2]) / _std[2];
    }

    tensor[offset] = a * rNorm + b * _whiteBgNormalized[0];
    tensor[chSize + offset] = a * gNorm + b * _whiteBgNormalized[1];
    tensor[chSize * 2 + offset] = a * bNorm + b * _whiteBgNormalized[2];
  }
}

/// バックグラウンドIsolateの初期化パラメータ
class _IsolateInitParams {
  final SendPort sendPort;
  final RootIsolateToken rootToken;
  final Uint8List modelBytes;

  _IsolateInitParams({
    required this.sendPort,
    required this.rootToken,
    required this.modelBytes,
  });
}

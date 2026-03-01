import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import '../constants/app_constants.dart';
import '../services/model_service.dart';

/// コピー済みフレームデータ
class FrameData {
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

  FrameData({
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

/// カメラ画像座標でのCrop矩形を計算する
///
/// FittedBox(cover)による表示変換を考慮し、画面上の楕円外接矩形を
/// カメラ画像のピクセル座標に変換する。
CropRect computeCropRect(CameraController controller) {
  final screenSize =
      WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  final screenW = screenSize.width;
  final screenH = screenSize.height;

  // カメラのプレビューサイズ（横向き基準なのでPortrait用に入れ替え）
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
  final ovalW = screenW * GuideOval.widthRatio;
  final ovalH = screenH * GuideOval.heightRatio;
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

/// CameraImageからデータをコピー
FrameData copyFrameData(CameraImage image) {
  if (image.format.group == ImageFormatGroup.bgra8888) {
    return FrameData(
      isBgra: true,
      bgraBytes: Uint8List.fromList(image.planes[0].bytes),
      bgraBytesPerRow: image.planes[0].bytesPerRow,
      width: image.width,
      height: image.height,
    );
  }

  return FrameData(
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

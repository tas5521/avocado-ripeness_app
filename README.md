# アボカド熟度チェッカー

カメラでアボカドを撮影し、端末上の ExecuTorch モデルで熟度を推定する Flutter アプリです。

## 主な機能

- カメラのリアルタイム映像から推論（バックグラウンド Isolate で実行）
- 楕円ガイドに合わせた撮影を想定した UI
- 3 クラス分類に基づく表示と、期待値に連動した熟度バー
- 初回起動時の免責事項ダイアログ、About（データセット・ライセンス情報への導線）
- カメラ権限の案内（拒否時は設定への導線）

## 技術スタック

- **Flutter** / **Dart**（SDK: `^3.10.4`、[`avocado_ripeness_app/pubspec.yaml`](avocado_ripeness_app/pubspec.yaml) を参照）
- **機械学習推論**: [executorch_flutter](https://pub.dev/packages/executorch_flutter)（ExecuTorch、`.pte` モデル）
- **その他主要依存**: `camera`、`flutter_hooks`、`flutter_screenutil`、`image`、`permission_handler`、`app_settings`、`shared_preferences`

## 前提条件

- Flutter SDK（安定版の利用を推奨）
- **iOS**: Xcode、デプロイメントターゲット **iOS 13.0** 以上（[`avocado_ripeness_app/ios/Podfile`](avocado_ripeness_app/ios/Podfile) と Xcode プロジェクトの設定に合わせています）
- **Android**: Android SDK / エミュレータまたは実機

カメラを使うため、推論の確認は実機を推奨します。

## セットアップと実行

リポジトリ直下から Flutter プロジェクトディレクトリに移動して依存関係を取得し、実行します。

```bash
cd avocado_ripeness_app
flutter pub get
flutter run
```

## リリースビルド（概要）

- **Android**: 例として `flutter build apk` または `flutter build appbundle`
- **iOS**: 例として `flutter build ipa`（App Store 配布用）

コード署名、プロビジョニング、App Store Connect への登録は、Apple Developer アカウントと Xcode の設定に従ってください。

## モデルアセット

学習済みモデル（`.pte`）は [`avocado_ripeness_app/assets/models/`](avocado_ripeness_app/assets/models/) に配置します。アプリは既定で `assets/models/efficientnet_lite0.pte` を読み込みます（[`lib/services/model_service.dart`](avocado_ripeness_app/lib/services/model_service.dart)）。

リポジトリに大きなモデルを含めない場合は、各自で該当パスにファイルを置いてください。`pubspec.yaml` の `flutter.assets` に `assets/models/` が含まれている必要があります。

## 免責事項

本アプリの表示は参考用の推定であり、アボカドの鮮度・食味・安全性などを保証するものではありません。購入・摂取の判断は自己責任で行ってください。

## ライセンス・サードパーティ

- 本リポジトリのライセンスはリポジトリ直下の [LICENSE](LICENSE)（Apache License 2.0）を参照してください。
- オンデバイス推論には [executorch_flutter](https://pub.dev/packages/executorch_flutter) および PyTorch ExecuTorch エコシステムが関係します。各パッケージのライセンスは配布元に従います。

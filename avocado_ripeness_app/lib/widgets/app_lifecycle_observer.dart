import 'package:flutter/widgets.dart';

/// アプリのライフサイクルを監視し、バックグラウンド/フォアグラウンドを検知
class AppLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onPause;
  final VoidCallback onResume;

  AppLifecycleObserver({required this.onPause, required this.onResume});

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

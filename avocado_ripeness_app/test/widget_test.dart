import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:avocado_ripeness_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(cameras: <CameraDescription>[]));
    expect(find.text('カメラが見つかりません'), findsNothing);
  });
}

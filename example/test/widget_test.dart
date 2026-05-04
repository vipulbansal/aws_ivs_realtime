import 'package:aws_ivs_realtime_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Lobby loads', (WidgetTester tester) async {
    await tester.pumpWidget(const IvsDemoApp());
    expect(find.textContaining('IVS Real-Time'), findsWidgets);
  });
}

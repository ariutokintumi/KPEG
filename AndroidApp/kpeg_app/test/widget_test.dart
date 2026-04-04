import 'package:flutter_test/flutter_test.dart';
import 'package:kpeg_app/main.dart';

void main() {
  testWidgets('App launches with bottom navigation', (tester) async {
    await tester.pumpWidget(const KpegApp());

    expect(find.text('Captura'), findsOneWidget);
    expect(find.text('Galería'), findsOneWidget);
    expect(find.text('Personas'), findsOneWidget);
  });
}

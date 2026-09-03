import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chords_app/main.dart';

void main() {
  testWidgets('arranca mostrando un cargador mientras carga el catálogo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ChordsApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

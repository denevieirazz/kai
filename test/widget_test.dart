// Smoke test do Hub Arsenal.
//
// Verifica que o app sobe e renderiza a navegação principal sem crashar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hub_app/main.dart';

void main() {
  testWidgets('Hub boots and shows navigation', (WidgetTester tester) async {
    // Tela larga pra garantir que a sidebar (desktop) aparece.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HubApp());
    await tester.pump();

    // Marca do app e itens de navegação visíveis.
    expect(find.text('HUB'), findsOneWidget);
    expect(find.text('Tarefas'), findsWidgets);
    expect(find.text('Mapa Mental'), findsWidgets);
  });
}

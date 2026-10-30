import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/widgets/scroll_edge_fade.dart';

void main() {
  testWidgets('a scrolling edge gets a mask and keeps scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 120,
              child: ScrollEdgeFade(
                child: ListView.builder(
                  itemCount: 40,
                  itemBuilder: (context, index) => SizedBox(
                    height: 32,
                    child: Text('row $index'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShaderMask), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}

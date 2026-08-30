import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunset_ripple/ui/transitions/stage_choreography.dart';

void main() {
  group('StageChoreography 编排表', () {
    test('三段区间按预期重叠，中间不留空档', () {
      // 首页最后一个元素还没走完，背景就该动起来了。
      final lastExit = StageChoreography.homeExit(4);
      expect(lastExit.end, greaterThan(0.18));

      // 背景快停稳时房间元素已经开始进场，否则会看到一段静止的空画面。
      final firstEnter = StageChoreography.roomEnter(0);
      expect(firstEnter.begin, lessThan(0.72));

      // 最后一个房间元素必须在整段转场结束前落位。
      final lastEnter = StageChoreography.roomEnter(2);
      expect(lastEnter.end, lessThanOrEqualTo(1.0));
    });

    test('离场顺序自上而下，入场顺序也自上而下', () {
      expect(
        StageChoreography.homeExit(0).begin,
        lessThan(StageChoreography.homeExit(1).begin),
      );
      expect(
        StageChoreography.roomEnter(0).begin,
        lessThan(StageChoreography.roomEnter(1).begin),
      );
    });
  });

  group('转场端点状态', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('stage=0 时首页元素在、房间元素不可见', (tester) async {
      await tester.pumpWidget(host(
        const Column(children: [
          StageExitItem(stage: 0.0, index: 0, child: Text('首页')),
          StageEnterItem(stage: 0.0, index: 0, child: Text('房间')),
        ]),
      ));

      expect(find.text('首页'), findsOneWidget);
      // 房间元素仍在树里占位，但透明度为 0。
      final enterOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('房间'), matching: find.byType(Opacity)).first,
      );
      expect(enterOpacity.opacity, 0.0);
    });

    testWidgets('stage=1 时首页元素已撤走、房间元素完全落位', (tester) async {
      await tester.pumpWidget(host(
        const Column(children: [
          StageExitItem(stage: 1.0, index: 0, child: Text('首页')),
          StageEnterItem(stage: 1.0, index: 0, child: Text('房间')),
        ]),
      ));

      expect(find.text('首页'), findsNothing);
      expect(find.text('房间'), findsOneWidget);
      // 落位后不该再残留 Opacity/Transform 这些转场包装。
      expect(
        find.ancestor(of: find.text('房间'), matching: find.byType(Opacity)),
        findsNothing,
      );
    });
  });
}

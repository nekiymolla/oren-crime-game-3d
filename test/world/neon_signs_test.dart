import 'dart:convert';
import 'dart:io';

import 'package:crime_oren/world/neon_signs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('соседние вывески с разными надписями, панель в пропорции текстуры', () {
    for (var i = 0; i < 40; i++) {
      expect(neonSignText(i), isNotEmpty);
      expect(neonSignText(i), isNot(neonSignText(i + 1)));
    }
    expect(neonPanelHeight(4.4), closeTo(1.1, 1e-9));
  });

  test('вывески из пайплайна читаются и не толпятся', () {
    final json = jsonDecode(File('assets/data/neon_signs.json').readAsStringSync()) as Map<String, dynamic>;
    final signs = [for (final s in json['signs'] as List) NeonSign.fromJson(s as Map<String, dynamic>)];
    expect(signs.length, greaterThan(10));
    for (final s in signs) {
      expect(s.normal.length, closeTo(1.0, 0.01));
      expect(s.color, inInclusiveRange(0, neonPalette.length - 1));
    }
    // Неон — акцент: соседние вывески не ближе 35 м (filter_neon_signs.mjs).
    for (var i = 0; i < signs.length; i++) {
      for (var j = i + 1; j < signs.length; j++) {
        expect((signs[i].wallPoint - signs[j].wallPoint).length, greaterThanOrEqualTo(35));
      }
    }
  });
}

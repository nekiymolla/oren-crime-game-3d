// Run against a profile/debug VM service; writes raw data for later inspection.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';
import 'package:vm_service/vm_service.dart';

Future<void> main(List<String> args) async {
  final uri = Uri.parse(args[0]);
  final service = await vmServiceConnectUri(
    uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
  );
  try {
    final vm = await service.getVM();
    final id = vm.isolates!.firstWhere((i) => i.name == 'main').id!;
    await service.setFlag('profiler', 'true');
    await service.clearCpuSamples(id);
    await Future<void>.delayed(
      Duration(seconds: args.length > 1 ? int.parse(args[1]) : 15),
    );
    final samples = await service.getCpuSamples(id, 0, 1 << 62);
    File(
      args.length > 2 ? args[2] : '/tmp/crime-cpu.json',
    ).writeAsStringSync(jsonEncode(samples.toJson()));
    final functions = samples.functions!
      ..sort(
        (a, b) => (b.exclusiveTicks ?? 0).compareTo(a.exclusiveTicks ?? 0),
      );
    print('samples=${samples.sampleCount}');
    for (final f in functions.take(35)) {
      print(
        '${f.exclusiveTicks} self / ${f.inclusiveTicks} total: ${f.function is FuncRef ? (f.function as FuncRef).name : f.function} ${f.resolvedUrl}',
      );
    }
  } finally {
    await service.dispose();
  }
}

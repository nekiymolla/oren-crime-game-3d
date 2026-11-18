// Developer-only inspection of a running debug build. No test controls are
// shipped in the game. Uses the VM service URL printed by `flutter run`.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tools/qa/inspect_game.dart <VM service URL> <expression | --smoke>',
    );
    exitCode = 64;
    return;
  }
  final uri = Uri.parse(args.first);
  final socket = uri.replace(
    scheme: uri.scheme == 'https' || uri.scheme == 'wss' ? 'wss' : 'ws',
    path: uri.path.endsWith('/ws')
        ? uri.path
        : '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}ws',
  );
  final service = await vmServiceConnectUri(socket.toString());
  try {
    final vm = await service.getVM();
    final isolateRef = vm.isolates!.firstWhere((i) => i.name == 'main');
    final isolateId = isolateRef.id!;
    final isolate = await service.getIsolate(isolateId);
    Future<String> instance(String path, String name) async {
      final ref = isolate.libraries!.firstWhere(
        (l) => l.uri == 'package:crime_oren/$path',
      );
      final library = await service.getObject(isolateId, ref.id!) as Library;
      final type = library.classes!.firstWhere((c) => c.name == name);
      final instances = await service.getInstances(isolateId, type.id!, 1);
      if (instances.instances!.isEmpty) throw StateError('$name is not loaded');
      return instances.instances!.first.id!;
    }

    final game = args.contains('--hud')
        ? await instance('ui/hud/game_hud.dart', '_GameHudState')
        : args.contains('--audio')
        ? await instance('audio/audio_system.dart', 'AudioSystem')
        : args.contains('--trees')
        ? await instance('world/vegetation.dart', 'VegetationBatch')
        : args.contains('--facades')
        ? await instance('world/building_facades.dart', 'BuildingFacades')
        : args.contains('--fps')
        ? await instance('engine/debug/fps_overlay.dart', '_FpsOverlayState')
        : args.contains('--app')
        ? isolate.libraries!
              .firstWhere((l) => l.uri == 'package:crime_oren/main.dart')
              .id!
        : await instance('engine/game.dart', 'Game');
    Future<String> eval(String expression, [String? target]) async {
      final result = await service.evaluate(
        isolateId,
        target ?? game,
        expression,
      );
      if (result is ErrorRef) {
        throw StateError('${result.kind}: ${result.message}');
      }
      if (result is InstanceRef) {
        if (result.valueAsStringIsTruncated == true) {
          final full =
              await service.getObject(
                    isolateId,
                    result.id!,
                    count: result.length ?? 1000000,
                  )
                  as Instance;
          return full.valueAsString!;
        }
        return result.valueAsString ?? result.toJson().toString();
      }
      return result.toJson().toString();
    }

    Future<void> captureSimulator(String path) async {
      if (vm.operatingSystem != 'ios') {
        print(
          'INFO: screenshot skipped on ${vm.operatingSystem}; VM checks still run',
        );
        return;
      }
      final result = await Process.run('xcrun', [
        'simctl',
        'io',
        'BBA66C99-1756-4D0B-8E7B-2E797F9284F0',
        'screenshot',
        path,
      ]);
      if (result.exitCode != 0) {
        throw StateError('Simulator screenshot failed: ${result.stderr}');
      }
    }

    if (args[1] == '--stream-stats') {
      final library = isolate.libraries!
          .firstWhere(
            (l) =>
                l.uri == 'package:crime_oren/world/streaming_diagnostics.dart',
          )
          .id!;
      final report = await eval('StreamingDiagnostics.json', library);
      if (args.length > 2) await File(args[2]).writeAsString(report);
      final rows = jsonDecode(report) as List;
      final stages = <String, List<double>>{};
      for (final row in rows) {
        stages
            .putIfAbsent(row['stage'], () => [])
            .add((row['elapsedUs'] as num) / 1000);
      }
      for (final entry in stages.entries) {
        entry.value.sort();
        print(
          '${entry.key}: n=${entry.value.length}, max=${entry.value.last.toStringAsFixed(2)}ms, median=${entry.value[entry.value.length ~/ 2].toStringAsFixed(2)}ms',
        );
      }
      return;
    }
    if (args[1] == '--frames') {
      await service.setFlag('profiler', 'false');
      final fps = await instance(
        'engine/debug/fps_overlay.dart',
        '_FpsOverlayState',
      );
      for (var i = 0; i < (args.length > 2 ? int.parse(args[2]) : 5); i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        print(
          await eval(
            r'"fps=$_fps interval=$_frameMs p95=$_p95Ms latency=$_latencyMs ui=$_uiMs raster=$_rasterMs"',
            fps,
          ),
        );
      }
      return;
    }
    if (args[1] == '--profile') {
      await service.setFlag('profiler', 'true');
      final start = (await service.getVMTimelineMicros()).timestamp!;
      await Future<void>.delayed(const Duration(seconds: 8));
      final end = (await service.getVMTimelineMicros()).timestamp!;
      final samples = await service.getCpuSamples(
        isolateId,
        start,
        end - start,
      );
      final functions = samples.functions!;
      final exclusive = <int, int>{}, inclusive = <int, int>{};
      for (final sample in samples.samples!) {
        final stack = sample.stack ?? [];
        if (stack.isNotEmpty) {
          exclusive.update(stack.first, (n) => n + 1, ifAbsent: () => 1);
        }
        for (final index in stack.toSet()) {
          inclusive.update(index, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      print('samples=${samples.sampleCount}');
      for (final data in [exclusive, inclusive]) {
        final entries = data.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        print(data == exclusive ? 'EXCLUSIVE' : 'INCLUSIVE');
        for (final entry in entries.take(22)) {
          print('${entry.value}: ${functions[entry.key].function?.name}');
        }
      }
      await File(
        args.length > 2 ? args[2] : '/tmp/crime-cpu.json',
      ).writeAsString(jsonEncode(samples.toJson()));
      await service.setFlag('profiler', 'false');
      return;
    }
    if (args[1] == '--desktop-smoke') {
      final hud = await instance('ui/hud/game_hud.dart', '_GameHudState');
      void check(bool ok, String message) {
        if (!ok) throw StateError('FAIL: $message');
        print('PASS: $message');
      }

      check(await eval('_ready', hud) == 'true', 'desktop scene loaded');
      check(
        await eval('desktopControls', hud) == 'true',
        'desktop HUD selected',
      );
      check(
        await eval('gameModeState.mode == ControlMode.onFoot && !isDead') ==
            'true',
        'desktop inspection starts on foot',
      );
      final position = await eval(
        r'"${playerNode.position.x},${playerNode.position.y},${playerNode.position.z}"',
      );
      final paused = await eval('_paused', hud);
      try {
        await eval('Future.microtask(()=>_setPaused(true))', hud);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final hours = await eval('clock.hours');
        final start = await eval('playerNode.position.toString()');
        await eval('inputState.setMove(0,1)');
        await Future<void>.delayed(const Duration(seconds: 1));
        check(await eval('clock.hours') == hours, 'pause freezes game clock');
        check(
          await eval('playerNode.position.toString()') == start,
          'pause freezes scene components',
        );
        await eval('Future.microtask(()=>_setPaused(false))', hud);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await eval(
          '(() { inputState.setMove(0,1); inputState.isRunning=false; return true; })()',
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await eval('inputState.setMove(0,0)');
        final travelled = double.parse(
          await eval('(playerNode.position-vm.Vector3($position)).length'),
        );
        check(
          travelled > .25 && travelled < 2.5,
          'movement resumes without a time jump: ${travelled.toStringAsFixed(2)}m',
        );
        await eval('inputState.aimHeld=true');
        final ammo = await eval('weapon.ammoInMagazine');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        check(
          await eval('cameraController.aiming') == 'true',
          'mouse aim engages shoulder camera',
        );
        check(
          await eval('weapon.ammoInMagazine') == ammo,
          'aiming alone does not fire',
        );
      } finally {
        await eval(
          '(() { inputState.reset(); _movement!.teleport(vm.Vector3($position)); return true; })()',
        );
        await eval('Future.microtask(()=>_setPaused($paused))', hud);
      }
      return;
    }
    if (args[1] == '--vehicle-smoke') {
      final hud = await instance('ui/hud/game_hud.dart', '_GameHudState');
      void check(bool ok, String message) {
        if (!ok) throw StateError('FAIL: $message');
        print('PASS: $message');
      }

      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (await eval('_ready', hud) != 'true') {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Scene load timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      Future<void> run(String code, {int wait = 200}) async {
        await eval('Future.microtask(() {$code})');
        await Future<void>.delayed(Duration(milliseconds: wait));
      }

      final original = await eval(
        r'"${vehicle.node.position.x},${vehicle.node.position.y},${vehicle.node.position.z}"',
      );
      final targetPosition = await eval(
        r'"${_parkedPlayerCars.first.node.position.x},${_parkedPlayerCars.first.node.position.y},${_parkedPlayerCars.first.node.position.z}"',
      );
      final hours = await eval('clock.hours'),
          rate = await eval('clock.gameMinutesPerSecond');
      await eval('Future.microtask(()=>_setPaused(false))', hud);
      try {
        await run(
          'inputState.reset(); wantedState.stars=0; clock.hours=13; clock.gameMinutesPerSecond=0; playerHealth.health=100; _hookCrashSound(vehicle); gameModeState.mode=ControlMode.driving; gameModeState.activeVehicle=vehicle.controller; _playerMeshNode!.visible=false; cameraController.followTarget=vehicle.node;',
        );
        await eval('Future.microtask(()=>setState((){}))', hud);
        check(
          await eval('vehicle.controller.maxSpeed') !=
              await eval('_parkedPlayerCars.first.controller.maxSpeed'),
          'parked compact and starter sedan have different profiles',
        );
        await run(
          'final p=cityMap.facadeProfiles.first; final normal=vm.Vector3(p.entrance.z,0,p.entrance.w); vehicle.node.position=vm.Vector3(p.entrance.x,0,p.entrance.y)+normal*8; vehicle.controller.heading=math.atan2(-normal.x,-normal.z); vehicle.controller.dynamics.stopYaw(); vehicle.controller.velocityXZ.setZero(); cameraController.orbitBy(vehicle.controller.heading-cameraController.yaw,.22-cameraController.pitch);',
        );
        await run(
          'final p=cityMap.facadeProfiles.first; vehicle.controller.velocityXZ.setValues(-p.entrance.z*10,-p.entrance.w*10);',
          wait: 1100,
        );
        check(
          double.parse(await eval('vehicle.damage.accumulatedImpact')) > 2.5,
          'real mapped wall records an impact',
        );
        check(
          int.parse(await eval('vehicle.deformation.zones.length')) > 0,
          'impact creates a local dent',
        );
        print(
          'INFO: wall rebound speed=${await eval('vehicle.controller.speed')}',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        check(
          double.parse(await eval('vehicle.deformation.maxDisplacement')) >
              .025,
          'impact deforms actual vertices, not only paint',
        );
        await run(
          'inputState.reset(); wantedState.stars=0; final c=_parkedPlayerCars.first; vehicle.node.position=vm.Vector3(900,0,900);vehicle.controller.heading=0;vehicle.controller.dynamics.stopYaw();vehicle.controller.velocityXZ.setZero(); c.node.position=vm.Vector3(900,0,910);c.controller.heading=0;c.controller.velocityXZ.setZero();c.controller.dynamics.stopYaw();cameraController.orbitBy(-cameraController.yaw,.22-cameraController.pitch);',
          wait: 700,
        );
        await run('vehicle.controller.velocityXZ.setValues(0,12);', wait: 1000);
        final targetMoved =
            double.parse(
              await eval('_parkedPlayerCars.first.node.position.z'),
            ) -
            910;
        check(
          targetMoved > .2,
          'rear impact pushes the other car: ${targetMoved.toStringAsFixed(2)}m',
        );
        check(
          double.parse(await eval('vehicle.controller.speed')) > 1,
          'striking car retains motion after a two-body collision',
        );
        check(
          int.parse(
                await eval('_parkedPlayerCars.first.deformation.zones.length'),
              ) >
              0,
          'struck car receives visible damage',
        );
        print(
          'INFO: two-car speeds ${await eval('vehicle.controller.speed')} / ${await eval('_parkedPlayerCars.first.controller.speed')}',
        );
      } finally {
        await run(
          'inputState.reset(); wantedState.stars=0; vehicle.controller.velocityXZ.setZero();vehicle.controller.dynamics.stopYaw();vehicle.node.position=vm.Vector3($original);final c=_parkedPlayerCars.first;c.controller.velocityXZ.setZero();c.controller.dynamics.stopYaw();c.node.position=vm.Vector3($targetPosition);clock.hours=$hours;clock.gameMinutesPerSecond=$rate;gameModeState.mode=ControlMode.onFoot;_playerMeshNode!.visible=true;cameraController.followTarget=playerNode;',
        );
        await eval('Future.microtask(()=>setState((){}))', hud);
      }
      return;
    }
    if (args[1] == '--areas-smoke') {
      void check(bool ok, String label) {
        if (!ok) throw StateError('FAIL: $label');
        print('PASS: $label');
      }

      final hud = await instance('ui/hud/game_hud.dart', '_GameHudState');
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (await eval('_ready', hud) != 'true') {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Scene not ready');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final data =
          jsonDecode(await File('assets/data/city_map.json').readAsString())
              as Map<String, dynamic>;
      final position = await eval(
        r'"${playerNode.position.x},${playerNode.position.y},${playerNode.position.z}"',
      );
      final hours = await eval('clock.hours'),
          rate = await eval('clock.gameMinutesPerSecond');
      final yaw = await eval('cameraController.yaw'),
          pitch = await eval('cameraController.pitch');
      final prefix = args.length > 2 ? args[2] : '/tmp/crime-areas';
      check(
        await eval('gameModeState.mode == ControlMode.onFoot && !isDead') ==
            'true',
        'area inspection starts on foot',
      );
      check(
        await eval('cityMap.barriers.length') ==
            (data['barriers'] as List)
                .fold<int>(0, (n, f) => n + (f['sections'] as List).length)
                .toString(),
        'all railing collision sections loaded',
      );
      try {
        await eval(
          '(() { inputState.setMove(0,0); inputState.isRunning=false; clock.hours=13; clock.gameMinutesPerSecond=0; return true; })()',
        );
        final fences = data['barriers'] as List;
        final fence = fences.first, section = (fence['sections'] as List).first;
        final ax = (section['a'][0] as num).toDouble(),
            az = (section['a'][1] as num).toDouble();
        final bx = (section['b'][0] as num).toDouble(),
            bz = (section['b'][1] as num).toDouble();
        final mx = (ax + bx) / 2,
            mz = (az + bz) / 2,
            length = math.sqrt(math.pow(bx - ax, 2) + math.pow(bz - az, 2));
        var nx = -(bz - az) / length, nz = (bx - ax) / length;
        final area = (data['areas'] as List).firstWhere(
          (a) => a['osm'] == fence['basis'],
        );
        if (((area['center'][0] as num) - mx) * nx +
                ((area['center'][1] as num) - mz) * nz <
            0) {
          nx = -nx;
          nz = -nz;
        }
        final heading = math.atan2(nx, nz);
        await eval(
          '(() { _movement!.teleport(vm.Vector3(${mx - nx * 2},${section['y']},${mz - nz * 2})); cameraController.orbitBy($heading-cameraController.yaw,.2-cameraController.pitch); return true; })()',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        await eval(
          '(() { inputState.setMove(0,1); inputState.isRunning=true; return true; })()',
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await eval('inputState.setMove(0,0)');
        final side = double.parse(
          await eval(
            '(playerNode.position.x-($mx))*$nx+(playerNode.position.z-($mz))*$nz',
          ),
        );
        check(
          side < -.4,
          'running stops outside an authored railing: ${side.toStringAsFixed(2)}m',
        );
        final gate = fence['gate']['point'];
        final gx = (gate[0] as num).toDouble(),
            gz = (gate[1] as num).toDouble();
        final dx = (area['center'][0] as num).toDouble() - gx,
            dz = (area['center'][1] as num).toDouble() - gz,
            gl = math.sqrt(dx * dx + dz * dz),
            ux = dx / gl,
            uz = dz / gl,
            gh = math.atan2(ux, uz);
        await eval(
          '(() { inputState.isRunning=false; _movement!.teleport(vm.Vector3(${gx - ux * 1.3},0,${gz - uz * 1.3})); cameraController.orbitBy($gh-cameraController.yaw,.2-cameraController.pitch); return true; })()',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await eval('inputState.setMove(0,1)');
        await Future<void>.delayed(const Duration(milliseconds: 1800));
        await eval('inputState.setMove(0,0)');
        final progress = double.parse(
          await eval(
            '(playerNode.position.x-($gx))*$ux+(playerNode.position.z-($gz))*$uz',
          ),
        );
        check(progress > .6, 'player walks through the gate into the court');
        for (final source in [
          'way/1153941648',
          'way/1162516950',
          'way/1162516951',
        ]) {
          final area = (data['areas'] as List).firstWhere(
            (a) => a['osm'] == source,
          );
          final points = (area['points'] as List).sublist(
            0,
            (area['points'] as List).length - 1,
          );
          var best = -1.0, fx = 0.0, fz = 1.0;
          for (var i = 0; i < points.length; i++) {
            final a = points[i], b = points[(i + 1) % points.length];
            final dx = (b[0] as num).toDouble() - (a[0] as num),
                dz = (b[1] as num).toDouble() - (a[1] as num),
                len = math.sqrt(dx * dx + dz * dz);
            if (len > best) {
              best = len;
              fx = dx / len;
              fz = dz / len;
            }
          }
          final x = (area['center'][0] as num).toDouble() - fz * 3.5 - fx * 3,
              z = (area['center'][1] as num).toDouble() + fx * 3.5 - fz * 3,
              angle = math.atan2(fx, fz);
          await eval(
            '(() { _movement!.teleport(vm.Vector3($x,0,$z)); cameraController.orbitBy($angle-cameraController.yaw,.28-cameraController.pitch); return true; })()',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          check(
            await eval(
                  'districtStreamer._preparing.isEmpty && districtStreamer._loading.isEmpty',
                ) ==
                'true',
            'area geometry finished streaming: $source',
          );
          if (source == 'way/1153941648' || source == 'way/1162516951') {
            final surface = source == 'way/1153941648'
                ? 'CityCourtSurface'
                : 'CitySkateSurface';
            check(
              await eval(
                    '(() { for(final chunk in districtStreamer._loaded.values) { for(final n in chunk.meshNodes) { if(n.name=="$surface")return true; } } return false; })()',
                  ) ==
                  'true',
              'hard surface loaded: $surface',
            );
            final cx = area['center'][0], cz = area['center'][1];
            check(
              await eval('terrain.heightAt($cx,$cz).abs()<.01') == 'true',
              'terrain stays below the playing surface',
            );
          }
          await captureSimulator('$prefix-${source.split('/').last}.png');
        }
        {
          final bank = (data['equipment'] as List).firstWhere(
            (e) => e['kind'] == 'skate_bank',
          );
          final area = (data['areas'] as List).firstWhere(
            (a) => a['osm'] == bank['basis'],
          );
          final direction =
              (bank['point'][1] as num) < (area['center'][1] as num)
              ? 1.0
              : -1.0;
          final angle = (bank['yaw'] as num).toDouble(),
              heading = angle + (direction > 0 ? 0 : math.pi);
          final x =
                  (bank['point'][0] as num) - math.sin(angle) * direction * 2.3,
              z = (bank['point'][1] as num) - math.cos(angle) * direction * 2.3;
          await eval(
            '(() { _movement!.teleport(vm.Vector3($x,0,$z)); cameraController.orbitBy($heading-cameraController.yaw,.2-cameraController.pitch); return true; })()',
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await eval('inputState.setMove(0,1)');
          var maximum = 0.0;
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            maximum = math.max(
              maximum,
              double.parse(await eval('playerNode.position.y')),
            );
          }
          await eval('inputState.setMove(0,0)');
          check(
            maximum > .7,
            'player walks up curved skate surface: ${maximum.toStringAsFixed(2)}m',
          );
        }
      } finally {
        await eval(
          '(() { inputState.setMove(0,0); inputState.isRunning=false; clock.hours=$hours; clock.gameMinutesPerSecond=$rate; _movement!.teleport(vm.Vector3($position)); cameraController.orbitBy($yaw-cameraController.yaw,$pitch-cameraController.pitch); return true; })()',
        );
      }
      return;
    }
    if (args[1] == '--city-smoke') {
      void check(bool ok, String label) {
        if (!ok) throw StateError('FAIL: $label');
        print('PASS: $label');
      }

      final position = await eval(
        r'"${playerNode.position.x},${playerNode.position.y},${playerNode.position.z}"',
      );
      final hours = await eval('clock.hours');
      final rate = await eval('clock.gameMinutesPerSecond');
      final health = await eval('playerHealth.health');
      final armor = await eval('playerHealth.armor');
      check(
        await eval('gameModeState.mode == ControlMode.onFoot && !isDead') ==
            'true',
        'city inspection starts on foot',
      );
      try {
        await eval(
          '(() { inputState.setMove(0,0); inputState.isRunning=false; clock.hours=23; clock.gameMinutesPerSecond=0; final b=cityMap.nearby("bench", playerNode.position.x, playerNode.position.z,radius:150,limit:1).first; _movement!.teleport(b.position+vm.Vector3(math.sin(b.yaw)*1.5,0,math.cos(b.yaw)*1.5)); return true; })()',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        check(
          await eval('nearbyBench != null') == 'true',
          'bench interaction appears at real scene position',
        );
        check(
          await eval(
                'streetLights.selected.isNotEmpty && streetLights._lights.any((SpotLight l)=>l.intensity>50)',
              ) ==
              'true',
          'nearest street lights illuminate night scene',
        );
        final prefix = args.length > 2 ? args[2] : '/tmp/crime-city';
        await captureSimulator('$prefix-night.png');
        await eval(
          '(() { playerHealth.takeDamage(1); playerHealth.health=40; restAtBench(); return true; })()',
        );
        check(await eval('benchRest.active') == 'true', 'bench rest starts');
        await Future<void>.delayed(const Duration(seconds: 6));
        check(
          await eval('!benchRest.active && playerHealth.health>=59') == 'true',
          'rest completes and restores health',
        );
        await eval(
          '(() { restAtBench(); _movement!.teleport(playerNode.position+vm.Vector3(1.2,0,0)); return true; })()',
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        check(
          await eval('!benchRest.active') == 'true',
          'walking away cancels rest',
        );
        await eval(
          '(() { final b=cityMap.nearby("bench",playerNode.position.x,playerNode.position.z,radius:10,limit:1).first; _movement!.teleport(b.position+vm.Vector3(math.sin(b.yaw)*1.5,0,math.cos(b.yaw)*1.5)); return true; })()',
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await eval(
          '(() { playerHealth.addArmor(10); restAtBench(); playerHealth.takeDamage(1); return true; })()',
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        check(
          await eval('!benchRest.active') == 'true',
          'armour damage cancels rest',
        );
        await eval('clock.hours=13');
        await Future<void>.delayed(const Duration(seconds: 1));
        check(
          await eval(
                'streetLights._lights.every((SpotLight l)=>l.intensity<.01)',
              ) ==
              'true',
          'street lights turn off in daylight',
        );
        await captureSimulator('$prefix-day.png');
      } finally {
        await eval(
          '(() { benchRest.cancel(); inputState.setMove(0,0); clock.hours=$hours; clock.gameMinutesPerSecond=$rate; playerHealth.health=$health; playerHealth.armor=$armor; _movement!.teleport(vm.Vector3($position)); return true; })()',
        );
      }
      return;
    }
    if (args[1] != '--smoke' && args[1] != '--drive') {
      print(await eval(args[1]));
      return;
    }
    final hud = await instance('ui/hud/game_hud.dart', '_GameHudState');
    // A VM connection is available before asynchronous scene loading finishes.
    final readyDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (await eval('_ready', hud) != 'true') {
      if (DateTime.now().isAfter(readyDeadline)) {
        throw StateError('Game did not finish loading within 30 seconds');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    Future<void> toggleVehicle() async {
      // VM evaluation can interrupt painting. Dispatch UI changes after
      // the current synchronous frame, like a normal input event.
      // This scenario tests the current player car. A passing traffic car can
      // otherwise be closer and turn an enter into a random carjack. Exclude
      // candidates only during the synchronous UI action, then restore them.
      await eval(
        'Future.microtask(() { final traffic=game.traffic; final units=traffic._units.toList(); traffic._units.clear(); try { _toggleVehicle(); } finally { traffic._units.addAll(units); } })',
        hud,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    void check(bool condition, String label) {
      if (!condition) throw StateError('FAIL: $label');
      print('PASS: $label');
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 1100));
    final wasDriving =
        await eval('gameModeState.mode == ControlMode.driving') == 'true';
    final position = await eval(
      r'"${playerNode.position.x},${playerNode.position.y},${playerNode.position.z}"',
    );
    final carPosition = await eval(
      r'"${vehicle.node.position.x},${vehicle.node.position.y},${vehicle.node.position.z}"',
    );
    final heading = await eval('vehicle.controller.heading');
    final yaw = await eval('cameraController.yaw');
    final pitch = await eval('cameraController.pitch');
    try {
      if (args[1] == '--drive') {
        if (wasDriving) await toggleVehicle();
        final hours = await eval('clock.hours');
        final timeRate = await eval('clock.gameMinutesPerSecond');
        final fps = await instance(
          'engine/debug/fps_overlay.dart',
          '_FpsOverlayState',
        );
        final frames = <int, int>{};
        const route = <(double, double)>[
          (127.29, -501.56),
          (140.76, -321.22),
          (153.59, -159.12),
          (157.95, -78.16),
          (160.43, 12.85),
          (168.84, 144.99),
          (173.32, 184.47),
        ];
        var segment = 0, nextFramePoll = 0;
        final watch = Stopwatch();
        final path = <Map<String, Object>>[];
        try {
          final yaw = math.atan2(
            route[1].$1 - route[0].$1,
            route[1].$2 - route[0].$2,
          );
          final x = route[0].$1 + math.cos(yaw) * 1.7 + math.sin(yaw) * 20;
          final z = route[0].$2 - math.sin(yaw) * 1.7 + math.cos(yaw) * 20;
          await eval(
            '(() { inputState.setMove(0,0); inputState.isRunning=false; clock.hours=16; clock.gameMinutesPerSecond=0; vehicle.controller.velocityXZ.setZero(); vehicle.controller.dynamics.stopYaw(); vehicle.controller.heading=$yaw; vehicle.node.position=vm.Vector3($x,0,$z); _movement!.teleport(vehicle.node.position+vm.Vector3(2.5,0,0)); cameraController.orbitBy($yaw-cameraController.yaw,.2-cameraController.pitch); return true; })()',
          );
          await Future<void>.delayed(const Duration(seconds: 3));
          await toggleVehicle();
          check(
            await eval('gameModeState.mode == ControlMode.driving') == 'true',
            'drive route entered',
          );
          watch.start();
          await eval(
            'vehicle.controller.velocityXZ.setValues(${math.sin(yaw) * 12},${math.cos(yaw) * 12})',
          );
          while (watch.elapsedMilliseconds < 55000) {
            final values = (await eval(
              r'"${vehicle.node.position.x},${vehicle.node.position.z},${vehicle.controller.heading},${vehicle.controller.speed},${gameModeState.mode == ControlMode.driving ? 1 : 0}"',
            )).split(',').map(double.parse).toList();
            if (values[4] != 1) {
              throw StateError(
                'Drive benchmark interrupted: player left the vehicle',
              );
            }
            final x = values[0], z = values[1];
            while (segment < route.length - 2 &&
                math.sqrt(
                      math.pow(x - route[segment + 1].$1, 2) +
                          math.pow(z - route[segment + 1].$2, 2),
                    ) <
                    18) {
              segment++;
            }
            final a = route[segment], b = route[segment + 1];
            final dx = b.$1 - a.$1,
                dz = b.$2 - a.$2,
                length = math.sqrt(dx * dx + dz * dz);
            final along =
                ((x - a.$1) * dx + (z - a.$2) * dz) / (length * length);
            final t = (along + 14 / length).clamp(0.0, 1.0);
            final targetX = a.$1 + dx * t + dz / length * 1.7,
                targetZ = a.$2 + dz * t - dx / length * 1.7;
            final desired = math.atan2(targetX - x, targetZ - z);
            final error =
                (desired - values[2] + math.pi) % (2 * math.pi) - math.pi;
            final steer = (error * 2.5).clamp(-1.0, 1.0);
            final throttle = ((13.0 - values[3]) * .5 + .12).clamp(-1.0, 1.0);
            await eval(
              '(() { for(final root in traffic.carNodes) { for(final n in root.meshNodes) { n.raycastable=false; } } inputState.setMove($steer,$throttle); return true; })()',
            );
            if (watch.elapsedMilliseconds >= nextFramePoll) {
              nextFramePoll += 500;
              final raw = await eval(
                r'_recent.map((t)=>"${t.timestampInMicroseconds(FramePhase.vsyncStart)},${t.buildDuration.inMicroseconds}").join(";")',
                fps,
              );
              for (final entry in raw.split(';')) {
                final f = entry.split(',').map(int.parse).toList();
                frames[f[0]] = f[1];
              }
              path.add({
                'ms': watch.elapsedMilliseconds,
                'x': x,
                'z': z,
                'speed': values[3],
              });
              print(
                'drive ${watch.elapsed.inSeconds}s z=${z.toStringAsFixed(1)} speed=${values[3].toStringAsFixed(1)}',
              );
            }
            if (segment == route.length - 2 && z > route.last.$2 - 18) break;
            await Future<void>.delayed(const Duration(milliseconds: 130));
          }
          final finalZ = double.parse(await eval('vehicle.node.position.z'));
          final times = frames.keys.toList()..sort();
          final gaps = <double>[
            for (var i = 1; i < times.length; i++)
              (times[i] - times[i - 1]) / 1000,
          ];
          final covered = gaps.reduce((a, b) => a + b);
          gaps.sort();
          final summary = {
            'completed':
                segment == route.length - 2 && finalZ > route.last.$2 - 18.1,
            'finalZ': finalZ,
            'frames': times.length,
            'fps': gaps.length * 1000 / covered,
            'p95Ms': gaps[(gaps.length * .95).floor()],
            'p99Ms': gaps[(gaps.length * .99).floor()],
            'maxMs': gaps.last,
            'over50ms': gaps.where((t) => t > 50).length,
            'path': path,
            'timings': times.map((t) => [t, frames[t]]).toList(),
          };
          final file = args.length > 2 ? args[2] : '/tmp/crime-drive.json';
          await File(file).writeAsString(jsonEncode(summary));
          print(
            jsonEncode(
              {...summary}
                ..remove('path')
                ..remove('timings'),
            ),
          );
        } finally {
          await eval(
            '(() { for(final root in traffic.carNodes) { for(final n in root.meshNodes) { n.raycastable=true; } } clock.hours=$hours; clock.gameMinutesPerSecond=$timeRate; return true; })()',
          );
        }
        return;
      }
      await eval(
        '(() { inputState.setMove(0, 0); inputState.isRunning = false; return true; })()',
      );
      if (wasDriving) await toggleVehicle();
      await eval(
        'cameraController.orbitBy(-cameraController.yaw, 0.20 - cameraController.pitch)',
      );
      await settle();
      final speeds = <double>[];
      for (final input in [0.25, 1.0]) {
        await eval(
          '(() { _movement!.teleport(worldConfig.playerSpawnPosition); inputState.setMove(0, $input); return true; })()',
        );
        await settle();
        speeds.add(double.parse(await eval('_movement!.horizontalSpeed')));
        check(
          await eval('_playerModel?.current == CharacterAnim.walk') == 'true',
          'walking animation is active',
        );
        await eval('inputState.setMove(0, 0)');
      }
      check(
        (speeds[0] / speeds[1] - 0.25).abs() < 0.05,
        'analog walk speed: ${speeds.map((s) => s.toStringAsFixed(2)).join(' / ')} m/s',
      );
      await eval(
        '(() { _movement!.teleport(worldConfig.playerSpawnPosition); inputState.setMove(0, 1); inputState.isRunning = true; return true; })()',
      );
      await settle();
      final sprint = double.parse(await eval('_movement!.horizontalSpeed'));
      check(
        await eval('_playerModel?.current == CharacterAnim.run') == 'true',
        'running animation is active',
      );
      check(
        sprint > 5 && sprint < 6,
        'sprint: ${sprint.toStringAsFixed(2)} m/s',
      );
      await eval(
        '(() { inputState.setMove(0, 0); inputState.isRunning = false; _movement!.teleport(vm.Vector3(8.5, 0, 3)); cameraController.orbitBy(math.pi / 2 - cameraController.yaw, 0.20 - cameraController.pitch); return true; })()',
      );
      await settle();
      final arm = double.parse(
        await eval(
          '(cameraNode.globalTransform.getTranslation() - cameraController.lookTarget).length',
        ),
      );
      check(
        arm < 4 && arm > 0.3,
        'camera retracts at the real house: ${arm.toStringAsFixed(2)} m',
      );
      check(
        await eval(
              '(() { final arm = cameraNode.globalTransform.getTranslation() - cameraController.lookTarget; return _castCameraObstruction(cameraController.lookTarget, arm.normalized(), arm.length - 0.05) == null; })()',
            ) ==
            'true',
        'camera remains outside the wall',
      );
      check(
        await eval('_playerMeshNode!.visible') == 'false',
        'close camera hides the player mesh',
      );
      await eval('cameraController.orbitBy(-math.pi, 0)');
      await settle();
      check(
        double.parse(
              await eval(
                '(cameraNode.globalTransform.getTranslation() - cameraController.lookTarget).length',
              ),
            ) >
            5,
        'camera recovers in open space',
      );
      check(
        await eval('_playerMeshNode!.visible') == 'true',
        'player mesh returns in open space',
      );
      await eval(
        '(() { _movement!.teleport(vehicle.node.position + vm.Vector3(2.5, 0, 0)); return true; })()',
      );
      await settle();
      await toggleVehicle();
      check(
        await eval('gameModeState.mode == ControlMode.driving') == 'true',
        'enter vehicle and switch HUD',
      );
      check(
        await eval('_playerMeshNode?.visible == false') == 'true',
        'driver model hides in vehicle',
      );
      await eval('inputState.setMove(0, 1)');
      await settle();
      final carSpeed = double.parse(await eval('vehicle.controller.speed'));
      check(
        carSpeed > 2,
        'vehicle accelerates: ${carSpeed.toStringAsFixed(2)} m/s',
      );
      await eval('inputState.setMove(0, -1)');
      await settle();
      check(
        double.parse(await eval('vehicle.controller.speed')) < carSpeed,
        'vehicle brakes',
      );
      await eval('inputState.setMove(0, 0)');
      await toggleVehicle();
      check(
        await eval('gameModeState.mode == ControlMode.onFoot') == 'true',
        'exit vehicle and restore walking HUD',
      );
      final treeTarget = await instance(
        'world/vegetation.dart',
        'VegetationBatch',
      );
      final spawn = await eval(
        r'"${worldConfig.playerSpawnPosition.x},${worldConfig.playerSpawnPosition.y},${worldConfig.playerSpawnPosition.z}"',
      );
      final treeData = await eval(
        r'''(() {
          final spawn=vm.Vector3(SPAWN_VECTOR);
          final indices=List<int>.generate(_treePositions.length,(i)=>i)
            ..sort((a,b)=>(_treePositions[a]-spawn).length2.compareTo((_treePositions[b]-spawn).length2));
          for(final index in indices) {
            final p=_treePositions[index]; var clear=true;
            for(var dz=-9.0;dz< -2;dz+=.8) {
              if(groundClearance?.call(p.x,p.z+dz,1.5)==false) {clear=false;break;}
            }
            for(var i=0;i<_treePositions.length && clear;i++) {
              if(i==index)continue;
              final other=_treePositions[i]-p;
              if(other.x.abs()<1.6 && other.z> -9 && other.z< -1)clear=false;
            }
            if(clear)return "${p.x},${p.y},${p.z},${_treeScales[index]}";
          }
          throw StateError('No tree with a clear vehicle approach');
        })()'''
            .replaceAll('SPAWN_VECTOR', spawn)
            .replaceAll('\n', ' '),
        treeTarget,
      );
      final tree = treeData.split(',').map(double.parse).toList();
      final root = '${tree[0]},${tree[1]},${tree[2]}';
      await eval(
        '(() { cameraController.orbitBy(-cameraController.yaw, 0.20 - cameraController.pitch); _movement!.teleport(vm.Vector3($root) + vm.Vector3(0, 0, -2.5)); inputState.setMove(0, 1); inputState.isRunning = true; return true; })()',
      );
      await settle();
      final clearance = double.parse(
        await eval('(playerNode.position - vm.Vector3($root)).length'),
      );
      check(
        clearance > 0.66 && clearance < 1,
        'running stops at a real trunk: ${clearance.toStringAsFixed(2)} m',
      );
      await eval(
        '(() { inputState.setMove(0, 0); inputState.isRunning = false; vehicle.controller.velocityXZ.setZero(); vehicle.controller.heading = 0; vehicle.node.position = vm.Vector3($root) + vm.Vector3(0, 0, -6); _movement!.teleport(vehicle.node.position + vm.Vector3(2.5, 0, 0)); return true; })()',
      );
      await settle();
      await toggleVehicle();
      check(
        await eval('gameModeState.mode == ControlMode.driving') == 'true',
        'enter vehicle for trunk collision',
      );
      await eval('inputState.setMove(0, 1)');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final carClearance = double.parse(
        await eval('${tree[2]} - vehicle.node.position.z'),
      );
      final expectedClearance =
          double.parse(
            await eval(
              'vehicle.controller.bodyHalfLength',
            ),
          ) +
          0.28 * tree[3] +
          0.005;
      check(
        (carClearance - expectedClearance).abs() < 0.16 &&
            double.parse(await eval('vehicle.controller.speed')) < 0.2,
        'vehicle stops before real trunk: ${carClearance.toStringAsFixed(2)} m',
      );
      await eval('inputState.setMove(0, -1)');
      await settle();
      check(
        double.parse(await eval('${tree[2]} - vehicle.node.position.z')) >
            carClearance + 0.4,
        'vehicle reverses away from trunk',
      );
      await eval('inputState.setMove(0, 0)');
      await toggleVehicle();
      // Known open green parcel, away from the roads and building footprints.
      await eval(
        '(() { _movement!.teleport(vm.Vector3(-180, terrain.heightAt(-180, 292), 292)); return true; })()',
      );
      await settle();
      check(
        double.parse(await eval('playerNode.position.y')) > 2.5,
        'player stands on raised terrain',
      );
      await eval('inputState.setMove(0, 1)');
      await settle();
      check(
        double.parse(
              await eval(
                '(playerNode.position.y - terrain.heightAt(playerNode.position.x, playerNode.position.z)).abs()',
              ),
            ) <
            0.12,
        'walking follows the visible terrain',
      );
      await eval(
        '(() { inputState.setMove(0, 0); vehicle.controller.velocityXZ.setZero(); vehicle.node.position = vm.Vector3(-180, terrain.heightAt(-180, 292), 292); _movement!.teleport(vehicle.node.position + vm.Vector3(2.5, 0, 0)); return true; })()',
      );
      await settle();
      await toggleVehicle();
      check(
        await eval('gameModeState.mode == ControlMode.driving') == 'true',
        'enter car on terrain',
      );
      await eval('inputState.setMove(0, 1)');
      await settle();
      check(
        double.parse(
              await eval(
                '(vehicle.node.position.y - terrain.heightAt(vehicle.node.position.x, vehicle.node.position.z)).abs()',
              ),
            ) <
            0.05,
        'vehicle follows the visible terrain',
      );
      check(
        await eval('vehicle.controller.wheelNodes.length == 4') == 'true',
        'four independent player wheels configured',
      );
      final contactError = double.parse(
        await eval(
          '(() { final spin=vehicle.node.getComponent<WheelSpinComponent>()!; var error=0.0; for(final wheel in vehicle.controller.wheelNodes) { final p=wheel.globalTransform.getTranslation(); error=math.max(error,(p.y-spin.wheelRadius-terrain.heightAt(p.x,p.z)).abs()); } return error; })()',
        ),
      );
      check(
        contactError < .06,
        'tyres follow terrain within ${(contactError * 100).toStringAsFixed(1)} cm',
      );
      await eval('inputState.setMove(0, 0)');
      await toggleVehicle();
      // Isolated driving pad outside OSM: test high-speed handling without
      // relying on live traffic or crashing into a house during the test.
      await eval(
        '(() { vehicle.controller.velocityXZ.setZero(); vehicle.controller.heading=0; vehicle.controller.dynamics.stopYaw(); vehicle.node.position=vm.Vector3(900,0,900); _movement!.teleport(vm.Vector3(902.5,0,900)); return true; })()',
      );
      await settle();
      await toggleVehicle();
      check(
        await eval('gameModeState.mode == ControlMode.driving') == 'true',
        'enter vehicle on handling test pad: ${await eval(r'"mode=${gameModeState.mode}, player=${playerNode.position}, vehicle=${vehicle.node.position}, interaction=$vehicleInteraction"')}',
      );
      await eval(
        '(() { vehicle.controller.velocityXZ.setValues(0,18); inputState.setMove(.8,.2); return true; })()',
      );
      await settle();
      check(
        double.parse(await eval('vehicle.controller.heading.abs()')) > .05,
        'tyre forces turn vehicle at speed',
      );
      check(
        double.parse(await eval('vehicle.controller.dynamics.bodyRoll.abs()')) >
            .002,
        'sprung body leans during cornering',
      );
      await eval(
        '(() { inputState.handbrakeHeld=true; inputState.setMove(1,0); return true; })()',
      );
      await settle();
      check(
        await eval(
              'vehicle.controller.speed.isFinite && vehicle.controller.speed < 25 && vehicle.controller.dynamics.yawRate.isFinite',
            ) ==
            'true',
        'handbrake remains numerically stable',
      );
      await eval(
        '(() { inputState.handbrakeHeld=false; inputState.setMove(0,0); return true; })()',
      );
      await toggleVehicle();
      // East wall of the real spawn house (x=7.05): a left turn must not
      // sweep a front corner into it, even before centre translation hits.
      await eval(
        '(() { vehicle.controller.velocityXZ.setZero(); vehicle.controller.heading=0; vehicle.controller.dynamics.stopYaw(); vehicle.node.position=vm.Vector3(8.15,0,3); _movement!.teleport(vm.Vector3(10.65,0,3)); return true; })()',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      await toggleVehicle();
      check(
        await eval('gameModeState.mode == ControlMode.driving') == 'true',
        'enter vehicle beside a real wall',
      );
      await eval(
        '(() { vehicle.controller.velocityXZ.setValues(0,8); inputState.setMove(-1,.1); return true; })()',
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
      await eval('inputState.setMove(0,0)');
      final leftCorner = double.parse(
        await eval(
          '(() { final c=vehicle.controller; var x=double.infinity; for(final sx in [-1.0,1.0]) { for(final sz in [-1.0,1.0]) { final p=vehicle.node.globalTransform.transform3(vm.Vector3(sx*c.bodyHalfWidth,.5,sz*c.bodyHalfLength)); x=math.min(x,p.x); } } return x; })()',
        ),
      );
      check(
        leftCorner > 7.02,
        'rotating vehicle corner stays outside real wall: ${leftCorner.toStringAsFixed(2)} m',
      );
      await toggleVehicle();
    } finally {
      await eval(
        '(() { inputState.setMove(0, 0); inputState.isRunning = false; inputState.handbrakeHeld = false; inputState.fireHeld = false; return true; })()',
      );
      if (await eval('gameModeState.mode == ControlMode.driving') == 'true') {
        await toggleVehicle();
      }
      await eval(
        '(() { vehicle.controller.velocityXZ.setZero(); vehicle.controller.heading = $heading; vehicle.node.position = vm.Vector3($carPosition); _movement!.teleport(vm.Vector3($position)); cameraController.orbitBy($yaw - cameraController.yaw, $pitch - cameraController.pitch); return true; })()',
      );
      if (wasDriving) {
        await eval(
          '(() { _movement!.teleport(vehicle.node.position + vm.Vector3(2.5, 0, 0)); return true; })()',
        );
        await settle();
        await toggleVehicle();
      }
    }
  } finally {
    await service.dispose();
  }
}

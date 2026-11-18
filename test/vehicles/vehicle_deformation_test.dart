import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/vehicle_deformation.dart';

void main() {
  test('a front impact dents the front while preserving the rear', () {
    final zones = [CrushZone(vm.Vector3(0, .6, 2), vm.Vector3(0, 0, -1), .3)];
    final front = deformPoint(vm.Vector3(0, .6, 2), zones),
        rear = deformPoint(vm.Vector3(0, .6, -2), zones);
    expect(front.position.z, closeTo(1.7, 1e-5));
    expect(front.scratch, greaterThan(.9));
    expect(rear.position.z, -2);
    expect(rear.scratch, 0);
  });
  test('repeated impacts stay bounded and do not move unrelated vertices', () {
    final d = VehicleDeformation();
    for (var i = 0; i < 100; i++) {
      d.add(vm.Vector3(0, .6, 2), vm.Vector3(0, 0, -1), 20);
    }
    expect(d.zones.length, 1);
    final hit = deformPoint(vm.Vector3(0, .6, 2), d.zones);
    expect(2 - hit.position.z, lessThanOrEqualTo(.521));
    expect(hit.position.isNaN, false);
  });
}

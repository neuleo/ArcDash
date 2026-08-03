import 'package:arcdash/models/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default layout has independent portrait and landscape layouts', () {
    final dashboard = DashboardLayout.defaults();

    expect(dashboard.forOrientation(DashboardOrientation.portrait), isNotEmpty);
    expect(
        dashboard.forOrientation(DashboardOrientation.landscape), isNotEmpty);
    expect(
      dashboard.forOrientation(DashboardOrientation.portrait),
      isNot(same(dashboard.forOrientation(DashboardOrientation.landscape))),
    );
  });

  test('layout round-trips and rejects unknown values', () {
    final original = DashboardLayout.defaults();
    final decoded = DashboardLayout.fromJson(original.toJson());

    expect(decoded, original);
    expect(
      () => DashboardLayout.fromJson({'version': 99}),
      throwsFormatException,
    );
  });

  test('layout validation rejects duplicate ids and out of bounds tiles', () {
    final tile = DashboardTile(
      id: 'speed',
      metric: DashboardMetric.speed,
      kind: DashboardTileKind.value,
      column: 0,
      row: 0,
      width: 2,
      height: 2,
    );
    final invalid = DashboardOrientationLayout(
      columns: 4,
      rows: 4,
      tiles: [tile, tile],
    );

    expect(() => invalid.validate(), throwsFormatException);
  });

  test('schema 2 keeps previously valid compact power tiles loadable', () {
    const layout = DashboardOrientationLayout(
      columns: 1,
      rows: 1,
      tiles: [
        DashboardTile(
          id: 'power',
          metric: DashboardMetric.power,
          kind: DashboardTileKind.arc,
          column: 0,
          row: 0,
          width: 1,
          height: 1,
        ),
      ],
    );

    expect(layout.validate, returnsNormally);
  });

  test('optional display kind and unit round-trip without breaking old tiles',
      () {
    const customized = DashboardTile(
      id: 'speed',
      metric: DashboardMetric.speed,
      kind: DashboardTileKind.value,
      unit: DashboardUnit.imperial,
      column: 0,
      row: 0,
      width: 3,
      height: 3,
    );
    final decoded = DashboardTile.fromJson(customized.toJson());
    final legacy = DashboardTile.fromJson({
      'id': 'voltage',
      'metric': 'voltage',
      'kind': 'value',
      'column': 0,
      'row': 0,
      'width': 1,
      'height': 1,
    });

    expect(decoded, customized);
    expect(decoded.unit, DashboardUnit.imperial);
    expect(legacy.unit, DashboardUnit.automatic);
  });
}

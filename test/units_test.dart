import 'package:err/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatSpeed converts m/s to km/h and mph', () {
    expect(formatSpeed(10, imperial: false), '36.0 km/h');
    expect(formatSpeed(10, imperial: true), '22.4 mph');
  });

  test('formatSpeed clamps the unknown-speed sentinel to zero', () {
    expect(formatSpeed(-1, imperial: false), '0.0 km/h');
  });

  test('formatDistance uses km/mi for totals', () {
    expect(formatDistance(2500, imperial: false), '2.50 km');
    expect(formatDistance(1609.344, imperial: true), '1.00 mi');
  });

  test('formatLiveDistance shows m/ft below the threshold, then km/mi', () {
    expect(formatLiveDistance(80, imperial: false), '80 m');
    expect(formatLiveDistance(2500, imperial: false), '2.50 km');
    expect(formatLiveDistance(100, imperial: true), '328 ft');
    expect(formatLiveDistance(1609.344, imperial: true), '1.00 mi');
  });

  test('formatElevation rounds to whole units', () {
    expect(formatElevation(123.4, imperial: false), '123 m');
    expect(formatElevation(304.8, imperial: true), '1000 ft');
  });

  test('formatDuration lets hours grow past a day', () {
    expect(
      formatDuration(const Duration(hours: 100, minutes: 5, seconds: 9)),
      '100:05:09',
    );
  });
}

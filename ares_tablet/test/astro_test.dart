import 'package:ares_tablet/models/ares_models.dart';
import 'package:ares_tablet/util/astro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mars clock', () {
    test('J2000 epoch maps to the expected MSD', () {
      final epoch = DateTime.utc(2000, 1, 1, 12);
      final clock = marsClockAt(epoch);
      expect(clock.msd, closeTo(44795.99904, 1e-6));
      expect(clock.mtc, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
      expect(clock.mtcSeconds, inInclusiveRange(0, 86399));
    });

    test('one sol advances MSD by one and preserves MTC', () {
      final start = DateTime.utc(2026, 11, 14, 6, 30);
      final a = marsClockAt(start);
      final b = marsClockAt(start.add(const Duration(milliseconds: 88775244)));
      expect(b.msd - a.msd, closeTo(1, 1e-9));
      expect(b.mtcSeconds, closeTo(a.mtcSeconds, 1));
    });
  });

  group('Light time and geometry', () {
    test('Earth-Mars one-way light time is physically plausible', () {
      final seconds = oneWayLightSeconds(DateTime.utc(2026, 11, 14));
      expect(seconds, greaterThan(180));
      expect(seconds, lessThan(1400));
    });

    test('one degree of latitude is about 59.2 km', () {
      final distance = haversineKm(
        const GeoPoint(137.4, -4.6),
        const GeoPoint(137.4, -5.6),
      );
      expect(distance, closeTo(59.16, 0.05));
    });

    test('bearing and compass labels agree', () {
      final bearing = initialBearingDeg(
        const GeoPoint(137.4, -4.6),
        const GeoPoint(137.5, -4.6),
      );
      expect(bearing, closeTo(90, 0.5));
      expect(compass16(bearing), 'E');
      expect(compass16(0), 'N');
      expect(compass16(225), 'SW');
    });

    test('solar elevation peaks at local noon and is negative at midnight', () {
      const point = GeoPoint(137.4, -4.65);
      const noon = MarsClock(
        msd: 44796,
        mtc: '12:00:00',
        mtcSeconds: 43200,
        localSolarHours: 12,
      );
      const midnight = MarsClock(
        msd: 44796,
        mtc: '00:00:00',
        mtcSeconds: 0,
        localSolarHours: 0,
      );
      final noonSun = solarPosition(point, noon);
      final midnightSun = solarPosition(point, midnight);
      expect(noonSun.elevationDeg, greaterThan(20));
      expect(midnightSun.elevationDeg, lessThan(0));
      expect(noonSun.azimuthDeg, inInclusiveRange(0, 360));
      expect(noonSun.isUp, isTrue);
      expect(midnightSun.isUp, isFalse);
    });
  });

  group('Formatting', () {
    test('coordinate hemispheres are correct', () {
      expect(
        formatCoordinate(const GeoPoint(137.4, -4.65)),
        '4.6500°S  137.4000°E',
      );
    });

    test('median handles odd and even lists', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median([]), 0);
    });
  });
}

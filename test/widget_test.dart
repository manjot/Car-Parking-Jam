import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_parking_jam/main.dart';
import 'package:car_parking_jam/models/game_models.dart';
import 'package:car_parking_jam/services/ad_service.dart';
import 'package:car_parking_jam/services/game_storage.dart';
import 'package:car_parking_jam/services/level_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unlimited 3D Level Generator & Complete Solvability Tests', () {
    test('Levels 1, 5, 10, 25, 100, 1000, 999999 are 100% solvable to 0 cars', () {
      const testLevels = [1, 2, 5, 10, 25, 50, 100, 1000, 999999];

      for (final lvl in testLevels) {
        final levelData = LevelGenerator.generateLevel(
          levelNumber: lvl,
          skinPack: CarSkinPack.allPacks.first,
        );

        expect(levelData.cars.length, greaterThanOrEqualTo(5));

        // Verify no two cars overlap or sit on an obstacle
        final occupied = <Point2I>{};
        for (final obs in levelData.obstacles) {
          occupied.add(Point2I(obs.gridX, obs.gridY));
        }
        for (final car in levelData.cars) {
          for (final cell in car.occupiedCells) {
            expect(
              cell.x >= 0 && cell.x < levelData.gridSize,
              isTrue,
              reason: 'Car out of X bounds on level $lvl',
            );
            expect(
              cell.y >= 0 && cell.y < levelData.gridSize,
              isTrue,
              reason: 'Car out of Y bounds on level $lvl',
            );
            expect(
              occupied.add(cell),
              isTrue,
              reason: 'Overlapping cell $cell on level $lvl',
            );
          }
        }

        // Verify the solver can completely clear the entire parking lot
        final remainingCars = levelData.cars.map((c) => c.copy()).toList();
        int safetySteps = 0;
        while (remainingCars.isNotEmpty && safetySteps < 200) {
          safetySteps++;
          final hint = LevelGenerator.findHintMove(
            level: levelData,
            activeCars: remainingCars,
          );
          expect(
            hint,
            isNotNull,
            reason: 'Level $lvl deadlocked with ${remainingCars.length} cars remaining!',
          );
          remainingCars.removeWhere((c) => c.id == hint!.car.id);
        }
        expect(remainingCars, isEmpty);
      }
    });
  });

  testWidgets('CarParkingJamApp renders 3D viewport, HUD, and Ad banner',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    AdService.instance.setTestEnvironment(true);
    await GameStorage.instance.load();
    await AdService.instance.initialize();

    await tester.pumpWidget(const CarParkingJamApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('LEVEL 1'), findsOneWidget);
    expect(find.text('Auto Hint'), findsOneWidget);
    expect(find.text('Helicopter'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Garage'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Unmount GameScreen so its 60fps 3D Ticker disposes cleanly in tests
    await tester.pumpWidget(const SizedBox());
  });
}

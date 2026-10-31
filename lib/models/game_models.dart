import 'package:flutter/material.dart';

enum CarOrientation {
  horizontal, // Moves along X axis (west <-> east)
  vertical, // Moves along Y axis (north <-> south)
}

enum CarType {
  sedan,
  sports,
  suv,
  taxi,
  police,
  pickup,
  bus,
  limo,
  fireTruck,
}

enum ExitDirection {
  north, // -Y
  south, // +Y
  west, // -X
  east, // +X
}

enum CarAnimState {
  parked,
  sliding,
  exitingLot,
  drivingOnRoad,
  helicopterLift,
  exited,
}

enum ObstacleType {
  bollard,
  fireHydrant,
  planter,
  charger,
}

class GridObstacle {
  final int gridX;
  final int gridY;
  final ObstacleType type;

  const GridObstacle({
    required this.gridX,
    required this.gridY,
    required this.type,
  });
}

class PerimeterWall {
  final ExitDirection side;
  final int index; // cell index along that border edge

  const PerimeterWall({
    required this.side,
    required this.index,
  });
}

class ParkingCar {
  final String id;
  int gridX;
  int gridY;
  final int length; // 2 or 3 cells
  final CarOrientation orientation;
  final bool facingPositive; // true => faces +X (east) or +Y (south)
  final CarType type;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isVip;

  // Dynamic 3D animation coordinates (in grid units)
  double animX;
  double animY;
  double animZ;
  double yawAngle; // radians in XY plane
  double tiltPitch; // suspension pitch when braking/bumping
  double tiltRoll;
  CarAnimState state;
  ExitDirection? exitDirection;
  double roadProgress;
  double shakeTimer;
  double shakeDirection; // +1 or -1
  bool isHighlighted;

  ParkingCar({
    required this.id,
    required this.gridX,
    required this.gridY,
    required this.length,
    required this.orientation,
    required this.facingPositive,
    required this.type,
    required this.primaryColor,
    required this.secondaryColor,
    this.isVip = false,
    double? animX,
    double? animY,
    this.animZ = 0.0,
    double? yawAngle,
    this.tiltPitch = 0.0,
    this.tiltRoll = 0.0,
    this.state = CarAnimState.parked,
    this.exitDirection,
    this.roadProgress = 0.0,
    this.shakeTimer = 0.0,
    this.shakeDirection = 1.0,
    this.isHighlighted = false,
  })  : animX = animX ?? gridX.toDouble(),
        animY = animY ?? gridY.toDouble(),
        yawAngle = yawAngle ??
            _defaultYaw(orientation, facingPositive);

  static double _defaultYaw(CarOrientation orientation, bool facingPositive) {
    if (orientation == CarOrientation.horizontal) {
      return facingPositive ? 0.0 : 3.141592653589793;
    } else {
      return facingPositive ? 1.5707963267948966 : -1.5707963267948966;
    }
  }

  void resetYaw() {
    yawAngle = _defaultYaw(orientation, facingPositive);
  }

  /// Cells occupied by this car on the grid when parked/sliding.
  List<Point2I> get occupiedCells {
    final cells = <Point2I>[];
    for (int i = 0; i < length; i++) {
      final cx = orientation == CarOrientation.horizontal ? gridX + i : gridX;
      final cy = orientation == CarOrientation.vertical ? gridY + i : gridY;
      cells.add(Point2I(cx, cy));
    }
    return cells;
  }

  bool occupiesCell(int x, int y) {
    if (state != CarAnimState.parked && state != CarAnimState.sliding) {
      return false;
    }
    if (orientation == CarOrientation.horizontal) {
      return y == gridY && x >= gridX && x < gridX + length;
    } else {
      return x == gridX && y >= gridY && y < gridY + length;
    }
  }

  ParkingCar copy() {
    return ParkingCar(
      id: id,
      gridX: gridX,
      gridY: gridY,
      length: length,
      orientation: orientation,
      facingPositive: facingPositive,
      type: type,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      isVip: isVip,
      animX: animX,
      animY: animY,
      animZ: animZ,
      yawAngle: yawAngle,
      tiltPitch: tiltPitch,
      tiltRoll: tiltRoll,
      state: state,
      exitDirection: exitDirection,
      roadProgress: roadProgress,
      shakeTimer: shakeTimer,
      shakeDirection: shakeDirection,
      isHighlighted: isHighlighted,
    );
  }
}

class Point2I {
  final int x;
  final int y;
  const Point2I(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is Point2I && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class Particle3D {
  double x;
  double y;
  double z;
  double vx;
  double vy;
  double vz;
  double size;
  double life;
  double maxLife;
  Color color;

  Particle3D({
    required this.x,
    required this.y,
    required this.z,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.size,
    required this.life,
    required this.maxLife,
    required this.color,
  });
}

class FloatingBadge3D {
  double x;
  double y;
  double z;
  String text;
  Color color;
  double life;
  double maxLife;

  FloatingBadge3D({
    required this.x,
    required this.y,
    required this.z,
    required this.text,
    required this.color,
    this.life = 1.1,
    this.maxLife = 1.1,
  });
}

class EnvironmentTheme {
  final String id;
  final String name;
  final String subtitle;
  final int unlockCost;
  final Color skyTop;
  final Color skyBottom;
  final Color groundColor;
  final Color roadColor;
  final Color lotAsphaltColor;
  final Color stallLineColor;
  final Color curbColor;
  final Color accentGlowColor;
  final Color treeFoliageColor;
  final bool isNight;

  const EnvironmentTheme({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.unlockCost,
    required this.skyTop,
    required this.skyBottom,
    required this.groundColor,
    required this.roadColor,
    required this.lotAsphaltColor,
    required this.stallLineColor,
    required this.curbColor,
    required this.accentGlowColor,
    required this.treeFoliageColor,
    this.isNight = false,
  });

  static const List<EnvironmentTheme> allThemes = [
    EnvironmentTheme(
      id: 'downtown',
      name: 'Downtown City',
      subtitle: 'Sunlit urban parking plaza with Lush trees',
      unlockCost: 0,
      skyTop: Color(0xFF0EA5E9),
      skyBottom: Color(0xFFBAE6FD),
      groundColor: Color(0xFF34D399),
      roadColor: Color(0xFF1E293B),
      lotAsphaltColor: Color(0xFF334155),
      stallLineColor: Color(0xFFFBBF24),
      curbColor: Color(0xFFE2E8F0),
      accentGlowColor: Color(0xFF38BDF8),
      treeFoliageColor: Color(0xFF10B981),
    ),
    EnvironmentTheme(
      id: 'neon_night',
      name: 'Cyber Neon Night',
      subtitle: 'Midnight synthwave lot with glowing headlights',
      unlockCost: 300,
      skyTop: Color(0xFF090D16),
      skyBottom: Color(0xFF1E1B4B),
      groundColor: Color(0xFF0F172A),
      roadColor: Color(0xFF0B0F19),
      lotAsphaltColor: Color(0xFF181826),
      stallLineColor: Color(0xFF22D3EE),
      curbColor: Color(0xFFF43F5E),
      accentGlowColor: Color(0xFFE879F9),
      treeFoliageColor: Color(0xFF6366F1),
      isNight: true,
    ),
    EnvironmentTheme(
      id: 'beach_pier',
      name: 'Miami Beach Pier',
      subtitle: 'Coastal boardwalk with golden sand & palms',
      unlockCost: 600,
      skyTop: Color(0xFF0284C7),
      skyBottom: Color(0xFFFDE68A),
      groundColor: Color(0xFFFCD34D),
      roadColor: Color(0xFF374151),
      lotAsphaltColor: Color(0xFF475569),
      stallLineColor: Color(0xFFFFFFFF),
      curbColor: Color(0xFFF97316),
      accentGlowColor: Color(0xFF06B6D4),
      treeFoliageColor: Color(0xFF22C55E),
    ),
    EnvironmentTheme(
      id: 'alpine_snow',
      name: 'Alpine Frost Peak',
      subtitle: 'Crisp mountain resort with snowdrifts & pines',
      unlockCost: 900,
      skyTop: Color(0xFF1D4ED8),
      skyBottom: Color(0xFFE0F2FE),
      groundColor: Color(0xFFF1F5F9),
      roadColor: Color(0xFF334155),
      lotAsphaltColor: Color(0xFF3E4C5E),
      stallLineColor: Color(0xFF7DD3FC),
      curbColor: Color(0xFFCBD5E1),
      accentGlowColor: Color(0xFF60A5FA),
      treeFoliageColor: Color(0xFF0D9488),
    ),
    EnvironmentTheme(
      id: 'sunset_dock',
      name: 'Golden Sunset Dock',
      subtitle: 'Warm industrial harbor with hazard curbs',
      unlockCost: 1200,
      skyTop: Color(0xFF7C2D12),
      skyBottom: Color(0xFFFB923C),
      groundColor: Color(0xFF44403C),
      roadColor: Color(0xFF1C1917),
      lotAsphaltColor: Color(0xFF292524),
      stallLineColor: Color(0xFFFACC15),
      curbColor: Color(0xFFF59E0B),
      accentGlowColor: Color(0xFFF97316),
      treeFoliageColor: Color(0xFFD97706),
    ),
  ];
}

class CarSkinPack {
  final String id;
  final String name;
  final String description;
  final int unlockCost;
  final List<Color> palette;

  const CarSkinPack({
    required this.id,
    required this.name,
    required this.description,
    required this.unlockCost,
    required this.palette,
  });

  static const List<CarSkinPack> allPacks = [
    CarSkinPack(
      id: 'classic',
      name: 'Street Turbo',
      description: 'Vibrant sports & city cruisers',
      unlockCost: 0,
      palette: [
        Color(0xFFEF4444), // Racing Red
        Color(0xFF3B82F6), // Electric Blue
        Color(0xFF10B981), // Emerald Green
        Color(0xFFF59E0B), // Taxi Amber
        Color(0xFF8B5CF6), // Royal Purple
        Color(0xFFEC4899), // Hot Magenta
        Color(0xFF06B6D4), // Cyan Drift
        Color(0xFFF97316), // Tangerine GT
      ],
    ),
    CarSkinPack(
      id: 'hyper_neon',
      name: 'Hyper Neon GT',
      description: 'High-contrast cyber supercar finishes',
      unlockCost: 400,
      palette: [
        Color(0xFF00F5D4),
        Color(0xFFFF007F),
        Color(0xFFFEE440),
        Color(0xFF9B5DE5),
        Color(0xFF00BBF9),
        Color(0xFFFF5400),
      ],
    ),
    CarSkinPack(
      id: 'gold_syndicate',
      name: 'Royal Gold & Chrome',
      description: 'Luxury metallic gold, ruby & obsidian fleet',
      unlockCost: 800,
      palette: [
        Color(0xFFFFD700),
        Color(0xFFE11D48),
        Color(0xFF38BDF8),
        Color(0xFFA855F7),
        Color(0xFF34D399),
        Color(0xFFFBBF24),
      ],
    ),
    CarSkinPack(
      id: 'pastel_retro',
      name: 'Retro Malibu 80s',
      description: 'Vintage sun-washed coupe colors',
      unlockCost: 1100,
      palette: [
        Color(0xFFFF6B6B),
        Color(0xFF4ECDC4),
        Color(0xFFFFE66D),
        Color(0xFFFF9F1C),
        Color(0xFFA29BFE),
        Color(0xFF55EFC4),
      ],
    ),
  ];
}

class LevelData {
  final int levelNumber;
  final int gridSize;
  final bool isBossLevel;
  final List<ParkingCar> cars;
  final List<GridObstacle> obstacles;
  final List<PerimeterWall> walls;
  final int parMoves;

  const LevelData({
    required this.levelNumber,
    required this.gridSize,
    required this.isBossLevel,
    required this.cars,
    required this.obstacles,
    required this.walls,
    required this.parMoves,
  });

  bool hasWall(ExitDirection side, int index) {
    for (final w in walls) {
      if (w.side == side && w.index == index) return true;
    }
    return false;
  }

  bool hasObstacle(int x, int y) {
    for (final o in obstacles) {
      if (o.gridX == x && o.gridY == y) return true;
    }
    return false;
  }
}


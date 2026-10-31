import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class GameStorage {
  GameStorage._();
  static final GameStorage instance = GameStorage._();

  static const _kCurrentLevel = 'cpj_current_level';
  static const _kHighestLevel = 'cpj_highest_level';
  static const _kCoins = 'cpj_coins';
  static const _kTotalCarsCleared = 'cpj_total_cars';
  static const _kHints = 'cpj_hints';
  static const _kHelicopters = 'cpj_helicopters';
  static const _kShuffles = 'cpj_shuffles';
  static const _kSelectedTheme = 'cpj_selected_theme';
  static const _kUnlockedThemes = 'cpj_unlocked_themes';
  static const _kSelectedSkin = 'cpj_selected_skin';
  static const _kUnlockedSkins = 'cpj_unlocked_skins';
  static const _kLevelStars = 'cpj_level_stars';

  int currentLevel = 1;
  int highestUnlockedLevel = 1;
  int coins = 200;
  int totalCarsCleared = 0;
  int hintsCount = 3;
  int helicoptersCount = 2;
  int shufflesCount = 2;

  String selectedThemeId = 'downtown';
  Set<String> unlockedThemeIds = {'downtown'};

  String selectedSkinPackId = 'classic';
  Set<String> unlockedSkinPackIds = {'classic'};

  Map<int, int> levelStars = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    currentLevel = prefs.getInt(_kCurrentLevel) ?? 1;
    highestUnlockedLevel = prefs.getInt(_kHighestLevel) ?? 1;
    coins = prefs.getInt(_kCoins) ?? 200;
    totalCarsCleared = prefs.getInt(_kTotalCarsCleared) ?? 0;
    hintsCount = prefs.getInt(_kHints) ?? 3;
    helicoptersCount = prefs.getInt(_kHelicopters) ?? 2;
    shufflesCount = prefs.getInt(_kShuffles) ?? 2;

    selectedThemeId = prefs.getString(_kSelectedTheme) ?? 'downtown';
    final themesList = prefs.getStringList(_kUnlockedThemes);
    if (themesList != null && themesList.isNotEmpty) {
      unlockedThemeIds = themesList.toSet();
    }

    selectedSkinPackId = prefs.getString(_kSelectedSkin) ?? 'classic';
    final skinsList = prefs.getStringList(_kUnlockedSkins);
    if (skinsList != null && skinsList.isNotEmpty) {
      unlockedSkinPackIds = skinsList.toSet();
    }

    final starsJson = prefs.getString(_kLevelStars);
    if (starsJson != null) {
      try {
        final decoded = jsonDecode(starsJson) as Map<String, dynamic>;
        levelStars = decoded.map(
          (key, value) => MapEntry(int.parse(key), (value as num).toInt()),
        );
      } catch (_) {}
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCurrentLevel, currentLevel);
    await prefs.setInt(_kHighestLevel, highestUnlockedLevel);
    await prefs.setInt(_kCoins, coins);
    await prefs.setInt(_kTotalCarsCleared, totalCarsCleared);
    await prefs.setInt(_kHints, hintsCount);
    await prefs.setInt(_kHelicopters, helicoptersCount);
    await prefs.setInt(_kShuffles, shufflesCount);
    await prefs.setString(_kSelectedTheme, selectedThemeId);
    await prefs.setStringList(_kUnlockedThemes, unlockedThemeIds.toList());
    await prefs.setString(_kSelectedSkin, selectedSkinPackId);
    await prefs.setStringList(_kUnlockedSkins, unlockedSkinPackIds.toList());

    final encodedStars = jsonEncode(
      levelStars.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(_kLevelStars, encodedStars);
  }
}


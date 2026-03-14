import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wow_warband_companion/models/achievement.dart';
import 'package:wow_warband_companion/services/character_cache_service.dart';

void main() {
  group('Achievement caching', () {
    late CharacterCacheService cacheService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      cacheService = CharacterCacheService(prefs);
    });

    test('caches and retrieves achievement category', () {
      final cat = AchievementCategory(
        id: 92,
        name: 'General',
        subcategories: [AchievementCategoryRef(id: 100, name: 'Sub')],
        achievementRefs: [AchievementRef(id: 6, name: 'Level 10')],
      );

      cacheService.cacheAchievementCategory(cat);
      final cached = cacheService.getCachedAchievementCategory(92);

      expect(cached, isNotNull);
      expect(cached!.name, 'General');
      expect(cached.subcategories.length, 1);
      expect(cached.achievementRefs.length, 1);
    });

    test('caches and retrieves achievement definitions', () {
      final achievements = [
        Achievement(id: 6, name: 'Level 10', description: 'Reach level 10.', points: 10),
        Achievement(id: 7, name: 'Level 20', description: 'Reach level 20.', points: 10),
      ];

      cacheService.cacheAchievements(92, achievements);
      final cached = cacheService.getCachedAchievements(92);

      expect(cached, isNotNull);
      expect(cached!.length, 2);
      expect(cached.first.name, 'Level 10');
    });

    test('returns null for missing cache entries', () {
      expect(cacheService.getCachedAchievementCategory(999), isNull);
      expect(cacheService.getCachedAchievements(999), isNull);
    });

    test('clearAll removes achievement cache entries', () {
      final cat = AchievementCategory(id: 92, name: 'General');
      cacheService.cacheAchievementCategory(cat);
      cacheService.clearAll();
      expect(cacheService.getCachedAchievementCategory(92), isNull);
    });
  });
}

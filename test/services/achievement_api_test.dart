import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/achievement.dart';

// We test the model parsing since the actual API calls require network.
void main() {
  group('Achievement API response parsing', () {
    test('parses achievement category index response', () {
      final json = {
        'categories': [
          {'key': {'href': 'https://...'}, 'name': 'General', 'id': 92},
          {'key': {'href': 'https://...'}, 'name': 'Quests', 'id': 96},
          {'key': {'href': 'https://...'}, 'name': 'Exploration', 'id': 97},
        ],
      };
      final categories = (json['categories'] as List)
          .map((e) => AchievementCategoryRef.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(categories.length, 3);
      expect(categories[0].name, 'General');
      expect(categories[1].id, 96);
    });

    test('parses achievement media response', () {
      final json = {
        'assets': [
          {'key': 'icon', 'value': 'https://render.worldofwarcraft.com/icons/56/achievement_level_10.jpg'},
        ],
      };
      final assets = json['assets'] as List;
      String? iconUrl;
      for (final asset in assets) {
        if (asset['key'] == 'icon') {
          iconUrl = asset['value'] as String;
        }
      }
      expect(iconUrl, contains('achievement_level_10'));
    });

    test('parses character achievements with deeply nested criteria', () {
      final json = {
        'total_quantity': 100,
        'total_points': 1500,
        'achievements': [
          {
            'id': 100,
            'achievement': {'id': 100, 'name': 'Explore Kalimdor'},
            'completed_timestamp': 1600000000000,
            'criteria': {
              'id': 500,
              'is_completed': true,
              'child_criteria': [
                {
                  'id': 501,
                  'is_completed': true,
                  'child_criteria': [
                    {'id': 502, 'is_completed': false},
                  ],
                },
              ],
            },
          },
        ],
      };
      final progress = AccountAchievementProgress.fromJson(json);
      expect(progress.achievements[100]!.criteriaProgress[500], true);
      expect(progress.achievements[100]!.criteriaProgress[501], true);
      expect(progress.achievements[100]!.criteriaProgress[502], false);
    });
  });
}

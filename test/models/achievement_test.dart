import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/achievement.dart';

void main() {
  group('AchievementCategory', () {
    test('fromJson parses category with subcategories and achievements', () {
      final json = {
        'id': 92,
        'name': 'General',
        'subcategories': [
          {'key': {'href': 'https://...'}, 'name': 'Expansion Features', 'id': 15465},
        ],
        'achievements': [
          {'key': {'href': 'https://...'}, 'name': 'Level 10', 'id': 6},
        ],
      };
      final cat = AchievementCategory.fromJson(json);
      expect(cat.id, 92);
      expect(cat.name, 'General');
      expect(cat.subcategories.length, 1);
      expect(cat.subcategories.first.id, 15465);
      expect(cat.achievementRefs.length, 1);
      expect(cat.achievementRefs.first.id, 6);
    });

    test('toJson round-trips correctly', () {
      final cat = AchievementCategory(
        id: 92,
        name: 'General',
        subcategories: [AchievementCategoryRef(id: 15465, name: 'Expansion Features')],
        achievementRefs: [AchievementRef(id: 6, name: 'Level 10')],
      );
      final json = cat.toJson();
      final restored = AchievementCategory.fromJson(json);
      expect(restored.id, cat.id);
      expect(restored.name, cat.name);
      expect(restored.subcategories.length, 1);
      expect(restored.achievementRefs.length, 1);
    });

    test('fromJson with empty lists', () {
      final cat = AchievementCategory.fromJson({'id': 1, 'name': 'Empty'});
      expect(cat.subcategories, isEmpty);
      expect(cat.achievementRefs, isEmpty);
    });
  });

  group('Achievement', () {
    test('fromJson parses achievement with nested criteria', () {
      final json = {
        'id': 6,
        'name': 'Level 10',
        'description': 'Reach level 10.',
        'points': 10,
        'is_account_wide': true,
        'criteria': {
          'id': 1234,
          'description': 'Reach level 10',
          'amount': 10,
          'child_criteria': [
            {'id': 1235, 'description': 'Sub-criteria', 'amount': 5},
          ],
        },
        'media': {'key': {'href': 'https://us.api.blizzard.com/data/wow/media/achievement/6'}},
      };
      final ach = Achievement.fromJson(json);
      expect(ach.id, 6);
      expect(ach.name, 'Level 10');
      expect(ach.description, 'Reach level 10.');
      expect(ach.points, 10);
      expect(ach.isAccountWide, true);
      expect(ach.criteria, isNotNull);
      expect(ach.criteria!.id, 1234);
      expect(ach.criteria!.childCriteria.length, 1);
      expect(ach.criteria!.childCriteria.first.amount, 5);
      expect(ach.mediaHref, contains('media/achievement/6'));
    });

    test('fromJson handles achievement without criteria', () {
      final json = {
        'id': 7,
        'name': 'Simple',
        'description': 'A simple achievement.',
        'points': 5,
        'is_account_wide': false,
      };
      final ach = Achievement.fromJson(json);
      expect(ach.criteria, isNull);
      expect(ach.isAccountWide, false);
      expect(ach.mediaHref, isNull);
    });

    test('toJson round-trips correctly', () {
      final ach = Achievement(
        id: 6,
        name: 'Level 10',
        description: 'Reach level 10.',
        points: 10,
        isAccountWide: true,
        criteria: AchievementCriteria(id: 1234, description: 'Reach level 10', amount: 10, childCriteria: []),
        iconUrl: 'https://icon.png',
      );
      final json = ach.toJson();
      final restored = Achievement.fromJson(json);
      expect(restored.id, ach.id);
      expect(restored.points, ach.points);
      expect(restored.criteria!.id, 1234);
      expect(restored.iconUrl, 'https://icon.png');
    });

    test('copyWith replaces iconUrl', () {
      const ach = Achievement(id: 1, name: 'Test', description: '', points: 0);
      final updated = ach.copyWith(iconUrl: 'new_icon.png');
      expect(updated.iconUrl, 'new_icon.png');
      expect(updated.id, 1);
    });
  });

  group('AccountAchievementProgress', () {
    test('fromJson parses character achievements response', () {
      final json = {
        'total_quantity': 500,
        'total_points': 5000,
        'achievements': [
          {
            'id': 6,
            'achievement': {'key': {'href': '...'}, 'name': 'Level 10', 'id': 6},
            'completed_timestamp': 1545123240000,
            'criteria': {
              'id': 1234,
              'is_completed': true,
              'child_criteria': [
                {'id': 1235, 'is_completed': true},
                {'id': 1236, 'is_completed': false},
              ],
            },
          },
          {
            'id': 7,
            'achievement': {'key': {'href': '...'}, 'name': 'Level 20', 'id': 7},
            'criteria': {'id': 2000, 'is_completed': false},
          },
        ],
      };
      final progress = AccountAchievementProgress.fromJson(json);
      expect(progress.totalQuantity, 500);
      expect(progress.totalPoints, 5000);
      expect(progress.achievements.length, 2);

      final first = progress.achievements[6]!;
      expect(first.isCompleted, true);
      expect(first.completedTimestamp, 1545123240000);
      expect(first.criteriaProgress[1235], true);
      expect(first.criteriaProgress[1236], false);

      final second = progress.achievements[7]!;
      expect(second.isCompleted, false);
      expect(second.completedTimestamp, isNull);
    });

    test('completed_timestamp of 0 is not treated as completed', () {
      final json = {
        'total_quantity': 0,
        'total_points': 0,
        'achievements': [
          {'id': 99, 'achievement': {'id': 99}, 'completed_timestamp': 0},
        ],
      };
      final progress = AccountAchievementProgress.fromJson(json);
      expect(progress.achievements[99]!.isCompleted, false);
    });

    test('deeply nested criteria are flattened', () {
      final json = {
        'total_quantity': 0,
        'total_points': 0,
        'achievements': [
          {
            'id': 100,
            'achievement': {'id': 100},
            'criteria': {
              'id': 500,
              'is_completed': false,
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
      final entry = progress.achievements[100]!;
      expect(entry.criteriaProgress[500], false);
      expect(entry.criteriaProgress[501], true);
      expect(entry.criteriaProgress[502], false);
    });
  });
}

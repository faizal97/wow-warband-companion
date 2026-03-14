import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/achievement.dart';
import 'package:wow_warband_companion/services/achievement_provider.dart';

void main() {
  group('AchievementProvider', () {
    test('mergeWithProgress marks completed achievements', () {
      final achievements = [
        Achievement(id: 6, name: 'Level 10', description: 'Reach 10', points: 10),
        Achievement(id: 7, name: 'Level 20', description: 'Reach 20', points: 10),
      ];
      final progress = AccountAchievementProgress(
        totalQuantity: 1,
        totalPoints: 10,
        achievements: {
          6: AchievementProgressEntry(
            achievementId: 6,
            isCompleted: true,
            completedTimestamp: 1600000000000,
            criteriaProgress: {},
          ),
        },
      );

      final merged = AchievementProvider.mergeWithProgress(achievements, progress);

      expect(merged.completed.length, 1);
      expect(merged.completed.first.achievement.id, 6);
      expect(merged.completed.first.isCompleted, true);
      expect(merged.incomplete.length, 1);
      expect(merged.incomplete.first.achievement.id, 7);
      expect(merged.incomplete.first.isCompleted, false);
    });

    test('mergeWithProgress calculates criteria completion counts', () {
      final achievements = [
        Achievement(
          id: 100,
          name: 'Explore',
          description: 'Explore all',
          points: 25,
          criteria: AchievementCriteria(
            id: 500,
            description: 'Root',
            childCriteria: [
              AchievementCriteria(id: 501, description: 'Zone A'),
              AchievementCriteria(id: 502, description: 'Zone B'),
              AchievementCriteria(id: 503, description: 'Zone C'),
            ],
          ),
        ),
      ];
      final progress = AccountAchievementProgress(
        totalQuantity: 0,
        totalPoints: 0,
        achievements: {
          100: AchievementProgressEntry(
            achievementId: 100,
            isCompleted: false,
            criteriaProgress: {500: false, 501: true, 502: true, 503: false},
          ),
        },
      );

      final merged = AchievementProvider.mergeWithProgress(achievements, progress);
      expect(merged.incomplete.length, 1);
      expect(merged.incomplete.first.completedCriteria, 2);
      expect(merged.incomplete.first.totalCriteria, 3);
    });

    test('mergeWithProgress with null progress treats all as incomplete', () {
      final achievements = [
        Achievement(id: 1, name: 'Test', description: '', points: 5),
      ];

      final merged = AchievementProvider.mergeWithProgress(achievements, null);
      expect(merged.completed, isEmpty);
      expect(merged.incomplete.length, 1);
    });

    test('completed preserves category order from API', () {
      final achievements = [
        Achievement(id: 1, name: 'First', description: '', points: 5),
        Achievement(id: 2, name: 'Second', description: '', points: 5),
      ];
      final progress = AccountAchievementProgress(
        totalQuantity: 2,
        totalPoints: 10,
        achievements: {
          1: AchievementProgressEntry(achievementId: 1, isCompleted: true, completedTimestamp: 2000),
          2: AchievementProgressEntry(achievementId: 2, isCompleted: true, completedTimestamp: 1000),
        },
      );

      final merged = AchievementProvider.mergeWithProgress(achievements, progress);
      // Order matches input list, not timestamp
      expect(merged.completed.first.achievement.id, 1);
      expect(merged.completed.last.achievement.id, 2);
    });

    test('formattedDate returns correct format', () {
      const display = AchievementDisplay(
        achievement: Achievement(id: 1, name: 'Test', description: '', points: 0),
        isCompleted: true,
        completedTimestamp: 1545123240000, // Dec 18, 2018
      );
      expect(display.formattedDate, isNotNull);
      expect(display.formattedDate, contains('2018'));
    });

    test('formattedDate returns null when no timestamp', () {
      const display = AchievementDisplay(
        achievement: Achievement(id: 1, name: 'Test', description: '', points: 0),
        isCompleted: false,
      );
      expect(display.formattedDate, isNull);
    });

    test('nearCompletion filters achievements at 50%+ criteria done', () {
      final achievements = [
        Achievement(
          id: 1, name: 'Almost', description: '', points: 10,
          criteria: AchievementCriteria(id: 10, childCriteria: [
            AchievementCriteria(id: 11, description: 'A'),
            AchievementCriteria(id: 12, description: 'B'),
            AchievementCriteria(id: 13, description: 'C'),
            AchievementCriteria(id: 14, description: 'D'),
          ]),
        ),
        Achievement(
          id: 2, name: 'Far', description: '', points: 10,
          criteria: AchievementCriteria(id: 20, childCriteria: [
            AchievementCriteria(id: 21, description: 'A'),
            AchievementCriteria(id: 22, description: 'B'),
            AchievementCriteria(id: 23, description: 'C'),
            AchievementCriteria(id: 24, description: 'D'),
          ]),
        ),
      ];
      final progress = AccountAchievementProgress(
        totalQuantity: 0, totalPoints: 0,
        achievements: {
          1: AchievementProgressEntry(
            achievementId: 1, isCompleted: false,
            criteriaProgress: {10: false, 11: true, 12: true, 13: true, 14: false},
          ),
          2: AchievementProgressEntry(
            achievementId: 2, isCompleted: false,
            criteriaProgress: {20: false, 21: true, 22: false, 23: false, 24: false},
          ),
        },
      );

      final merged = AchievementProvider.mergeWithProgress(achievements, progress);
      expect(merged.incomplete.length, 2);

      final nearCompletion = merged.incomplete
          .where((d) => d.totalCriteria > 0 && d.completedCriteria / d.totalCriteria >= 0.5)
          .toList();
      expect(nearCompletion.length, 1);
      expect(nearCompletion.first.achievement.name, 'Almost');
    });
  });
}

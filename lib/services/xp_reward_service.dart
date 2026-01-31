// xp_reward_service.dart
import 'xp_service.dart';

class XpRewardService {
  static Future<void> rewardXPFromBadge(int xp, String badgeId) async {
    await XPService.addXP(
      xp,
      reason: 'Badge: $badgeId',
    );
  }
}

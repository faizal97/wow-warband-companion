import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wow_warband_companion/main.dart';
import 'package:wow_warband_companion/services/battlenet_auth_service.dart';

void main() {
  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      WowCompanionApp(authService: BattleNetAuthService(prefs)),
    );
    expect(find.text('WOW WARBAND'), findsOneWidget);
    expect(find.text('SIGN IN WITH BATTLE.NET'), findsOneWidget);
  });
}

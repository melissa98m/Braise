import 'package:bresonne_app/notifications/notification_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('an unset preference falls back to the given default', () async {
    expect(
      await NotificationPrefs.isEnabled(NotificationPrefs.match, defaultValue: true),
      isTrue,
    );
    expect(
      await NotificationPrefs.isEnabled(NotificationPrefs.messages, defaultValue: false),
      isFalse,
    );
  });

  test('a stored value overrides the default', () async {
    SharedPreferences.setMockInitialValues({NotificationPrefs.question: false});

    expect(
      await NotificationPrefs.isEnabled(NotificationPrefs.question, defaultValue: true),
      isFalse,
    );
  });
}

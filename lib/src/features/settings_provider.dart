import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

// ==========================================
// SETTINGS PROVIDERS
// ==========================================

/// Available auto-refresh intervals (in seconds)
enum RefreshInterval {
  disabled(0, 'Disabled'),
  fast10s(10, '10 seconds'),
  default30s(30, '30 seconds'),
  medium60s(60, '1 minute'),
  slow120s(120, '2 minutes'),
  verySlow300s(300, '5 minutes'),
  custom(-1, 'Custom');

  const RefreshInterval(this.seconds, this.label);
  final int seconds;
  final String label;

  static RefreshInterval fromSeconds(int seconds) {
    for (final interval in RefreshInterval.values) {
      if (interval.seconds == seconds) return interval;
    }
    return RefreshInterval.custom;
  }
}

/// Provider for auto-refresh interval configuration
final autoRefreshIntervalProvider = NotifierProvider<AutoRefreshIntervalNotifier, RefreshInterval>(
  AutoRefreshIntervalNotifier.new,
);

class AutoRefreshIntervalNotifier extends Notifier<RefreshInterval> {
  @override
  RefreshInterval build() {
    _loadInterval();
    return RefreshInterval.default30s;
  }

  Future<void> _loadInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt('auto_refresh_interval') ?? 30;
    state = RefreshInterval.fromSeconds(seconds);
  }

  Future<void> setInterval(RefreshInterval interval) async {
    state = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_refresh_interval', interval.seconds);
  }

  Future<void> setCustomInterval(int seconds) async {
    if (seconds < 5 || seconds > 600) {
      throw ArgumentError('Custom interval must be between 5 and 600 seconds');
    }
    state = RefreshInterval.custom;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_refresh_interval', seconds);
  }

  int get intervalSeconds {
    if (state == RefreshInterval.custom) {
      // Load custom value from prefs synchronously (fallback to 30s)
      return 30; // TODO: Make this async-safe
    }
    return state.seconds;
  }
}

/// Provider for auto-refresh enabled state
final autoRefreshEnabledProvider = NotifierProvider<AutoRefreshEnabledNotifier, bool>(
  AutoRefreshEnabledNotifier.new,
);

class AutoRefreshEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _loadEnabled();
    return true; // Default: enabled
  }

  Future<void> _loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('auto_refresh_enabled') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_refresh_enabled', state);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_refresh_enabled', enabled);
  }
}

/// Provider for notifications enabled state
final notificationsEnabledProvider = NotifierProvider<NotificationsEnabledNotifier, bool>(
  NotificationsEnabledNotifier.new,
);

class NotificationsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _loadEnabled();
    return true; // Default: enabled
  }

  Future<void> _loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('notifications_enabled') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    await NotificationService().setEnabled(state);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await NotificationService().setEnabled(enabled);
  }
}

/// Provider for last manual refresh timestamp
final lastManualRefreshProvider = StateProvider<DateTime?>((ref) => null);

/// Provider for next auto refresh countdown (in seconds)
final nextRefreshCountdownProvider = StateProvider<int?>((ref) => null);

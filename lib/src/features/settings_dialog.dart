import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_provider.dart';

/// Settings dialog for configuring app preferences
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final _customIntervalController = TextEditingController();
  bool _showCustomInterval = false;

  @override
  void dispose() {
    _customIntervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final autoRefreshEnabled = ref.watch(autoRefreshEnabledProvider);
    final autoRefreshInterval = ref.watch(autoRefreshIntervalProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings, size: 28),
          SizedBox(width: 12),
          Text('Settings'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== AUTO-REFRESH SECTION =====
              const Text(
                'Auto-Refresh',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Enable Auto-Refresh'),
                subtitle: const Text('Automatically refresh instance list'),
                value: autoRefreshEnabled,
                onChanged: (value) {
                  ref.read(autoRefreshEnabledProvider.notifier).setEnabled(value);
                },
              ),
              const SizedBox(height: 8),
              if (autoRefreshEnabled) ...[
                const Text(
                  'Refresh Interval',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ...RefreshInterval.values
                    .where((interval) => interval != RefreshInterval.custom)
                    .map((interval) {
                  return RadioListTile<RefreshInterval>(
                    title: Text(interval.label),
                    subtitle: interval.seconds > 0
                        ? Text('Update every ${interval.seconds} seconds')
                        : null,
                    value: interval,
                    groupValue: autoRefreshInterval,
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(autoRefreshIntervalProvider.notifier)
                            .setInterval(value);
                        setState(() => _showCustomInterval = false);
                      }
                    },
                  );
                }),
                // Custom interval option
                RadioListTile<bool>(
                  title: const Text('Custom Interval'),
                  subtitle: _showCustomInterval
                      ? null
                      : const Text('Specify a custom interval (5-600s)'),
                  value: true,
                  groupValue: _showCustomInterval ||
                      autoRefreshInterval == RefreshInterval.custom,
                  onChanged: (value) {
                    if (value == true) {
                      setState(() => _showCustomInterval = true);
                    }
                  },
                ),
                if (_showCustomInterval ||
                    autoRefreshInterval == RefreshInterval.custom) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 32, right: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customIntervalController,
                            decoration: const InputDecoration(
                              labelText: 'Seconds',
                              hintText: '30',
                              border: OutlineInputBorder(),
                              helperText: 'Min: 5, Max: 600',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final seconds =
                                int.tryParse(_customIntervalController.text);
                            if (seconds == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid number'),
                                ),
                              );
                              return;
                            }
                            if (seconds < 5 || seconds > 600) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Interval must be between 5 and 600 seconds'),
                                ),
                              );
                              return;
                            }
                            ref
                                .read(autoRefreshIntervalProvider.notifier)
                                .setCustomInterval(seconds);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Refresh interval set to $seconds seconds'),
                              ),
                            );
                          },
                          child: const Text('Set'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const Divider(height: 32),

              // ===== NOTIFICATIONS SECTION =====
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Enable Desktop Notifications'),
                subtitle: const Text('Get notified about VM state changes and events'),
                value: notificationsEnabled,
                onChanged: (value) {
                  ref.read(notificationsEnabledProvider.notifier).setEnabled(value);
                },
              ),
              const SizedBox(height: 8),
              if (notificationsEnabled) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You will be notified about:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 4),
                      Text('• VM state changes (RUNNING ↔ STOPPED)', style: TextStyle(fontSize: 12)),
                      Text('• IAP tunnel failures', style: TextStyle(fontSize: 12)),
                      Text('• Lifecycle operation results (start/stop/reset)', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
              const Divider(height: 32),

              // ===== ABOUT SECTION =====
              const Text(
                'About',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Linux Cloud Connector'),
                subtitle: Text('Version 1.9.0\n© 2026 Jordi Lopez Reyes'),
                isThreeLine: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Helper function to show settings dialog
Future<void> showSettingsDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => const SettingsDialog(),
  );
}

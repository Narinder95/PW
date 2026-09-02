import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  final bool notificationsEnabled;
  final Function(bool) onNotificationsChanged;
  final String notificationTime;
  final Function(String) onNotificationTimeChanged;
  final String darkModePreference;
  final Function(String) onDarkModeChanged;
  final bool streakReminderEnabled;
  final Function(bool) onStreakReminderChanged;

  const SettingsSection({
    Key? key,
    required this.notificationsEnabled,
    required this.onNotificationsChanged,
    required this.notificationTime,
    required this.onNotificationTimeChanged,
    required this.darkModePreference,
    required this.onDarkModeChanged,
    required this.streakReminderEnabled,
    required this.onStreakReminderChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preferences',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey[300] ?? Colors.grey,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Notifications Toggle
                _buildSettingTile(
                  context,
                  icon: Icons.notifications_outlined,
                  label: 'Push Notifications',
                  value: notificationsEnabled,
                  onChanged: onNotificationsChanged,
                  isToggle: true,
                ),
                Divider(
                  height: 0,
                  color: Colors.grey[200],
                ),

                // Notification Time
                _buildSettingTile(
                  context,
                  icon: Icons.access_time_outlined,
                  label: 'Notification Time',
                  value: notificationTime,
                  onTap: () => _showTimePicker(context),
                ),
                Divider(
                  height: 0,
                  color: Colors.grey[200],
                ),

                // Dark Mode
                _buildSettingTile(
                  context,
                  icon: Icons.dark_mode_outlined,
                  label: 'Theme',
                  value: darkModePreference,
                  onTap: () => _showThemeSelector(context),
                ),
                Divider(
                  height: 0,
                  color: Colors.grey[200],
                ),

                // Streak Reminder
                _buildSettingTile(
                  context,
                  icon: Icons.local_fire_department_outlined,
                  label: 'Streak Reminder',
                  value: streakReminderEnabled,
                  onChanged: onStreakReminderChanged,
                  isToggle: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required dynamic value,
    Function(bool)? onChanged,
    VoidCallback? onTap,
    bool isToggle = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (isToggle)
              Switch(
                value: value as bool,
                onChanged: onChanged,
                activeThumbColor: Theme.of(context).colorScheme.primary,
              )
            else
              Row(
                children: [
                  Text(
                    value is String ? value : value.toString(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showTimePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Notification Time'),
        content: SizedBox(
          height: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Simple time picker (can be enhanced later)
              Expanded(
                child: ListView.builder(
                  itemCount: 24,
                  itemBuilder: (context, index) {
                    final time = '${index.toString().padLeft(2, '0')}:00';
                    return ListTile(
                      title: Text(time),
                      onTap: () {
                        onNotificationTimeChanged(time);
                        Navigator.pop(context);
                      },
                      selected: notificationTime == time,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme'),
        // RadioGroup owns the selection now; the per-Radio groupValue and
        // onChanged arguments are deprecated.
        content: RadioGroup<String>(
          groupValue: darkModePreference,
          onChanged: (value) {
            if (value == null) return;
            onDarkModeChanged(value);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Light'),
                leading: const Radio<String>(value: 'light'),
                onTap: () {
                  onDarkModeChanged('light');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Dark'),
                leading: const Radio<String>(value: 'dark'),
                onTap: () {
                  onDarkModeChanged('dark');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Auto (System)'),
                leading: const Radio<String>(value: 'auto'),
                onTap: () {
                  onDarkModeChanged('auto');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

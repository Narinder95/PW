class ActivityLog {
  final String date;
  final Map<String, int> activities;
  final DateTime loggedAt;

  ActivityLog({
    required this.date,
    required this.activities,
    required this.loggedAt,
  });

  toJson() {
    return {
      'date': date,
      'activities': activities,
      'loggedAt': loggedAt.toIso8601String(),
    };
  }

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      date: json['date'],
      activities: Map<String, int>.from(json['activities']),
      loggedAt: DateTime.parse(json['loggedAt']),
    );
  }
}

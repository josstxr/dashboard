import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeeklyWorkoutEntry {
  final String workoutId;
  final String name;
  final int dayOfWeek;
  final bool completed;
  final int restRating;
  final DateTime? updatedAt;

  const WeeklyWorkoutEntry({
    required this.workoutId,
    required this.name,
    required this.dayOfWeek,
    this.completed = false,
    this.restRating = 0,
    this.updatedAt,
  });

  WeeklyWorkoutEntry copyWith({
    String? workoutId,
    String? name,
    int? dayOfWeek,
    bool? completed,
    int? restRating,
    DateTime? updatedAt,
  }) {
    return WeeklyWorkoutEntry(
      workoutId: workoutId ?? this.workoutId,
      name: name ?? this.name,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      completed: completed ?? this.completed,
      restRating: restRating ?? this.restRating,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory WeeklyWorkoutEntry.fromJson(Map<String, dynamic> json) {
    return WeeklyWorkoutEntry(
      workoutId: json['workoutId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Rutina',
      dayOfWeek: int.tryParse(json['dayOfWeek']?.toString() ?? '') ?? 1,
      completed: json['completed'] == true,
      restRating: (int.tryParse(json['restRating']?.toString() ?? '') ?? 0)
          .clamp(0, 5),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workoutId': workoutId,
      'name': name,
      'dayOfWeek': dayOfWeek,
      'completed': completed,
      'restRating': restRating,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class WeeklyWorkoutLog {
  final String weekStartIso;
  final List<WeeklyWorkoutEntry> entries;

  const WeeklyWorkoutLog({required this.weekStartIso, required this.entries});

  int get totalRoutines => entries.length;
  int get completedRoutines => entries.where((entry) => entry.completed).length;
  bool get completedAll =>
      entries.isNotEmpty && completedRoutines == entries.length;

  WeeklyWorkoutLog copyWith({
    String? weekStartIso,
    List<WeeklyWorkoutEntry>? entries,
  }) {
    return WeeklyWorkoutLog(
      weekStartIso: weekStartIso ?? this.weekStartIso,
      entries: entries ?? this.entries,
    );
  }

  factory WeeklyWorkoutLog.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    return WeeklyWorkoutLog(
      weekStartIso:
          json['weekStartIso']?.toString() ?? _weekStartIso(DateTime.now()),
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map(
                  (item) => WeeklyWorkoutEntry.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((entry) => entry.workoutId.isNotEmpty)
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weekStartIso': weekStartIso,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class WeeklyWorkoutRegistryStore {
  static const _prefix = 'healthy_t_weekly_workout_registry_';

  static Future<WeeklyWorkoutLog> load({
    required String email,
    required List<Map<String, dynamic>> workouts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final weekStart = _weekStartIso(DateTime.now());
    final raw = prefs.getString(_key(email, weekStart));
    WeeklyWorkoutLog log = WeeklyWorkoutLog(
      weekStartIso: weekStart,
      entries: const [],
    );

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          log = WeeklyWorkoutLog.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        debugPrint('Error decoding weekly workout log: $e');
      }
    }

    return _mergeWithWorkouts(log.copyWith(weekStartIso: weekStart), workouts);
  }

  static Future<void> save({
    required String email,
    required WeeklyWorkoutLog log,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(email, log.weekStartIso),
      jsonEncode(log.toJson()),
    );
  }

  static Future<void> clearForUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final userPrefix = '$_prefix${email.trim().toLowerCase()}_';
    final keys = prefs.getKeys().where((key) => key.startsWith(userPrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static String _key(String email, String weekStartIso) {
    return '$_prefix${email.trim().toLowerCase()}_$weekStartIso';
  }

  static WeeklyWorkoutLog _mergeWithWorkouts(
    WeeklyWorkoutLog log,
    List<Map<String, dynamic>> workouts,
  ) {
    final savedById = {for (final entry in log.entries) entry.workoutId: entry};
    final entries = workouts
        .map((workout) {
          final id = workout['id']?.toString() ?? '';
          final saved = savedById[id];
          return WeeklyWorkoutEntry(
            workoutId: id,
            name: workout['name']?.toString().trim().isNotEmpty == true
                ? workout['name'].toString().trim()
                : 'Rutina',
            dayOfWeek:
                int.tryParse(workout['day_of_week']?.toString() ?? '') ?? 1,
            completed: saved?.completed ?? false,
            restRating: saved?.restRating ?? 0,
            updatedAt: saved?.updatedAt,
          );
        })
        .where((entry) => entry.workoutId.isNotEmpty)
        .toList();

    entries.sort((a, b) {
      final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (byDay != 0) return byDay;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return log.copyWith(entries: entries);
  }
}

class WeeklyWorkoutPrUpdate {
  final String workoutId;
  final int exerciseIndex;
  final String weight;
  final String reps;
  final String date;
  final String notes;
  final bool delete;

  const WeeklyWorkoutPrUpdate({
    required this.workoutId,
    required this.exerciseIndex,
    required this.weight,
    required this.reps,
    required this.date,
    required this.notes,
    this.delete = false,
  });
}

class WeeklyWorkoutRegistrySection extends StatelessWidget {
  final WeeklyWorkoutLog? log;
  final List<Map<String, dynamic>> workouts;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final ValueChanged<WeeklyWorkoutEntry> onToggleCompleted;
  final void Function(WeeklyWorkoutEntry entry, int rating) onRestRatingChanged;
  final ValueChanged<WeeklyWorkoutPrUpdate> onPrUpdated;

  const WeeklyWorkoutRegistrySection({
    super.key,
    required this.log,
    required this.workouts,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.onToggleCompleted,
    required this.onRestRatingChanged,
    required this.onPrUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final completed = log?.completedRoutines ?? 0;
    final total = log?.totalRoutines ?? 0;
    final progress = total == 0 ? 0.0 : completed / total;
    final pending = (total - completed).clamp(0, total);
    final restAverage = _averageRestRating(log?.entries ?? const []);
    final trainingDays = _trainingDayLabels(log?.entries ?? const []);
    final prsCount = _registeredPrs(
      workouts,
    ).where((record) => record.hasPr).length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => _openRegistryDetail(context),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: isLightMode
                ? Colors.white.withOpacity(0.64)
                : const Color(0xFF171A1D).withOpacity(0.88),
            border: Border.all(
              color: isLightMode
                  ? const Color(0xFFCAD2DA).withOpacity(0.72)
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: primaryTextColor.withOpacity(
                        isLightMode ? 0.08 : 0.14,
                      ),
                    ),
                    child: Icon(
                      Icons.fact_check_rounded,
                      color: primaryTextColor,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registro semanal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          total == 0
                              ? 'Activa tu seguimiento de entrenamiento'
                              : pending == 0
                              ? 'Semana completa. Revisa energía inicial y PR.'
                              : '$pending rutinas pendientes esta semana',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: secondaryTextColor,
                    size: 28,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: progress,
                  backgroundColor: primaryTextColor.withOpacity(0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    log?.completedAll == true
                        ? Colors.green.shade600
                        : primaryTextColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (trainingDays.isNotEmpty) ...[
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: trainingDays
                      .map(
                        (day) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: primaryTextColor.withOpacity(
                              isLightMode ? 0.055 : 0.10,
                            ),
                          ),
                          child: Text(
                            day,
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: _RegistrySummaryPill(
                      label: 'Completadas',
                      value: total == 0 ? '--' : '$completed/$total',
                      icon: Icons.done_all_rounded,
                      isLightMode: isLightMode,
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RegistrySummaryPill(
                      label: 'Energía inicial',
                      value: restAverage == 0
                          ? '--'
                          : restAverage.toStringAsFixed(1),
                      icon: Icons.hotel_rounded,
                      isLightMode: isLightMode,
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RegistrySummaryPill(
                      label: 'PR',
                      value: '$prsCount',
                      icon: Icons.emoji_events_rounded,
                      isLightMode: isLightMode,
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRegistryDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.76,
        minChildSize: 0.48,
        maxChildSize: 0.94,
        expand: false,
        builder: (ctx, scrollController) {
          return _WeeklyWorkoutRegistryDetail(
            log: log,
            workouts: workouts,
            isLightMode: isLightMode,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            scrollController: scrollController,
            onToggleCompleted: onToggleCompleted,
            onRestRatingChanged: onRestRatingChanged,
            onPrUpdated: onPrUpdated,
          );
        },
      ),
    );
  }
}

class _RegistrySummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  const _RegistrySummaryPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: primaryTextColor.withOpacity(isLightMode ? 0.045 : 0.08),
      ),
      child: Row(
        children: [
          Icon(icon, color: secondaryTextColor, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyWorkoutRegistryDetail extends StatefulWidget {
  final WeeklyWorkoutLog? log;
  final List<Map<String, dynamic>> workouts;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final ScrollController scrollController;
  final ValueChanged<WeeklyWorkoutEntry> onToggleCompleted;
  final void Function(WeeklyWorkoutEntry entry, int rating) onRestRatingChanged;
  final ValueChanged<WeeklyWorkoutPrUpdate> onPrUpdated;

  const _WeeklyWorkoutRegistryDetail({
    required this.log,
    required this.workouts,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.scrollController,
    required this.onToggleCompleted,
    required this.onRestRatingChanged,
    required this.onPrUpdated,
  });

  @override
  State<_WeeklyWorkoutRegistryDetail> createState() =>
      _WeeklyWorkoutRegistryDetailState();
}

class _WeeklyWorkoutRegistryDetailState
    extends State<_WeeklyWorkoutRegistryDetail> {
  @override
  Widget build(BuildContext context) {
    final entries = widget.log?.entries ?? const <WeeklyWorkoutEntry>[];
    final completed = widget.log?.completedRoutines ?? 0;
    final total = widget.log?.totalRoutines ?? 0;
    final progress = total == 0 ? 0.0 : completed / total;
    final prs = _registeredPrs(widget.workouts);
    final pending = (total - completed).clamp(0, total);
    final restAverage = _averageRestRating(entries);
    final registeredPrs = prs.where((record) => record.hasPr).length;
    final workoutsById = {
      for (final workout in widget.workouts)
        if ((workout['id']?.toString() ?? '').isNotEmpty)
          workout['id'].toString(): workout,
    };

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        color: widget.isLightMode
            ? const Color(0xFFF1F4F6)
            : const Color(0xFF101214),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: widget.secondaryTextColor.withOpacity(0.35),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: widget.primaryTextColor.withOpacity(
                widget.isLightMode ? 0.045 : 0.08,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Registro semanal',
                        style: TextStyle(
                          color: widget.primaryTextColor,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: widget.log?.completedAll == true
                            ? Colors.green.withOpacity(0.16)
                            : widget.primaryTextColor.withOpacity(0.08),
                      ),
                      child: Text(
                        widget.log?.completedAll == true
                            ? 'Completo'
                            : '$pending pendiente${pending == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: widget.log?.completedAll == true
                              ? Colors.green.shade600
                              : widget.secondaryTextColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  total == 0
                      ? 'Agrega rutinas para iniciar tu seguimiento.'
                      : 'Toca un día para ver sus ejercicios. Califica el descanso/energía con la que empezaste antes de entrenar y actualiza tus PR.',
                  style: TextStyle(
                    color: widget.secondaryTextColor,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: progress,
                    backgroundColor: widget.primaryTextColor.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.log?.completedAll == true
                          ? Colors.green.shade600
                          : widget.primaryTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _DetailMetric(
                        label: 'Rutinas',
                        value: total == 0 ? '--' : '$completed/$total',
                        isLightMode: widget.isLightMode,
                        primaryTextColor: widget.primaryTextColor,
                        secondaryTextColor: widget.secondaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DetailMetric(
                        label: 'Energía inicial',
                        value: restAverage == 0
                            ? '--'
                            : '${restAverage.toStringAsFixed(1)}/5',
                        isLightMode: widget.isLightMode,
                        primaryTextColor: widget.primaryTextColor,
                        secondaryTextColor: widget.secondaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DetailMetric(
                        label: 'PR',
                        value: '$registeredPrs',
                        isLightMode: widget.isLightMode,
                        primaryTextColor: widget.primaryTextColor,
                        secondaryTextColor: widget.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _RegistrySectionHeader(
            icon: Icons.checklist_rounded,
            title: 'Rutinas de la semana',
            subtitle:
                'Toca un día para desplegar ejercicios; registra tu energía/descanso antes de iniciar.',
            primaryTextColor: widget.primaryTextColor,
            secondaryTextColor: widget.secondaryTextColor,
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Todavía no hay rutinas asignadas para esta semana.',
                style: TextStyle(
                  color: widget.secondaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...entries.map(
              (entry) => _RegistryRow(
                entry: entry,
                workout: workoutsById[entry.workoutId],
                isLightMode: widget.isLightMode,
                primaryTextColor: widget.primaryTextColor,
                secondaryTextColor: widget.secondaryTextColor,
                onToggleCompleted: widget.onToggleCompleted,
                onRestRatingChanged: (rating) {
                  widget.onRestRatingChanged(entry, rating);
                },
                onPrUpdated: widget.onPrUpdated,
              ),
            ),
          const SizedBox(height: 18),
          _PrSection(
            prs: prs,
            isLightMode: widget.isLightMode,
            primaryTextColor: widget.primaryTextColor,
            secondaryTextColor: widget.secondaryTextColor,
            onPrUpdated: widget.onPrUpdated,
          ),
        ],
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  const _DetailMetric({
    required this.label,
    required this.value,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isLightMode
            ? Colors.white.withOpacity(0.46)
            : Colors.black.withOpacity(0.18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primaryTextColor,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: secondaryTextColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrySectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  const _RegistrySectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: primaryTextColor, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: primaryTextColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegistryRow extends StatelessWidget {
  final WeeklyWorkoutEntry entry;
  final Map<String, dynamic>? workout;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final ValueChanged<WeeklyWorkoutEntry> onToggleCompleted;
  final ValueChanged<int> onRestRatingChanged;
  final ValueChanged<WeeklyWorkoutPrUpdate> onPrUpdated;

  const _RegistryRow({
    required this.entry,
    required this.workout,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.onToggleCompleted,
    required this.onRestRatingChanged,
    required this.onPrUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final prs = workout == null
        ? const <WeeklyWorkoutPrRecord>[]
        : _registeredPrs([workout!]);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        backgroundColor: primaryTextColor.withOpacity(
          isLightMode ? 0.055 : 0.09,
        ),
        collapsedBackgroundColor: primaryTextColor.withOpacity(
          isLightMode ? 0.045 : 0.08,
        ),
        iconColor: primaryTextColor,
        collapsedIconColor: secondaryTextColor,
        leading: Checkbox(
          value: entry.completed,
          activeColor: Colors.green.shade600,
          checkColor: Colors.white,
          onChanged: (_) => onToggleCompleted(entry),
        ),
        title: Text(
          entry.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: primaryTextColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RegistryTag(
                label: _weekdayName(entry.dayOfWeek),
                icon: Icons.calendar_month_rounded,
                isLightMode: isLightMode,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
              ),
              _RegistryTag(
                label: entry.restRating == 0
                    ? 'Energía inicial --'
                    : 'Energía inicial ${entry.restRating}/5',
                icon: Icons.bolt_rounded,
                isLightMode: isLightMode,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
              ),
            ],
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Descanso/energía antes de empezar',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(5, (index) {
              final rating = index + 1;
              final selected = rating <= entry.restRating;
              return Expanded(
                child: IconButton(
                  tooltip: 'Energía inicial $rating de 5',
                  onPressed: () => onRestRatingChanged(rating),
                  icon: Icon(
                    selected ? Icons.bolt_rounded : Icons.bolt_outlined,
                    color: selected
                        ? Colors.green.shade600
                        : secondaryTextColor,
                    size: 24,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ejercicios de ${_weekdayName(entry.dayOfWeek)}',
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (prs.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No hay ejercicios cargados para este día.',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...prs.map(
              (pr) => _ExercisePrRow(
                pr: pr,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                onTap: () => _openWeeklyPrEditor(context, pr, onPrUpdated),
              ),
            ),
        ],
      ),
    );
  }
}

class _RegistryTag extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  const _RegistryTag({
    required this.label,
    required this.icon,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: primaryTextColor.withOpacity(isLightMode ? 0.055 : 0.10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: secondaryTextColor, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExercisePrRow extends StatelessWidget {
  final WeeklyWorkoutPrRecord pr;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final VoidCallback onTap;

  const _ExercisePrRow({
    required this.pr,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: primaryTextColor.withOpacity(0.045),
          ),
          child: Row(
            children: [
              Icon(
                pr.hasPr ? Icons.emoji_events_rounded : Icons.add_rounded,
                color: pr.hasPr ? Colors.amber.shade600 : secondaryTextColor,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  pr.exercise,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  pr.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrSection extends StatelessWidget {
  final List<WeeklyWorkoutPrRecord> prs;
  final bool isLightMode;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final ValueChanged<WeeklyWorkoutPrUpdate> onPrUpdated;

  const _PrSection({
    required this.prs,
    required this.isLightMode,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.onPrUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: primaryTextColor.withOpacity(isLightMode ? 0.045 : 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RegistrySectionHeader(
            icon: Icons.emoji_events_rounded,
            title: 'Resumen de PR',
            subtitle:
                'También puedes editar cualquier PR desde este resumen completo.',
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
          ),
          const SizedBox(height: 12),
          if (prs.isEmpty)
            Text(
              'No hay ejercicios disponibles para registrar PR.',
              style: TextStyle(
                color: secondaryTextColor,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...prs.map(
              (pr) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openWeeklyPrEditor(context, pr, onPrUpdated),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          pr.hasPr
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: pr.hasPr
                              ? Colors.amber.shade600
                              : secondaryTextColor,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pr.exercise,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: primaryTextColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                pr.workoutName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            pr.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: primaryTextColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_rounded,
                          color: secondaryTextColor,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _openWeeklyPrEditor(
  BuildContext context,
  WeeklyWorkoutPrRecord pr,
  ValueChanged<WeeklyWorkoutPrUpdate> onPrUpdated,
) {
  final weightC = TextEditingController(text: pr.weight);
  final repsC = TextEditingController(text: pr.reps);
  final dateC = TextEditingController(text: pr.date);
  final notesC = TextEditingController(text: pr.notes);

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Editar PR'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pr.exercise,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightC,
              decoration: const InputDecoration(
                labelText: 'Peso del PR',
                hintText: 'Ej. 80 kg / 175 lb',
              ),
              keyboardType: TextInputType.text,
            ),
            TextField(
              controller: repsC,
              decoration: const InputDecoration(
                labelText: 'Repeticiones',
                hintText: 'Ej. 5',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: dateC,
              decoration: const InputDecoration(
                labelText: 'Fecha',
                hintText: 'AAAA-MM-DD',
              ),
            ),
            TextField(
              controller: notesC,
              decoration: const InputDecoration(labelText: 'Notas del PR'),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            onPrUpdated(
              WeeklyWorkoutPrUpdate(
                workoutId: pr.workoutId,
                exerciseIndex: pr.exerciseIndex,
                weight: '',
                reps: '',
                date: '',
                notes: '',
                delete: true,
              ),
            );
            Navigator.pop(ctx);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('BORRAR'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () {
            onPrUpdated(
              WeeklyWorkoutPrUpdate(
                workoutId: pr.workoutId,
                exerciseIndex: pr.exerciseIndex,
                weight: weightC.text.trim(),
                reps: repsC.text.trim(),
                date: dateC.text.trim(),
                notes: notesC.text.trim(),
              ),
            );
            Navigator.pop(ctx);
          },
          child: const Text('GUARDAR'),
        ),
      ],
    ),
  );
}

class WeeklyWorkoutPrRecord {
  final String workoutId;
  final int exerciseIndex;
  final String workoutName;
  final String exercise;
  final String weight;
  final String reps;
  final String date;
  final String notes;
  final String detail;

  const WeeklyWorkoutPrRecord({
    required this.workoutId,
    required this.exerciseIndex,
    required this.workoutName,
    required this.exercise,
    required this.weight,
    required this.reps,
    required this.date,
    required this.notes,
    required this.detail,
  });

  bool get hasPr => weight.trim().isNotEmpty;
}

List<WeeklyWorkoutPrRecord> _registeredPrs(
  List<Map<String, dynamic>> workouts,
) {
  final records = <WeeklyWorkoutPrRecord>[];
  for (final workout in workouts) {
    final workoutId = workout['id']?.toString() ?? '';
    final workoutName = workout['name']?.toString().trim().isNotEmpty == true
        ? workout['name'].toString().trim()
        : 'Rutina';
    final exercises =
        (workout['exercises'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    for (final entry in exercises.asMap().entries) {
      final exercise = entry.value;
      final weight = exercise['pr_weight']?.toString().trim() ?? '';
      final reps = exercise['pr_reps']?.toString().trim() ?? '';
      final date = exercise['pr_date']?.toString().trim() ?? '';
      final notes = exercise['pr_notes']?.toString().trim() ?? '';
      final detail = [
        if (weight.isNotEmpty) weight,
        if (reps.isNotEmpty) 'x $reps',
        if (date.isNotEmpty) date,
      ].join(' • ');
      records.add(
        WeeklyWorkoutPrRecord(
          workoutId: workoutId,
          exerciseIndex: entry.key,
          workoutName: workoutName,
          exercise: exercise['name']?.toString().trim().isNotEmpty == true
              ? exercise['name'].toString().trim()
              : 'Ejercicio',
          weight: weight,
          reps: reps,
          date: date,
          notes: notes,
          detail: detail.isEmpty ? 'Sin PR' : detail,
        ),
      );
    }
  }
  return records;
}

double _averageRestRating(List<WeeklyWorkoutEntry> entries) {
  final ratedEntries = entries.where((entry) => entry.restRating > 0).toList();
  if (ratedEntries.isEmpty) return 0;
  final total = ratedEntries.fold<int>(
    0,
    (sum, entry) => sum + entry.restRating,
  );
  return total / ratedEntries.length;
}

List<String> _trainingDayLabels(List<WeeklyWorkoutEntry> entries) {
  final days = entries.map((entry) => entry.dayOfWeek).toSet().toList()..sort();
  return days.map(_weekdayName).toList();
}

String _weekStartIso(DateTime date) {
  final start = DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: date.weekday - DateTime.monday));
  return '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';
}

String _weekdayName(int day) {
  switch (day) {
    case 1:
      return 'Lunes';
    case 2:
      return 'Martes';
    case 3:
      return 'Miercoles';
    case 4:
      return 'Jueves';
    case 5:
      return 'Viernes';
    case 6:
      return 'Sabado';
    case 7:
      return 'Domingo';
    default:
      return 'Sin dia';
  }
}

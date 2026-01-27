import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

enum _AttendanceMode { student, employee, combined }

class MasterCalenderAttendencePage extends StatefulWidget {
  const MasterCalenderAttendencePage({super.key});

  @override
  State<MasterCalenderAttendencePage> createState() =>
      _MasterCalenderAttendencePageState();
}

class _MasterCalenderAttendencePageState
    extends State<MasterCalenderAttendencePage>
    with SingleTickerProviderStateMixin {
  _AttendanceMode _mode = _AttendanceMode.student;

  // Filters (all optional)
  final _stuidCtrl = TextEditingController();
  final _teacherCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _classCtrl = TextEditingController();
  bool? _validOnly; // student only: null=all, true=present, false=absent

  // Date range
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day - 30);
  DateTime _end = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  // Data state
  bool _loadingEvents = false;
  bool _loadingSummary = false;
  String? _errorEvents;
  String? _errorSummary;

  List<_AttendanceEvent> _events = [];
  List<_DaySummary> _summary = [];

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    Future.microtask(() async {
      await _loadEvents();
      await _loadSummary();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _stuidCtrl.dispose();
    _teacherCtrl.dispose();
    _courseCtrl.dispose();
    _subjectCtrl.dispose();
    _classCtrl.dispose();
    super.dispose();
  }

  // -------------------- Tailwind-like helpers --------------------
  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      );

  TextStyle _h1() => const TextStyle(fontSize: 16, fontWeight: FontWeight.w800);
  TextStyle _muted() => TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600);

  String _yyyymmdd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    String? token;

    final authStr = prefs.getString('auth');
    if (authStr != null) {
      try {
        final decoded = jsonDecode(authStr);
        if (decoded is Map) {
          final m = Map<String, dynamic>.from(decoded);
          token = (m['token'] ?? m['jwt'] ?? m['access_token'])?.toString();
        }
      } catch (_) {}
    }

    final h = <String, String>{'Accept': 'application/json'};
    if (token != null && token.trim().isNotEmpty) {
      h['Authorization'] = 'Bearer ${token.trim()}';
    }
    return h;
  }

  // -------------------- API builders --------------------
  String get _base => ApiEndpoints.calendarAttendance;

  String get _studentEventsUrl => '$_base/student-events';
  String get _employeeEventsUrl => '$_base/employee-events';
  String get _combinedEventsUrl => '$_base/combined-events';

  String get _studentSummaryUrl => '$_base/student-summary';
  String get _employeeSummaryUrl => '$_base/employee-summary';

  Map<String, String> _buildQueryForStudent() {
    final qp = <String, String>{
      'start': _yyyymmdd(_start),
      'end': _yyyymmdd(_end),
    };

    final stuid = _stuidCtrl.text.trim();
    if (stuid.isNotEmpty) qp['stuid'] = stuid;

    final teacher = _teacherCtrl.text.trim();
    if (teacher.isNotEmpty) qp['teacherid'] = teacher;

    final course = _courseCtrl.text.trim();
    if (course.isNotEmpty) qp['courseid'] = course;

    final subject = _subjectCtrl.text.trim();
    if (subject.isNotEmpty) qp['subjectid'] = subject;

    final clazz = _classCtrl.text.trim();
    if (clazz.isNotEmpty) qp['classid'] = clazz;

    if (_validOnly != null) qp['valid'] = _validOnly == true ? 'true' : 'false';

    return qp;
  }

  Map<String, String> _buildQueryForEmployee() {
    final qp = <String, String>{
      'start': _yyyymmdd(_start),
      'end': _yyyymmdd(_end),
    };

    // For employee routes, backend expects attuserid OR teacherid (it maps teacherid -> attuserid)
    final teacher = _teacherCtrl.text.trim();
    if (teacher.isNotEmpty) qp['teacherid'] = teacher;

    final course = _courseCtrl.text.trim();
    if (course.isNotEmpty) qp['courseid'] = course;

    final subject = _subjectCtrl.text.trim();
    if (subject.isNotEmpty) qp['subjectid'] = subject;

    final clazz = _classCtrl.text.trim();
    if (clazz.isNotEmpty) qp['classid'] = clazz;

    return qp;
  }

  // -------------------- Loaders --------------------
  Future<void> _loadEvents() async {
    setState(() {
      _loadingEvents = true;
      _errorEvents = null;
    });

    try {
      final headers = await _authHeaders();

      final (url, qp) = switch (_mode) {
        _AttendanceMode.student => (_studentEventsUrl, _buildQueryForStudent()),
        _AttendanceMode.employee => (_employeeEventsUrl, _buildQueryForEmployee()),
        _AttendanceMode.combined => (_combinedEventsUrl, {
            ..._buildQueryForStudent(), // includes start/end + optional student filters
            ..._buildQueryForEmployee(), // includes start/end + optional employee filters
          }),
      };

      final uri = Uri.parse(url).replace(queryParameters: qp);

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final decoded = jsonDecode(resp.body);
      final list = (decoded is Map) ? decoded['events'] : null;

      final events = <_AttendanceEvent>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            events.add(_AttendanceEvent.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }

      setState(() => _events = events);
    } on TimeoutException {
      setState(() => _errorEvents = 'Timeout: calendar-attendance did not respond in time.');
    } catch (e) {
      setState(() => _errorEvents = 'Failed to load events: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingEvents = false);
    }
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _errorSummary = null;
    });

    try {
      final headers = await _authHeaders();

      Future<List<_DaySummary>> loadStudent() async {
        final uri = Uri.parse(_studentSummaryUrl).replace(queryParameters: _buildQueryForStudent());
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
        if (resp.statusCode != 200) throw Exception('Student summary HTTP ${resp.statusCode}: ${resp.body}');
        final decoded = jsonDecode(resp.body);
        final days = (decoded is Map) ? decoded['days'] : null;
        if (days is! List) return [];
        return days
            .whereType<Map>()
            .map((m) => _DaySummary.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }

      Future<List<_DaySummary>> loadEmployee() async {
        final uri = Uri.parse(_employeeSummaryUrl).replace(queryParameters: _buildQueryForEmployee());
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
        if (resp.statusCode != 200) throw Exception('Employee summary HTTP ${resp.statusCode}: ${resp.body}');
        final decoded = jsonDecode(resp.body);
        final days = (decoded is Map) ? decoded['days'] : null;
        if (days is! List) return [];
        return days
            .whereType<Map>()
            .map((m) => _DaySummary.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }

      List<_DaySummary> result;

      if (_mode == _AttendanceMode.student) {
        result = await loadStudent();
      } else if (_mode == _AttendanceMode.employee) {
        result = await loadEmployee();
      } else {
        // combined: merge both by day (YYYY-MM-DD)
        final both = await Future.wait([loadStudent(), loadEmployee()]);
        final map = <String, _DaySummary>{};

        for (final s in both[0]) {
          map[s.day] = s;
        }
        for (final e in both[1]) {
          final prev = map[e.day];
          if (prev == null) {
            map[e.day] = e;
          } else {
            map[e.day] = _DaySummary(
              day: e.day,
              total: prev.total + e.total,
              present: prev.present + e.present,
              absent: prev.absent + e.absent,
            );
          }
        }

        final keys = map.keys.toList()..sort();
        result = keys.map((k) => map[k]!).toList();
      }

      setState(() => _summary = result);
    } on TimeoutException {
      setState(() => _errorSummary = 'Timeout: summary did not respond in time.');
    } catch (e) {
      setState(() => _errorSummary = 'Failed to load summary: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final firstDate = DateTime(2000, 1, 1);
    final lastDate = DateTime(2100, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) {
        // keep white theme
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _start = DateTime(picked.year, picked.month, picked.day);
        if (_start.isAfter(_end)) {
          _end = _start;
        }
      } else {
        _end = DateTime(picked.year, picked.month, picked.day);
        if (_end.isBefore(_start)) {
          _start = _end;
        }
      }
    });

    // refresh both tabs
    await _loadEvents();
    await _loadSummary();
  }

  void _clearFilters() {
    setState(() {
      _stuidCtrl.clear();
      _teacherCtrl.clear();
      _courseCtrl.clear();
      _subjectCtrl.clear();
      _classCtrl.clear();
      _validOnly = null;
    });
  }

  Future<void> _applyAll() async {
    await _loadEvents();
    await _loadSummary();
  }

  // -------------------- UI sections --------------------
  Widget _modePills() {
    Widget pill(_AttendanceMode m, String label, IconData icon) {
      final selected = _mode == m;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () async {
          setState(() => _mode = m);
          await _applyAll();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2563EB) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? const Color(0xFF2563EB) : Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : Colors.grey.shade800),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        pill(_AttendanceMode.student, 'Student', Icons.school_rounded),
        pill(_AttendanceMode.employee, 'Employee', Icons.badge_rounded),
        pill(_AttendanceMode.combined, 'Combined', Icons.layers_rounded),
      ],
    );
  }

  Widget _filtersCard() {
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Text('Filters', style: _h1()),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Date range
          Row(
            children: [
              Expanded(
                child: _miniDateButton(
                  label: 'Start',
                  value: _yyyymmdd(_start),
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniDateButton(
                  label: 'End',
                  value: _yyyymmdd(_end),
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Inputs
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _miniField(
                ctrl: _stuidCtrl,
                label: 'Student (stuid / roll / email)',
                icon: Icons.person_rounded,
                width: 280,
              ),
              _miniField(
                ctrl: _teacherCtrl,
                label: 'Teacher ID',
                icon: Icons.person_pin_rounded,
                width: 160,
              ),
              _miniField(
                ctrl: _courseCtrl,
                label: 'Course ID',
                icon: Icons.menu_book_rounded,
                width: 160,
              ),
              _miniField(
                ctrl: _subjectCtrl,
                label: 'Subject ID',
                icon: Icons.book_rounded,
                width: 160,
              ),
              _miniField(
                ctrl: _classCtrl,
                label: 'Class/Section ID',
                icon: Icons.meeting_room_rounded,
                width: 160,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Valid toggle (student only)
          Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: _mode == _AttendanceMode.employee ? 0.45 : 1,
                  child: IgnorePointer(
                    ignoring: _mode == _AttendanceMode.employee,
                    child: _validToggle(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _applyAll,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Apply'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniDateButton({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range_rounded, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: _muted()),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _miniField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 18),
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _validToggle() {
    // null = all, true = present, false = absent
    Widget chip(String text, bool? value, IconData icon) {
      final selected = _validOnly == value;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          setState(() => _validOnly = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? const Color(0xFF2563EB) : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? const Color(0xFF2563EB) : Colors.grey.shade800),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF2563EB) : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('All', null, Icons.all_inclusive_rounded),
        chip('Present', true, Icons.check_circle_rounded),
        chip('Absent', false, Icons.cancel_rounded),
      ],
    );
  }

  Widget _eventsTab() {
    if (_loadingEvents) {
      return _loadingCard('Loading events...');
    }
    if (_errorEvents != null) {
      return _errorCard(_errorEvents!, onRetry: _loadEvents);
    }
    if (_events.isEmpty) {
      return _emptyCard('No events found for the selected filters.');
    }

    // group by day
    final Map<String, List<_AttendanceEvent>> grouped = {};
    for (final e in _events) {
      final day = _yyyymmdd(e.start.toLocal());
      grouped.putIfAbsent(day, () => []).add(e);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a)); // latest first

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day = days[i];
        final list = grouped[day]!..sort((a, b) => b.start.compareTo(a.start));

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_rounded, color: Color(0xFF2563EB), size: 18),
                    const SizedBox(width: 8),
                    Text(day, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text('${list.length}', style: _muted()),
                  ],
                ),
                const SizedBox(height: 10),
                ...list.map((e) => _eventTile(e)).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _eventTile(_AttendanceEvent e) {
    final isStudent = e.type == 'student';
    final icon = isStudent ? Icons.school_rounded : Icons.badge_rounded;

    final badgeColor = isStudent
        ? (e.attvalid == true ? const Color(0xFF22C55E) : const Color(0xFFEF4444))
        : const Color(0xFF0EA5E9);

    String timeText(DateTime d) {
      final t = d.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    final subtitleParts = <String>[];
    if (e.attsubjectid?.isNotEmpty == true) subtitleParts.add('Subj: ${e.attsubjectid}');
    if (e.attcourseid?.isNotEmpty == true) subtitleParts.add('Course: ${e.attcourseid}');
    if (e.attclassid?.isNotEmpty == true) subtitleParts.add('Class: ${e.attclassid}');
    if (e.attuserid?.isNotEmpty == true) subtitleParts.add('User: ${e.attuserid}');
    if (e.teacherid?.isNotEmpty == true) subtitleParts.add('By: ${e.teacherid}');

    final subtitle = subtitleParts.isEmpty ? '-' : subtitleParts.join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: badgeColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeText(e.start),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTab() {
    if (_loadingSummary) {
      return _loadingCard('Loading summary...');
    }
    if (_errorSummary != null) {
      return _errorCard(_errorSummary!, onRetry: _loadSummary);
    }
    if (_summary.isEmpty) {
      return _emptyCard('No summary available for this range/filters.');
    }

    final total = _summary.fold<int>(0, (s, d) => s + d.total);
    final present = _summary.fold<int>(0, (s, d) => s + d.present);
    final absent = _summary.fold<int>(0, (s, d) => s + d.absent);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_rounded, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Text('Summary', style: _h1()),
                  const Spacer(),
                  Text('${_yyyymmdd(_start)} → ${_yyyymmdd(_end)}', style: _muted()),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _miniStat('Total', total.toString(), Icons.layers_rounded, const Color(0xFF2563EB))),
                  const SizedBox(width: 10),
                  Expanded(child: _miniStat('Present', present.toString(), Icons.check_circle_rounded, const Color(0xFF22C55E))),
                  const SizedBox(width: 10),
                  Expanded(child: _miniStat('Absent', absent.toString(), Icons.cancel_rounded, const Color(0xFFEF4444))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Day list
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Day-wise', style: _h1()),
              const SizedBox(height: 10),
              ..._summary.map((d) => _dayRow(d)).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _dayRow(_DaySummary d) {
    final pct = d.total <= 0 ? 0 : ((d.present / d.total) * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              d.day,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
          _pill('${d.present} P', const Color(0xFF22C55E)),
          const SizedBox(width: 8),
          _pill('${d.absent} A', const Color(0xFFEF4444)),
          const SizedBox(width: 8),
          _pill('$pct%', const Color(0xFF2563EB)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _loadingCard(String text) {
    return ListView(
      children: [
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(text, style: _muted()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorCard(String msg, {required Future<void> Function() onRetry}) {
    return ListView(
      children: [
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Error', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 8),
              Text(msg, style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(String msg) {
    return ListView(
      children: [
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.inbox_rounded, color: Colors.grey.shade500),
              const SizedBox(width: 10),
              Expanded(child: Text(msg, style: _muted())),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text(
          'Calendar Attendance',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              await _loadEvents();
              await _loadSummary();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF2563EB),
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: Colors.grey.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.event_note_rounded), text: 'Events'),
            Tab(icon: Icon(Icons.analytics_rounded), text: 'Summary'),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            children: [
              // MODE
              _modePills(),
              const SizedBox(height: 12),

              // FILTERS
              _filtersCard(),
              const SizedBox(height: 12),

              // CONTENT
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _eventsTab(),
                    _summaryTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------- Models --------------------

class _AttendanceEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String type;

  // useful fields for display
  final String? attuserid;
  final String? attcourseid;
  final String? attsubjectid;
  final String? attclassid;
  final bool? attvalid;
  final String? teacherid;

  _AttendanceEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.type,
    this.attuserid,
    this.attcourseid,
    this.attsubjectid,
    this.attclassid,
    this.attvalid,
    this.teacherid,
  });

  factory _AttendanceEvent.fromJson(Map<String, dynamic> json) {
    final ext = (json['extendedProps'] is Map)
        ? Map<String, dynamic>.from(json['extendedProps'])
        : <String, dynamic>{};

    DateTime parseDT(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return _AttendanceEvent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Attendance').toString(),
      start: parseDT(json['start']),
      end: json['end'] == null ? null : parseDT(json['end']),
      type: (ext['type'] ?? json['type'] ?? 'student').toString(),
      attuserid: ext['attuserid']?.toString(),
      attcourseid: ext['attcourseid']?.toString(),
      attsubjectid: ext['attsubjectid']?.toString(),
      attclassid: ext['attclassid']?.toString(),
      attvalid: ext['attvalid'] is bool
          ? ext['attvalid'] as bool
          : (ext['attvalid']?.toString().toLowerCase() == 'true'
              ? true
              : (ext['attvalid']?.toString().toLowerCase() == 'false'
                  ? false
                  : null)),
      teacherid: ext['teacherid']?.toString(),
    );
  }
}

class _DaySummary {
  final String day; // YYYY-MM-DD
  final int total;
  final int present;
  final int absent;

  const _DaySummary({
    required this.day,
    required this.total,
    required this.present,
    required this.absent,
  });

  factory _DaySummary.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.round();
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return _DaySummary(
      day: (json['day'] ?? '').toString(),
      total: asInt(json['total']),
      present: asInt(json['present']),
      absent: asInt(json['absent']),
    );
  }
}

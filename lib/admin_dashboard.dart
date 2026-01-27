// lib/admin_dashboard.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'login_page.dart';
import 'master_user.dart' hide baseUrl;

// ✅ pages (your list)
import 'pages/bulktecher.dart'; // TeacherMasterPage()
import 'pages/no_internet_error.dart'; // NoInternetErrorPage()
import 'pages/MasterRolePage.dart'; // MasterRoleApiPage()
import 'pages/master_student.dart'; // MasterStudentScreen()
import 'pages/master_notice.dart'; // MasterNoticeScreen()
import 'pages/master_events.dart'; // MasterEventsPage()  <-- added & wired
import 'pages/master_employee_attendance.dart'; // MasterEmployeeAttendancePage()
import 'pages/master_depts_page.dart'; // MasterDeptsPage()
import 'pages/master_demand_letters.dart'; // MasterDemandLettersPage()
import 'pages/master_course_registration.dart'; // MasterCourseRegistrationPage()
import 'pages/master_course_offering.dart'; // MasterCourseOfferingPage()
import 'pages/master_college_screen.dart'; // MasterCollegeScreen()
import 'pages/master_college_examroutine.dart'; // MasterCollegeExamRoutinePage()
import 'pages/master_classroom.dart'; // MasterClassroomPage()
import 'pages/master_calender_attendence.dart'; // MasterCalenderAttendencePage()
import 'pages/leave_application_page.dart'; // LeaveApplicationPage()
import 'pages/error_404_page.dart'; // Error404Page()
import 'pages/college_acad_year_page.dart'; // CollegeAcadYearPage()

// ✅ Use calendar-attendance base from api_endpoints.dart
import 'core/config/api_endpoints.dart';

/// ----------------- ENV + API CONFIG -----------------
class AppConfig {
  static String get baseUrl {
    final v = dotenv.env['BASE_URL'] ?? '';
    if (v.trim().isNotEmpty) return v.trim();
    return 'https://poweranger-turbo.onrender.com'; // fallback
  }

  static String get apiPrefix {
    final v = dotenv.env['API_PREFIX'] ?? '';
    if (v.trim().isNotEmpty) return v.trim();
    return '/api'; // fallback
  }
}

class Api {
  static String get baseUrl => AppConfig.baseUrl;
  static String get apiPrefix => AppConfig.apiPrefix;

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  // ✅ As you requested
  static String get chartData => _join(baseUrl, '$apiPrefix/chart-data');
}

class AdminDashboardScreen extends StatefulWidget {
  final String username;
  final String roleDescription;

  const AdminDashboardScreen({
    super.key,
    required this.username,
    required this.roleDescription,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  // Main page animations
  late final AnimationController _controller;
  late final Animation<double> _fadeHeader;
  late final Animation<double> _fadeCards;
  late final Animation<Offset> _slideHeader;
  late final Animation<Offset> _slideCards;

  // Menu animation
  late final AnimationController _menuController;
  late final Animation<Offset> _menuSlide;
  bool _isMenuOpen = false;

  // Skeleton shimmer controller
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  // API state
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _raw = {};
  Map<String, dynamic> _counts = {}; // response.data

  // ✅ Calendar-attendance snapshot state
  bool _attLoading = true;
  String? _attError;
  int _stuPresent30 = 0;
  int _stuAbsent30 = 0;
  int _stuTotal30 = 0;

  int _empPresent30 = 0;
  int _empAbsent30 = 0;
  int _empTotal30 = 0;

  @override
  void initState() {
    super.initState();

    // -------- MAIN PAGE ANIMATION --------
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeHeader = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    _fadeCards = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    _slideHeader = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(_fadeHeader);

    _slideCards = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_fadeCards);

    _controller.forward();

    // -------- MENU ANIMATION --------
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _menuSlide = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _menuController,
        curve: Curves.easeOutCubic,
      ),
    );

    // -------- SKELETON SHIMMER --------
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _shimmerAnim =
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);
    _shimmerCtrl.repeat(reverse: true);

    // Fetch counts + attendance snapshot
    Future.microtask(() async {
      await _fetchCounts();
      await _fetchAttendanceSnapshot30d();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _menuController.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _menuController.forward();
      } else {
        _menuController.reverse();
      }
    });
  }

  Future<void> _logout() async {
    if (_isMenuOpen) _toggleMenu();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth');
    await prefs.remove('sessionUser');
    await prefs.remove('dashboard_hide_charts');
    await prefs.remove('group_mode');
    await prefs.remove('is_group_admin');
    await prefs.remove('child_user_role');

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  /// ✅ open only the page you clicked
  void _openFromMenu(Widget page) {
    if (_isMenuOpen) _toggleMenu();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    });
  }

  // ✅ Navigation helpers (existing)
  void _openStudents() => _openFromMenu(const MasterStudentScreen());
  void _openAddStudent() =>
      _openFromMenu(const MasterStudentScreen(openAddOnStart: true));
  void _openAcadYear() => _openFromMenu(const CollegeAcadYearPage());
  void _openNotices() => _openFromMenu(const MasterNoticeScreen());
  void _openClassroom() => _openFromMenu(const MasterClassroomPage());
  void _openSettings404() => _openFromMenu(const Error404Page());
  void _openCalendarAttendance() =>
      _openFromMenu(const MasterCalenderAttendencePage());
  void _openExamRoutine() =>
      _openFromMenu(const MasterCollegeExamRoutinePage());

  // ✅ NEW helpers (your other pages)
  void _openTeacherBulkUpload() => _openFromMenu(const TeacherMasterPage());

  void _openEvents() => _openFromMenu(const MasterEventsPage());
  void _openEmployeeAttendance() =>
      _openFromMenu(const MasterEmployeeAttendancePage());
  void _openDepartments() => _openFromMenu(const MasterDeptsPage());
  void _openDemandLetters() => _openFromMenu(const MasterDemandLettersPage());
  void _openCourseRegistration() =>
      _openFromMenu(const MasterCourseRegistrationPage());
  void _openCourseOffering() =>
      _openFromMenu(const MasterCourseOfferingPage());
  void _openCollege() => _openFromMenu(const MasterCollegeScreen());

  void _openLeaveApplication() => _openFromMenu(const LeaveApplicationPage());
  void _openNoInternet() => _openFromMenu(const NoInternetErrorPage());

  // ===================== API Fetch =====================
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

    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    return headers;
  }

  String _yyyymmdd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _fetchCounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(Api.chartData);
      final headers = await _authHeaders();

      final resp = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 20),
          );

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          _raw = Map<String, dynamic>.from(decoded);
          final data = decoded['data'];
          if (data is Map) {
            _counts = Map<String, dynamic>.from(data);
          } else {
            _counts = {};
          }
        } else {
          _raw = {'data': decoded};
          _counts = {};
        }
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: /chart-data did not respond in time.';
    } catch (e) {
      _error = 'Failed to load dashboard data: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ✅ Fetch calendar-attendance summary (last 30 days) and show as chart in dashboard
  Future<void> _fetchAttendanceSnapshot30d() async {
    setState(() {
      _attLoading = true;
      _attError = null;
    });

    try {
      final headers = await _authHeaders();

      final now = DateTime.now();
      final start =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      final end = DateTime(now.year, now.month, now.day);

      final qp = {
        'start': _yyyymmdd(start),
        'end': _yyyymmdd(end),
      };

      // Base from: lib/core/config/api_endpoints.dart
      final base = ApiEndpoints.calendarAttendance;

      final stuUri =
          Uri.parse('$base/student-summary').replace(queryParameters: qp);
      final empUri =
          Uri.parse('$base/employee-summary').replace(queryParameters: qp);

      final results = await Future.wait([
        http.get(stuUri, headers: headers).timeout(const Duration(seconds: 25)),
        http.get(empUri, headers: headers).timeout(const Duration(seconds: 25)),
      ]);

      // ---- student summary ----
      final stuResp = results[0];
      if (stuResp.statusCode != 200) {
        throw Exception(
            'Student summary HTTP ${stuResp.statusCode}: ${stuResp.body}');
      }
      final stuDecoded = jsonDecode(stuResp.body);
      final stuDays = (stuDecoded is Map) ? stuDecoded['days'] : null;

      int stuTotal = 0, stuPresent = 0, stuAbsent = 0;
      if (stuDays is List) {
        for (final d in stuDays) {
          if (d is Map) {
            stuTotal += _asInt(d['total']);
            stuPresent += _asInt(d['present']);
            stuAbsent += _asInt(d['absent']);
          }
        }
      }

      // ---- employee summary ----
      final empResp = results[1];
      if (empResp.statusCode != 200) {
        throw Exception(
            'Employee summary HTTP ${empResp.statusCode}: ${empResp.body}');
      }
      final empDecoded = jsonDecode(empResp.body);
      final empDays = (empDecoded is Map) ? empDecoded['days'] : null;

      int empTotal = 0, empPresent = 0, empAbsent = 0;
      if (empDays is List) {
        for (final d in empDays) {
          if (d is Map) {
            empTotal += _asInt(d['total']);
            empPresent += _asInt(d['present']);
            empAbsent += _asInt(d['absent']);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _stuTotal30 = stuTotal;
        _stuPresent30 = stuPresent;
        _stuAbsent30 = stuAbsent;

        _empTotal30 = empTotal;
        _empPresent30 = empPresent;
        _empAbsent30 = empAbsent;

        _attLoading = false;
      });
    } on TimeoutException {
      setState(() {
        _attError =
            'Timeout: calendar-attendance summary did not respond in time.';
        _attLoading = false;
      });
    } catch (e) {
      setState(() {
        _attError = 'Failed to load calendar-attendance summary: $e';
        _attLoading = false;
      });
    }
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    final cleaned = s.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  // KPI from your real keys
  int get _students => _asInt(_counts['student_master']);
  int get _users => _asInt(_counts['master_user']);
  int get _courses => _asInt(_counts['master_course']);
  int get _roles => _asInt(_counts['user_role']);
  int get _classrooms => _asInt(_counts['master_classroom']);

  String _prettyKey(String k) {
    return k
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // ===================== Skeleton =====================
  Widget _skeletonBox({double? w, double? h, BorderRadius? br}) {
    return FadeTransition(
      opacity: _shimmerAnim,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: br ?? BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _statSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _skeletonBox(w: 42, h: 42, br: BorderRadius.circular(999)),
              const Spacer(),
              _skeletonBox(w: 22, h: 10, br: BorderRadius.circular(999)),
            ],
          ),
          const SizedBox(height: 10),
          _skeletonBox(w: 90, h: 10),
          const SizedBox(height: 8),
          _skeletonBox(w: 70, h: 16),
          const SizedBox(height: 8),
          _skeletonBox(w: 120, h: 10),
        ],
      ),
    );
  }

  Widget _pieSkeletonCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _skeletonBox(w: 140, h: 140, br: BorderRadius.circular(999)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonBox(w: 140, h: 12),
                const SizedBox(height: 10),
                _skeletonBox(w: double.infinity, h: 10),
                const SizedBox(height: 10),
                _skeletonBox(w: double.infinity, h: 10),
                const SizedBox(height: 10),
                _skeletonBox(w: 180, h: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================== Cards =====================
  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Icon(Icons.more_horiz_rounded,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: card,
    );
  }

  // ===================== PIE DATA =====================
  List<_PieSlice> _buildPrimarySlices() {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF22C55E),
      Color(0xFFF97316),
      Color(0xFF7C3AED),
    ];

    final items = <Map<String, dynamic>>[
      {'label': 'Students', 'value': _students, 'color': colors[0]},
      {'label': 'Users', 'value': _users, 'color': colors[1]},
      {'label': 'Courses', 'value': _courses, 'color': colors[2]},
      {'label': 'Role Maps', 'value': _roles, 'color': colors[3]},
    ];

    return items
        .map((m) => _PieSlice(
              label: m['label'] as String,
              value: (m['value'] as int).toDouble(),
              color: m['color'] as Color,
            ))
        .toList();
  }

  List<_PieSlice> _buildTopTableSlices({int topN = 6}) {
    const palette = [
      Color(0xFF2563EB),
      Color(0xFF22C55E),
      Color(0xFFF97316),
      Color(0xFF7C3AED),
      Color(0xFF0EA5E9),
      Color(0xFFEF4444),
      Color(0xFF334155),
      Color(0xFF16A34A),
      Color(0xFF6366F1),
      Color(0xFFEA580C),
    ];

    final entries = _counts.entries
        .map((e) => MapEntry(e.key, _asInt(e.value)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return const [];

    final top = entries.take(topN).toList();
    final rest = entries.skip(topN).toList();

    final slices = <_PieSlice>[];
    for (var i = 0; i < top.length; i++) {
      slices.add(
        _PieSlice(
          label: _prettyKey(top[i].key),
          value: top[i].value.toDouble(),
          color: palette[i % palette.length],
        ),
      );
    }

    final othersSum = rest.fold<int>(0, (s, e) => s + e.value);
    if (othersSum > 0) {
      slices.add(
        _PieSlice(
          label: 'Others',
          value: othersSum.toDouble(),
          color: const Color(0xFF94A3B8),
        ),
      );
    }

    return slices;
  }

  List<_PieSlice> _buildAttendanceSlices(int present, int absent) {
    return [
      _PieSlice(
        label: 'Present',
        value: present.toDouble(),
        color: const Color(0xFF22C55E),
      ),
      _PieSlice(
        label: 'Absent',
        value: absent.toDouble(),
        color: const Color(0xFFEF4444),
      ),
    ];
  }

  Widget _pieCard({
    required String title,
    required String subtitle,
    required List<_PieSlice> slices,
  }) {
    final total = slices.fold<double>(0, (s, p) => s + p.value);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: _PieChart(
                  slices: slices,
                  holeRadiusFactor: 0.62,
                  centerTextTop: total == 0 ? '0' : total.toInt().toString(),
                  centerTextBottom: 'Total',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: slices.map((s) {
                    final pct = total <= 0 ? 0 : ((s.value / total) * 100);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${s.value.toInt()}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ Attendance chart card on dashboard
  Widget _attendanceSnapshotCard() {
    if (_attLoading) return _pieSkeletonCard();

    if (_attError != null) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.withOpacity(0.25)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance Snapshot',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _attError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _fetchAttendanceSnapshot30d,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            )
          ],
        ),
      );
    }

    final stuSlices = _buildAttendanceSlices(_stuPresent30, _stuAbsent30);
    final empSlices = _buildAttendanceSlices(_empPresent30, _empAbsent30);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Attendance Snapshot (Last 30 Days)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _openCalendarAttendance,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: const Color(0xFF2563EB).withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.open_in_new_rounded,
                          size: 16, color: Color(0xFF2563EB)),
                      SizedBox(width: 6),
                      Text(
                        'Open',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Students + Employees summary from calendar-attendance',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Students',
                        style:
                            TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 150,
                      child: _PieChart(
                        slices: stuSlices,
                        holeRadiusFactor: 0.64,
                        centerTextTop: _stuTotal30.toString(),
                        centerTextBottom: 'Total',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Employees',
                        style:
                            TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 150,
                      child: _PieChart(
                        slices: empSlices,
                        holeRadiusFactor: 0.64,
                        centerTextTop: _empTotal30.toString(),
                        centerTextBottom: 'Total',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _miniPill(
                  icon: Icons.check_circle_rounded,
                  label: 'Stu Present: $_stuPresent30',
                  color: const Color(0xFF22C55E)),
              _miniPill(
                  icon: Icons.cancel_rounded,
                  label: 'Stu Absent: $_stuAbsent30',
                  color: const Color(0xFFEF4444)),
              _miniPill(
                  icon: Icons.check_circle_rounded,
                  label: 'Emp Present: $_empPresent30',
                  color: const Color(0xFF22C55E)),
              _miniPill(
                  icon: Icons.cancel_rounded,
                  label: 'Emp Absent: $_empAbsent30',
                  color: const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPill(
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ===================== MENU UI HELPERS (NEW, DRILLING) =====================
  Widget _menuHeader() {
    const primary = Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            alignment: Alignment.center,
            child:
                const Icon(Icons.admin_panel_settings_rounded, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(widget.roleDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.18)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600)),
                  ]
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _menuSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.18)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: color),
          ),
          title: Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          subtitle: Text('Tap to expand',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
          children: children,
        ),
      ),
    );
  }

  // ===================== MAIN BUILD =====================
  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2563EB);

    final primarySlices = _buildPrimarySlices();
    final topTableSlices = _buildTopTableSlices(topN: 6);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: Stack(
          children: [
            // ================= MAIN CONTENT =================
            Column(
              children: [
                // ---------- HEADER ----------
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: SlideTransition(
                    position: _slideHeader,
                    child: FadeTransition(
                      opacity: _fadeHeader,
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _toggleMenu,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: AnimatedIcon(
                                icon: AnimatedIcons.menu_close,
                                progress: _menuController,
                                size: 22,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF2563EB),
                                  Color(0xFF22C55E),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'C1',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, Super Admin',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  widget.username,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _loading
                                ? null
                                : () async {
                                    await _fetchCounts();
                                    await _fetchAttendanceSnapshot30d();
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Refresh',
                          ),
                          IconButton(
                            onPressed: _logout,
                            icon: const Icon(Icons.logout_rounded),
                            tooltip: 'Logout',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------- ROLE TAG ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FadeTransition(
                      opacity: _fadeHeader,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 16,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.roleDescription,
                              style: const TextStyle(
                                fontSize: 11,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ============== BODY (SCROLLABLE) ==============
                Expanded(
                  child: SlideTransition(
                    position: _slideCards,
                    child: FadeTransition(
                      opacity: _fadeCards,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Database Overview',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                if (_loading)
                                  Row(
                                    children: const [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Loading...',
                                          style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (_error != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.25)),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Row 1
                            Row(
                              children: [
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.school_rounded,
                                          title: 'Students',
                                          value: _students.toString(),
                                          subtitle: 'student_master',
                                          color: const Color(0xFF2563EB),
                                          onTap: _openStudents,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.people_alt_rounded,
                                          title: 'Users',
                                          value: _users.toString(),
                                          subtitle: 'master_user',
                                          color: const Color(0xFF22C55E),
                                          onTap: () => _openFromMenu(
                                              const MasterUserScreen()),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Row 2
                            Row(
                              children: [
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.menu_book_rounded,
                                          title: 'Courses',
                                          value: _courses.toString(),
                                          subtitle: 'master_course',
                                          color: const Color(0xFFF97316),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.verified_user_rounded,
                                          title: 'Role Mappings',
                                          value: _roles.toString(),
                                          subtitle: 'user_role',
                                          color: const Color(0xFF7C3AED),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Row 3 (Classrooms + Academic Year)
                            Row(
                              children: [
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.meeting_room_rounded,
                                          title: 'Classrooms',
                                          value: _classrooms.toString(),
                                          subtitle: 'master_classroom',
                                          color: const Color(0xFF0EA5E9),
                                          onTap: _openClassroom,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.date_range_rounded,
                                          title: 'Academic Year',
                                          value: _asInt(
                                                  _counts['college_acad_year'])
                                              .toString(),
                                          subtitle: 'college_acad_year',
                                          color: const Color(0xFF6366F1),
                                          onTap: _openAcadYear,
                                        ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // ✅ Analytics
                            Text(
                              'Analytics',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            const SizedBox(height: 10),

                            _loading
                                ? _pieSkeletonCard()
                                : _pieCard(
                                    title: 'Core Modules Share',
                                    subtitle:
                                        'Students / Users / Courses / Role Mappings',
                                    slices: primarySlices,
                                  ),

                            const SizedBox(height: 12),

                            _loading
                                ? _pieSkeletonCard()
                                : (topTableSlices.isEmpty
                                    ? Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                              color: Colors.grey.shade200),
                                        ),
                                        padding: const EdgeInsets.all(14),
                                        child: Text(
                                          'No non-zero tables found to build the Top Tables pie chart.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      )
                                    : _pieCard(
                                        title: 'Top Tables Share',
                                        subtitle: 'OverView',
                                        slices: topTableSlices,
                                      )),

                            const SizedBox(height: 12),

                            // ✅ Attendance snapshot
                            _attendanceSnapshotCard(),

                            const SizedBox(height: 18),

                            const Text(
                              'Quick Actions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _QuickActionChip(
                                  icon: Icons.school_rounded,
                                  label: 'Students',
                                  color: const Color(0xFFF97316),
                                  onTap: _openStudents,
                                ),
                                _QuickActionChip(
                                  icon: Icons.person_add_alt_1_rounded,
                                  label: 'Add Student',
                                  color: const Color(0xFF2563EB),
                                  onTap: _openAddStudent,
                                ),
                                _QuickActionChip(
                                  icon: Icons.file_upload_rounded,
                                  label: 'Teacher Bulk Upload',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: _openTeacherBulkUpload,
                                ),
                                _QuickActionChip(
                                  icon: Icons.meeting_room_rounded,
                                  label: 'Classrooms',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: _openClassroom,
                                ),
                                _QuickActionChip(
                                  icon: Icons.date_range_rounded,
                                  label: 'Academic Year',
                                  color: const Color(0xFF7C3AED),
                                  onTap: _openAcadYear,
                                ),
                                _QuickActionChip(
                                  icon: Icons.event_note_rounded,
                                  label: 'Exam Routine',
                                  color: const Color(0xFF6366F1),
                                  onTap: _openExamRoutine,
                                ),
                                _QuickActionChip(
                                  icon: Icons.event_available_rounded,
                                  label: 'Calendar Attendance',
                                  color: const Color(0xFF22C55E),
                                  onTap: _openCalendarAttendance,
                                ),
                                _QuickActionChip(
                                  icon: Icons.campaign_rounded,
                                  label: 'Notices',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: _openNotices,
                                ),
                                _QuickActionChip(
                                  icon: Icons.event_rounded,
                                  label: 'Events',
                                  color: const Color(0xFF7C3AED),
                                  onTap: _openEvents, // ✅ quick link
                                ),
                                _QuickActionChip(
                                  icon: Icons.assignment_rounded,
                                  label: 'Leave Application',
                                  color: const Color(0xFFF97316),
                                  onTap: _openLeaveApplication,
                                ),
                                _QuickActionChip(
                                  icon: Icons.analytics_rounded,
                                  label: 'Refresh Snapshot',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: () async {
                                    await _fetchCounts();
                                    await _fetchAttendanceSnapshot30d();
                                  },
                                ),
                                _QuickActionChip(
                                  icon: Icons.settings_suggest_rounded,
                                  label: 'Settings',
                                  color: const Color(0xFF6366F1),
                                  onTap: _openSettings404,
                                ),
                              ],
                            ),

                            const SizedBox(height: 28),

                            if (!_loading && _raw.isNotEmpty)
                              Text(
                                'API: ${_raw['status'] ?? '-'} • ${_raw['timestamp'] ?? '-'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),

                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ================= HAMBURGER SLIDE MENU (NEW DRILLING UI) =================
            if (_isMenuOpen) ...[
              GestureDetector(
                onTap: _toggleMenu,
                child: Container(color: Colors.black.withOpacity(0.25)),
              ),
              SlideTransition(
                position: _menuSlide,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.78,
                    height: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // top row
                        Row(
                          children: [
                            const Icon(Icons.dashboard_rounded,
                                size: 22, color: Color(0xFF2563EB)),
                            const SizedBox(width: 8),
                            const Text(
                              'Admin Menu',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w900),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _toggleMenu,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        _menuHeader(),
                        const SizedBox(height: 12),

                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _menuItem(
                                  icon: Icons.home_rounded,
                                  title: 'Dashboard',
                                  subtitle: 'Overview & analytics',
                                  color: const Color(0xFF2563EB),
                                  onTap: _toggleMenu,
                                ),

                                _menuSection(
                                  icon: Icons.groups_2_rounded,
                                  title: 'People (Masters)',
                                  color: const Color(0xFF7C3AED),
                                  initiallyExpanded: true,
                                  children: [
                                    _menuItem(
                                      icon: Icons.people_alt_rounded,
                                      title: 'Users',
                                      subtitle: 'master_user',
                                      color: const Color(0xFF22C55E),
                                      onTap: () =>
                                          _openFromMenu(const MasterUserScreen()),
                                    ),
                                    _menuItem(
                                      icon: Icons.school_rounded,
                                      title: 'Students',
                                      subtitle: 'student_master',
                                      color: const Color(0xFF2563EB),
                                      onTap: _openStudents,
                                    ),
                                    _menuItem(
                                      icon: Icons.file_upload_rounded,
                                      title: 'Teacher Bulk Upload',
                                      subtitle: 'CSV bulk import',
                                      color: const Color(0xFF0EA5E9),
                                      onTap: _openTeacherBulkUpload,
                                    ),
                                    _menuItem(
                                      icon: Icons.apartment_rounded,
                                      title: 'Departments',
                                      subtitle: 'master_depts',
                                      color: const Color(0xFF6366F1),
                                      onTap: _openDepartments,
                                    ),
                                  ],
                                ),

                                _menuSection(
                                  icon: Icons.school_outlined,
                                  title: 'Academics',
                                  color: const Color(0xFFF97316),
                                  children: [
                                    _menuItem(
                                      icon: Icons.account_balance_rounded,
                                      title: 'College',
                                      subtitle: 'master_college',
                                      color: const Color(0xFF2563EB),
                                      onTap: _openCollege,
                                    ),
                                    _menuItem(
                                      icon: Icons.date_range_rounded,
                                      title: 'Academic Year',
                                      subtitle: 'college_acad_year',
                                      color: const Color(0xFF7C3AED),
                                      onTap: _openAcadYear,
                                    ),
                                    _menuItem(
                                      icon: Icons.meeting_room_rounded,
                                      title: 'Classrooms',
                                      subtitle: 'master_classroom',
                                      color: const Color(0xFF0EA5E9),
                                      onTap: _openClassroom,
                                    ),
                                    _menuItem(
                                      icon: Icons.view_list_rounded,
                                      title: 'Course Offering',
                                      subtitle: 'offering',
                                      color: const Color(0xFF22C55E),
                                      onTap: _openCourseOffering,
                                    ),
                                    _menuItem(
                                      icon: Icons.how_to_reg_rounded,
                                      title: 'Course Registration',
                                      subtitle: 'registration',
                                      color: const Color(0xFFF97316),
                                      onTap: _openCourseRegistration,
                                    ),
                                    _menuItem(
                                      icon: Icons.event_note_rounded,
                                      title: 'Exam Routine',
                                      subtitle: 'exam schedules',
                                      color: const Color(0xFF6366F1),
                                      onTap: _openExamRoutine,
                                    ),
                                  ],
                                ),

                                _menuSection(
                                  icon: Icons.fact_check_rounded,
                                  title: 'Attendance',
                                  color: const Color(0xFF22C55E),
                                  children: [
                                    _menuItem(
                                      icon: Icons.event_available_rounded,
                                      title: 'Calendar Attendance',
                                      subtitle: 'student + employee summary',
                                      color: const Color(0xFF22C55E),
                                      onTap: _openCalendarAttendance,
                                    ),
                                    _menuItem(
                                      icon: Icons.badge_outlined,
                                      title: 'Employee Attendance',
                                      subtitle: 'master_employee_attendance',
                                      color: const Color(0xFF2563EB),
                                      onTap: _openEmployeeAttendance,
                                    ),
                                  ],
                                ),

                                _menuSection(
                                  icon: Icons.campaign_rounded,
                                  title: 'Communication',
                                  color: const Color(0xFF0EA5E9),
                                  children: [
                                    _menuItem(
                                      icon: Icons.campaign_rounded,
                                      title: 'Notices',
                                      subtitle: 'master_notice',
                                      color: const Color(0xFF0EA5E9),
                                      onTap: _openNotices,
                                    ),
                                    _menuItem(
                                      icon: Icons.event_rounded,
                                      title: 'Events',
                                      subtitle: 'master_events',
                                      color: const Color(0xFF7C3AED),
                                      onTap: _openEvents, // ✅ menu link
                                    ),
                                    _menuItem(
                                      icon: Icons.description_rounded,
                                      title: 'Demand Letters',
                                      subtitle: 'master_demand_letters',
                                      color: const Color(0xFFF97316),
                                      onTap: _openDemandLetters,
                                    ),
                                    _menuItem(
                                      icon: Icons.assignment_rounded,
                                      title: 'Leave Application',
                                      subtitle: 'leave-application',
                                      color: const Color(0xFF2563EB),
                                      onTap: _openLeaveApplication,
                                    ),
                                  ],
                                ),

                                _menuSection(
                                  icon: Icons.settings_rounded,
                                  title: 'System',
                                  color: const Color(0xFF334155),
                                  children: [
                                    _menuItem(
                                      icon: Icons.wifi_off_rounded,
                                      title: 'No Internet (Test)',
                                      subtitle: 'offline screen',
                                      color: const Color(0xFFEF4444),
                                      onTap: _openNoInternet,
                                    ),
                                    _menuItem(
                                      icon: Icons.settings_suggest_rounded,
                                      title: 'Settings',
                                      subtitle: 'coming soon',
                                      color: const Color(0xFF6366F1),
                                      onTap: _openSettings404,
                                    ),
                                    _menuItem(
                                      icon: Icons.refresh_rounded,
                                      title: 'Refresh Snapshot',
                                      subtitle: 'reload dashboard data',
                                      color: const Color(0xFF0EA5E9),
                                      onTap: () async {
                                        await _fetchCounts();
                                        await _fetchAttendanceSnapshot30d();
                                      },
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                InkWell(
                                  onTap: _logout,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444)
                                          .withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFEF4444)
                                              .withOpacity(0.18)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.logout_rounded,
                                            color: Color(0xFFEF4444)),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Logout',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFFEF4444)),
                                        ),
                                        const Spacer(),
                                        Icon(Icons.chevron_right_rounded,
                                            color: Colors.grey.shade600),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.grey.shade300),
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
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== PIE CHART WIDGETS =====================
class _PieSlice {
  final String label;
  final double value;
  final Color color;

  const _PieSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _PieChart extends StatelessWidget {
  final List<_PieSlice> slices;
  final double holeRadiusFactor; // 0..1
  final String centerTextTop;
  final String centerTextBottom;

  const _PieChart({
    required this.slices,
    this.holeRadiusFactor = 0.6,
    this.centerTextTop = '',
    this.centerTextBottom = '',
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(
        slices: slices,
        holeRadiusFactor: holeRadiusFactor,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              centerTextTop,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              centerTextBottom,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<_PieSlice> slices;
  final double holeRadiusFactor;

  _PiePainter({
    required this.slices,
    required this.holeRadiusFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, p) => s + p.value);

    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * (1 - holeRadiusFactor)
      ..color = const Color(0xFFE5E7EB);

    canvas.drawCircle(
      center,
      radius * (holeRadiusFactor + (1 - holeRadiusFactor) / 2),
      bgPaint,
    );

    if (total <= 0) return;

    var start = -math.pi / 2;
    final stroke = radius * (1 - holeRadiusFactor);

    for (final s in slices) {
      final sweep = (s.value / total) * math.pi * 2;
      if (sweep <= 0) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = s.color;

      final r = radius * (holeRadiusFactor + (1 - holeRadiusFactor) / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        sweep,
        false,
        paint,
      );

      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.holeRadiusFactor != holeRadiusFactor;
  }
}

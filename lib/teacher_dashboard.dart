// ✅ File: lib/teacher_dashboard.dart
// ✅ Teacher Dashboard UI upgraded to match Admin Dashboard style
// ✅ Keeps LoginPage connection: TeacherDashboardScreen(username, roleDescription)
// ✅ Safe + resilient API parsing (won't crash if backend fields differ)
// ✅ No external page imports (uses internal placeholder pages so it compiles)

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

  // ✅ Using endpoints seen in your logs (safe if some return 404/500 -> UI won't break)
  static String get teacherDtls => _join(baseUrl, '$apiPrefix/teacher-dtls');

  static String notices({int page = 1, int limit = 8}) =>
      _join(baseUrl, '$apiPrefix/notices/view-notices?page=$page&limit=$limit');

  static String announcements({int page = 1, int limit = 8}) => _join(
    baseUrl,
    '$apiPrefix/announcements/view-announcements?page=$page&limit=$limit',
  );

  static String events({int page = 1, int limit = 8}) =>
      _join(baseUrl, '$apiPrefix/events/view-events?page=$page&limit=$limit');
}

/// ===================== TEACHER DASHBOARD =====================

class TeacherDashboardScreen extends StatefulWidget {
  final String username;
  final String roleDescription;

  const TeacherDashboardScreen({
    super.key,
    required this.username,
    required this.roleDescription,
  });

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen>
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

  Map<String, dynamic> _teacher = {};
  int _notices = 0;
  int _events = 0;
  int _announcements = 0;

  // Optional teacher KPIs (best-effort from teacher-dtls payload)
  int _subjects = 0;
  int _classes = 0;

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

    _menuSlide = Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic),
        );

    // -------- SKELETON SHIMMER --------
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _shimmerAnim = CurvedAnimation(
      parent: _shimmerCtrl,
      curve: Curves.easeInOut,
    );
    _shimmerCtrl.repeat(reverse: true);

    Future.microtask(_fetchDashboardSnapshot);
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

  /// ✅ open only the page you clicked (internal placeholder pages)
  void _openFromMenu(Widget page) {
    if (_isMenuOpen) _toggleMenu();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    });
  }

  // ===================== API HELPERS =====================
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

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    final cleaned = s.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  int _pickIntByKeys(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return _asInt(m[k]);
    }
    return 0;
  }

  /// tries to extract count from many common API shapes:
  /// {total: 12}, {count: 12}, {data: {total: 12}}, {data: []}, {rows: []}, {items: []}
  int _extractCount(dynamic decoded) {
    try {
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);

        // direct totals
        for (final k in const ['total', 'count', 'records', 'totalCount']) {
          if (m[k] != null) return _asInt(m[k]);
        }

        // nested data map
        final data = m['data'];
        if (data is Map) {
          for (final k in const ['total', 'count', 'records', 'totalCount']) {
            if (data[k] != null) return _asInt(data[k]);
          }
        }

        // list shapes
        if (data is List) return data.length;
        final rows = m['rows'];
        if (rows is List) return rows.length;
        final items = m['items'];
        if (items is List) return items.length;
        final result = m['result'];
        if (result is List) return result.length;
      }

      if (decoded is List) return decoded.length;
    } catch (_) {}
    return 0;
  }

  Future<void> _fetchDashboardSnapshot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final headers = await _authHeaders();

      final futures = <Future<http.Response>>[
        http
            .get(Uri.parse(Api.teacherDtls), headers: headers)
            .timeout(const Duration(seconds: 20)),
        http
            .get(Uri.parse(Api.notices(page: 1, limit: 8)), headers: headers)
            .timeout(const Duration(seconds: 20)),
        http
            .get(Uri.parse(Api.events(page: 1, limit: 8)), headers: headers)
            .timeout(const Duration(seconds: 20)),
        http
            .get(
              Uri.parse(Api.announcements(page: 1, limit: 8)),
              headers: headers,
            )
            .timeout(const Duration(seconds: 20)),
      ];

      final res = await Future.wait(futures);

      // teacher-dtls
      final tResp = res[0];
      if (tResp.statusCode == 200) {
        final decoded = jsonDecode(tResp.body);
        if (decoded is Map) {
          // best-effort: allow teacher object at decoded['data'] or decoded directly
          final teacherObj = (decoded['data'] is Map)
              ? Map<String, dynamic>.from(decoded['data'])
              : Map<String, dynamic>.from(decoded);
          _teacher = teacherObj;

          // best-effort KPI keys (won't harm if not present)
          _subjects = _pickIntByKeys(teacherObj, [
            'subject_count',
            'subjects',
            'total_subjects',
            'assigned_subjects',
          ]);

          _classes = _pickIntByKeys(teacherObj, [
            'class_count',
            'classes',
            'total_classes',
            'assigned_classes',
          ]);
        }
      }

      // notices
      final nResp = res[1];
      if (nResp.statusCode == 200) {
        _notices = _extractCount(jsonDecode(nResp.body));
      }

      // events
      final eResp = res[2];
      if (eResp.statusCode == 200) {
        _events = _extractCount(jsonDecode(eResp.body));
      }

      // announcements
      final aResp = res[3];
      if (aResp.statusCode == 200) {
        _announcements = _extractCount(jsonDecode(aResp.body));
      }

      // If everything failed -> show a meaningful error
      final failedAll =
          (tResp.statusCode != 200 &&
          nResp.statusCode != 200 &&
          eResp.statusCode != 200 &&
          aResp.statusCode != 200);

      if (failedAll) {
        _error =
            'All dashboard APIs failed.\n'
            'teacher-dtls: HTTP ${tResp.statusCode}\n'
            'notices: HTTP ${nResp.statusCode}\n'
            'events: HTTP ${eResp.statusCode}\n'
            'announcements: HTTP ${aResp.statusCode}';
      }
    } on TimeoutException {
      _error = 'Timeout: Teacher dashboard APIs did not respond in time.';
    } catch (e) {
      _error = 'Failed to load teacher dashboard: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ===================== SKELETON =====================
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

  // ===================== CARDS =====================
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
              Icon(
                Icons.more_horiz_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
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
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
  List<_PieSlice> _buildCommsSlices() {
    const palette = [
      Color(0xFF2563EB), // notices
      Color(0xFF7C3AED), // events
      Color(0xFF22C55E), // announcements
    ];

    final items = <Map<String, dynamic>>[
      {'label': 'Notices', 'value': _notices, 'color': palette[0]},
      {'label': 'Events', 'value': _events, 'color': palette[1]},
      {'label': 'Announcements', 'value': _announcements, 'color': palette[2]},
    ];

    return items
        .map(
          (m) => _PieSlice(
            label: m['label'] as String,
            value: (m['value'] as int).toDouble(),
            color: m['color'] as Color,
          ),
        )
        .toList();
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
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
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

  // ===================== MENU UI HELPERS =====================
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
            child: const Icon(Icons.person_pin_rounded, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.roleDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
          title: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            'Tap to expand',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  String _teacherName() {
    final name =
        (_teacher['teacher_name'] ??
                _teacher['name'] ??
                _teacher['tname'] ??
                _teacher['username'])
            ?.toString();
    if (name == null || name.trim().isEmpty) return widget.username;
    return name.trim();
  }

  // ===================== MAIN BUILD =====================
  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2563EB);
    final commSlices = _buildCommsSlices();

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
                                colors: [Color(0xFF2563EB), Color(0xFF22C55E)],
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
                                  'Welcome, Teacher',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  _teacherName(),
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
                                : _fetchDashboardSnapshot,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
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
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Teacher Overview',
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
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Loading...',
                                        style: TextStyle(fontSize: 12),
                                      ),
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
                                    color: Colors.red.withOpacity(0.25),
                                  ),
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

                            // Row 1: Subjects + Classes
                            Row(
                              children: [
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.menu_book_rounded,
                                          title: 'Subjects',
                                          value: _subjects.toString(),
                                          subtitle: 'Assigned subjects',
                                          color: const Color(0xFFF97316),
                                          onTap: () => _openFromMenu(
                                            const _PlaceholderPage(
                                              title: 'Subjects',
                                              subtitle:
                                                  'Your assigned subjects will appear here.',
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.meeting_room_rounded,
                                          title: 'Classes',
                                          value: _classes.toString(),
                                          subtitle: 'Assigned classes',
                                          color: const Color(0xFF0EA5E9),
                                          onTap: () => _openFromMenu(
                                            const _PlaceholderPage(
                                              title: 'Classes',
                                              subtitle:
                                                  'Your assigned classes will appear here.',
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Row 2: Notices + Events
                            Row(
                              children: [
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.campaign_rounded,
                                          title: 'Notices',
                                          value: _notices.toString(),
                                          subtitle: 'Latest notices',
                                          color: const Color(0xFF2563EB),
                                          onTap: () => _openFromMenu(
                                            const _PlaceholderPage(
                                              title: 'Notices',
                                              subtitle:
                                                  'Notice list page will open here.',
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.event_rounded,
                                          title: 'Events',
                                          value: _events.toString(),
                                          subtitle: 'Upcoming events',
                                          color: const Color(0xFF7C3AED),
                                          onTap: () => _openFromMenu(
                                            const _PlaceholderPage(
                                              title: 'Events',
                                              subtitle:
                                                  'Event list page will open here.',
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Row 3: Announcements + Attendance (placeholder)
                            Row(
                              children: [
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.announcement_rounded,
                                          title: 'Announcements',
                                          value: _announcements.toString(),
                                          subtitle: 'Latest announcements',
                                          color: const Color(0xFF22C55E),
                                          onTap: () => _openFromMenu(
                                            const _PlaceholderPage(
                                              title: 'Announcements',
                                              subtitle:
                                                  'Announcement list page will open here.',
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading
                                      ? _statSkeleton()
                                      : _buildStatCard(
                                          icon: Icons.fact_check_rounded,
                                          title: 'Attendance',
                                          value: '—',
                                          subtitle: 'Open attendance module',
                                          color: const Color(0xFF6366F1),
                                          onTap: () => _openFromMenu(
                                            const _PlaceholderPage(
                                              title: 'Attendance',
                                              subtitle:
                                                  'Attendance module page will open here.',
                                            ),
                                          ),
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
                                    title: 'Communication Share',
                                    subtitle:
                                        'Notices / Events / Announcements',
                                    slices: commSlices,
                                  ),

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
                                  icon: Icons.campaign_rounded,
                                  label: 'Notices',
                                  color: const Color(0xFF2563EB),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(
                                      title: 'Notices',
                                      subtitle:
                                          'Notice list page will open here.',
                                    ),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.event_rounded,
                                  label: 'Events',
                                  color: const Color(0xFF7C3AED),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(
                                      title: 'Events',
                                      subtitle:
                                          'Event list page will open here.',
                                    ),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.announcement_rounded,
                                  label: 'Announcements',
                                  color: const Color(0xFF22C55E),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(
                                      title: 'Announcements',
                                      subtitle:
                                          'Announcement list page will open here.',
                                    ),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.refresh_rounded,
                                  label: 'Refresh Snapshot',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: _fetchDashboardSnapshot,
                                ),
                                _QuickActionChip(
                                  icon: Icons.logout_rounded,
                                  label: 'Logout',
                                  color: const Color(0xFFEF4444),
                                  onTap: _logout,
                                ),
                              ],
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

            // ================= HAMBURGER SLIDE MENU =================
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
                            const Icon(
                              Icons.dashboard_rounded,
                              size: 22,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Teacher Menu',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
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
                                  icon: Icons.school_rounded,
                                  title: 'Teaching',
                                  color: const Color(0xFFF97316),
                                  initiallyExpanded: true,
                                  children: [
                                    _menuItem(
                                      icon: Icons.menu_book_rounded,
                                      title: 'Subjects',
                                      subtitle: 'assigned subjects',
                                      color: const Color(0xFFF97316),
                                      onTap: () => _openFromMenu(
                                        const _PlaceholderPage(
                                          title: 'Subjects',
                                          subtitle:
                                              'Your assigned subjects will appear here.',
                                        ),
                                      ),
                                    ),
                                    _menuItem(
                                      icon: Icons.meeting_room_rounded,
                                      title: 'Classes',
                                      subtitle: 'assigned classes',
                                      color: const Color(0xFF0EA5E9),
                                      onTap: () => _openFromMenu(
                                        const _PlaceholderPage(
                                          title: 'Classes',
                                          subtitle:
                                              'Your assigned classes will appear here.',
                                        ),
                                      ),
                                    ),
                                    _menuItem(
                                      icon: Icons.fact_check_rounded,
                                      title: 'Attendance',
                                      subtitle: 'mark / view attendance',
                                      color: const Color(0xFF6366F1),
                                      onTap: () => _openFromMenu(
                                        const _PlaceholderPage(
                                          title: 'Attendance',
                                          subtitle:
                                              'Attendance module page will open here.',
                                        ),
                                      ),
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
                                      subtitle: 'latest notices',
                                      color: const Color(0xFF2563EB),
                                      onTap: () => _openFromMenu(
                                        const _PlaceholderPage(
                                          title: 'Notices',
                                          subtitle:
                                              'Notice list page will open here.',
                                        ),
                                      ),
                                    ),
                                    _menuItem(
                                      icon: Icons.event_rounded,
                                      title: 'Events',
                                      subtitle: 'upcoming events',
                                      color: const Color(0xFF7C3AED),
                                      onTap: () => _openFromMenu(
                                        const _PlaceholderPage(
                                          title: 'Events',
                                          subtitle:
                                              'Event list page will open here.',
                                        ),
                                      ),
                                    ),
                                    _menuItem(
                                      icon: Icons.announcement_rounded,
                                      title: 'Announcements',
                                      subtitle: 'latest announcements',
                                      color: const Color(0xFF22C55E),
                                      onTap: () => _openFromMenu(
                                        const _PlaceholderPage(
                                          title: 'Announcements',
                                          subtitle:
                                              'Announcement list page will open here.',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                _menuSection(
                                  icon: Icons.settings_rounded,
                                  title: 'System',
                                  color: const Color(0xFF334155),
                                  children: [
                                    _menuItem(
                                      icon: Icons.refresh_rounded,
                                      title: 'Refresh Snapshot',
                                      subtitle: 'reload dashboard data',
                                      color: const Color(0xFF0EA5E9),
                                      onTap: _fetchDashboardSnapshot,
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
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFFEF4444,
                                        ).withOpacity(0.18),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.logout_rounded,
                                          color: Color(0xFFEF4444),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Logout',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFFEF4444),
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.grey.shade600,
                                        ),
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
      painter: _PiePainter(slices: slices, holeRadiusFactor: holeRadiusFactor),
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

  _PiePainter({required this.slices, required this.holeRadiusFactor});

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

/// ✅ Internal placeholder page so this file compiles without importing other pages
class _PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PlaceholderPage({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

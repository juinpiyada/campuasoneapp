import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart'; // Ensure that the import is correct.

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
  late final AnimationController _controller;
  late final Animation<double> _fadeHeader;
  late final Animation<double> _fadeCards;
  late final Animation<Offset> _slideHeader;
  late final Animation<Offset> _slideCards;

  late final AnimationController _menuController;
  late final Animation<Offset> _menuSlide;
  bool _isMenuOpen = false;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _counts = {};

  int _coursesAssigned = 0;
  int _studentsInCourses = 0;
  int _assignmentsDue = 0;

  @override
  void initState() {
    super.initState();

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

    _slideHeader = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero)
        .animate(_fadeHeader);

    _slideCards = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(_fadeCards);

    _controller.forward();

    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _menuSlide = Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic));

    Future.microtask(() async {
      await _fetchCounts();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _menuController.dispose();
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

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _fetchCounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('YOUR_API_URL/courses-count'); // Use actual API URL
      final headers = await _authHeaders();

      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          _counts = Map<String, dynamic>.from(decoded);
          _coursesAssigned = _counts['courses_assigned'] ?? 0;
          _studentsInCourses = _counts['students_in_courses'] ?? 0;
          _assignmentsDue = _counts['assignments_due'] ?? 0;
        }
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: /courses-count did not respond in time.';
    } catch (e) {
      _error = 'Failed to load dashboard data: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    return headers;
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTap: _isMenuOpen ? _toggleMenu : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                color: _isMenuOpen
                    ? Colors.black.withOpacity(0.5)
                    : Colors.transparent,
              ),
            ),
            SlideTransition(
              position: _menuSlide,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 280,
                  height: double.infinity,
                  color: Colors.white,
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: primaryColor.withOpacity(0.1),
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.roleDescription,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const Divider(height: 32),
                      _buildMenuItem(Icons.dashboard_rounded, 'Dashboard'),
                      _buildMenuItem(Icons.class_rounded, 'My Courses'),
                      _buildMenuItem(Icons.people_rounded, 'Students'),
                      _buildMenuItem(Icons.settings_rounded, 'Settings'),
                      const Spacer(),
                      ListTile(
                        leading: const Icon(
                          Icons.logout_rounded,
                          color: Colors.red,
                        ),
                        title: const Text(
                          'Logout',
                          style: TextStyle(color: Colors.red),
                        ),
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Column(
              children: [
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, Teacher ${widget.username}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _loading ? null : () async {
                              await _fetchCounts();
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

                Expanded(
                  child: SlideTransition(
                    position: _slideCards,
                    child: FadeTransition(
                      opacity: _fadeCards,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Teacher Dashboard',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                if (_loading)
                                  Row(
                                    children: const [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Loading...', style: TextStyle(fontSize: 12)),
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
                                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            // Rows for stats
                            Row(
                              children: [
                                Expanded(
                                  child: _loading ? _statSkeleton() : _buildStatCard(
                                    icon: Icons.class_rounded,
                                    title: 'Courses Assigned',
                                    value: _coursesAssigned.toString(),
                                    subtitle: 'courses_assigned',
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _loading ? _statSkeleton() : _buildStatCard(
                                    icon: Icons.people_alt_rounded,
                                    title: 'Students in Courses',
                                    value: _studentsInCourses.toString(),
                                    subtitle: 'students_in_courses',
                                    color: const Color(0xFF22C55E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _loading ? _statSkeleton() : _buildStatCard(
                                    icon: Icons.assignment_rounded,
                                    title: 'Assignments Due',
                                    value: _assignmentsDue.toString(),
                                    subtitle: 'assignments_due',
                                    color: const Color(0xFFF97316),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade700),
      title: Text(title),
      onTap: () {
        _toggleMenu();
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
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
              Icon(Icons.more_horiz_rounded, color: Colors.grey.shade400, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
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

  Widget _skeletonBox({double? w, double? h, BorderRadius? br}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: br ?? BorderRadius.circular(14),
      ),
    );
  }
}

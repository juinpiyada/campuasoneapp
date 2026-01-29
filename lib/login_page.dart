// ✅ File: lib/login_page.dart
// ✅ Logic UNCHANGED (only UI upgraded)
// ✅ Added Logo (asset + safe fallback)
// ✅ Next-level modern UI (gradient + glass card + better spacing + responsive)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'admin_dashboard.dart';
import 'student_dashboard.dart';
import 'finance_dashboard.dart';
import 'teacher_dashboard.dart';

/// ----------------- ENV + API CONFIG -----------------
class AppConfig {
  static String get baseUrl {
    final v = dotenv.env['BASE_URL'] ?? '';
    if (v.trim().isNotEmpty) return v.trim();
    return 'https://poweranger-turbo.onrender.com';
  }
}

class Api {
  static String get baseUrl => AppConfig.baseUrl;

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  static String get login => _join(baseUrl, '/login');
}

/// Super admin
const String superAdminUser = 'super_user@gmail.com';

/// ---------------- ROLE HELPERS ----------------

String _normToken(String s) => s.trim().toLowerCase().replaceAll('-', '_');

Set<String> _buildRoleSet(Map<String, dynamic> data) {
  final rolesRaw = data['roles'];
  final rolesArr = (rolesRaw is List) ? rolesRaw : const [];

  final all = <dynamic>[
    ...rolesArr,
    data['user_role'],
    data['userroledesc'],
    data['role_description'],
  ].where((e) => e != null).toList();

  final out = <String>{};
  for (final r in all) {
    final text = r.toString();
    final parts = text.split(RegExp(r'[,\s]+'));
    for (final p in parts) {
      final t = _normToken(p);
      if (t.isNotEmpty) out.add(t);
    }
  }
  return out;
}

/// ---------- ROLE DETECTION ----------

bool _isFinance(Set<String> roleSet) =>
    roleSet.contains('fin_act') ||
    roleSet.contains('fin_act_adm') ||
    roleSet.contains('finance') ||
    roleSet.contains('finance_admin');

bool _isStudent(Set<String> roleSet, String roleDescRaw) {
  final roleDesc = roleDescRaw.toUpperCase();
  if (roleDesc.contains('STU-CURR')) return true;

  const keys = <String>{
    'student',
    'stu_curr',
    'stu_onboard',
    'stu_passed',
  };

  for (final k in keys) {
    if (roleSet.contains(k)) return true;
  }
  return false;
}

/// ✅ TEACHER ROLE DETECTION
bool _isTeacher(Set<String> roleSet, String roleDescRaw) {
  final roleDesc = roleDescRaw.toLowerCase();
  if (roleDesc.contains('teacher')) return true;

  const teacherKeys = {
    'teacher',
    'faculty',
    'fac',
    'tch',
    'role_teacher',
  };

  for (final k in teacherKeys) {
    if (roleSet.contains(k)) return true;
  }
  return false;
}

/// ================= LOGIN PAGE =================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  // ✅ Add your logo here
  // Put file at: assets/images/campusone_logo.png
  // and add in pubspec.yaml under assets:
  //   - assets/images/campusone_logo.png
  static const String _logoAsset = 'assets/images/campusone_logo.png';

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.07),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _scale = Tween<double>(begin: 0.98, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();
    _autoLogin();
  }

  @override
  void dispose() {
    _animController.dispose();
    _userController.dispose();
    _passController.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  /// ================= AUTO LOGIN =================
  Future<void> _autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authStr = prefs.getString('auth');
      if (authStr == null) return;

      final auth = jsonDecode(authStr);
      if (auth is! Map) return;

      final authMap = Map<String, dynamic>.from(auth);

      final userId = (authMap['userId'] ?? '').toString();
      final roleDesc = (authMap['role_description'] ?? 'User').toString();
      final roleSet = _buildRoleSet(authMap);

      if (!mounted) return;

      if (userId.toLowerCase() == superAdminUser) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminDashboardScreen(
              username: userId,
              roleDescription: roleDesc,
            ),
          ),
        );
        return;
      }

      if (_isStudent(roleSet, roleDesc)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentDashboardScreen(
              username: userId,
              roleDescription: roleDesc,
            ),
          ),
        );
        return;
      }

      if (_isTeacher(roleSet, roleDesc)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TeacherDashboardScreen(
              username: userId,
              roleDescription: roleDesc,
            ),
          ),
        );
        return;
      }

      if (_isFinance(roleSet)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FinanceDashboardScreen(
              username: userId,
              roleDescription: roleDesc,
            ),
          ),
        );
        return;
      }
    } catch (_) {}
  }

  /// ================= LOGIN =================
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(Api.login),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _userController.text.trim(),
          'password': _passController.text,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        setState(() => _errorMessage = data['error'] ?? 'Login failed');
        return;
      }

      final userId = (data['userid'] ?? data['username'] ?? '').toString();
      final roleDesc =
          (data['role_description'] ?? data['user_role'] ?? 'User').toString();

      final roleSet = _buildRoleSet(data);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'auth',
        jsonEncode({
          ...data,
          'userId': userId,
          'role_description': roleDesc,
          'login_time': DateTime.now().toIso8601String(),
          'isAuthenticated': true,
        }),
      );

      if (!mounted) return;

      Widget target;

      if (userId.toLowerCase() == superAdminUser) {
        target = AdminDashboardScreen(username: userId, roleDescription: roleDesc);
      } else if (_isStudent(roleSet, roleDesc)) {
        target = StudentDashboardScreen(username: userId, roleDescription: roleDesc);
      } else if (_isTeacher(roleSet, roleDesc)) {
        target = TeacherDashboardScreen(username: userId, roleDescription: roleDesc);
      } else if (_isFinance(roleSet)) {
        target = FinanceDashboardScreen(username: userId, roleDescription: roleDesc);
      } else {
        target = AdminDashboardScreen(username: userId, roleDescription: roleDesc);
      }

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => target));
    } catch (e) {
      setState(() => _errorMessage = 'Server error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ================= UI HELPERS =================

  BoxDecoration _glassCardDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.55), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.10),
          blurRadius: 26,
          offset: const Offset(0, 18),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF5F7FF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _logoOrFallback(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFEFF3FF),
        child: Image.asset(
          _logoAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            // Fallback (in case asset missing)
            return Center(
              child: Icon(
                Icons.school_rounded,
                size: size * 0.55,
                color: const Color(0xFF2563EB),
              ),
            );
          },
        ),
      ),
    );
  }

  /// ================= UI =================
  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 900;

    final cardWidth = isWide ? 420.0 : (media.size.width.clamp(320.0, 520.0) - 36);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF6F8FF),
              Color(0xFFEFF3FF),
              Color(0xFFF7F7FB),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardWidth),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                        decoration: _glassCardDecoration(),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header
                              Row(
                                children: [
                                  _logoOrFallback(56),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          "CampusOne",
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          "Sign in to continue",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6B7280),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // Small banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    colors: [
                                      primary.withOpacity(0.12),
                                      const Color(0xFF22C55E).withOpacity(0.08),
                                    ],
                                  ),
                                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(Icons.verified_user_rounded, color: primary),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        "Secure Login • Role-based Dashboard",
                                        style: TextStyle(
                                          fontSize: 12.8,
                                          color: Color(0xFF111827),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              // User ID
                              TextFormField(
                                controller: _userController,
                                focusNode: _userFocus,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) => _passFocus.requestFocus(),
                                decoration: _fieldDecoration(
                                  label: "User ID / Email",
                                  icon: Icons.person_rounded,
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
                              ),

                              const SizedBox(height: 14),

                              // Password
                              TextFormField(
                                controller: _passController,
                                focusNode: _passFocus,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _isLoading ? null : _login(),
                                decoration: _fieldDecoration(
                                  label: "Password",
                                  icon: Icons.lock_rounded,
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword ? "Show password" : "Hide password",
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.black.withOpacity(0.65),
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
                              ),

                              const SizedBox(height: 12),

                              // Error
                              if (_errorMessage != null)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.error_rounded, color: Color(0xFFEF4444)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: Color(0xFFB91C1C),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 14),

                              // Button
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    elevation: 10,
                                    shadowColor: primary.withOpacity(0.35),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          "Sign In",
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Footer note
                              Text(
                                "© ${DateTime.now().year} CampusOne • Powered by Secure API",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.black.withOpacity(0.45),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

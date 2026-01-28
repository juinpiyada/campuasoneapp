// lib/login_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'admin_dashboard.dart';
import 'student_dashboard.dart';
import 'finance_dashboard.dart'; // ✅ ADDED
import 'teacher_dashboard_screen.dart'; // ✅ ADDED

/// ----------------- ENV + API CONFIG -----------------
class AppConfig {
  static String get baseUrl {
    final v = dotenv.env['BASE_URL'] ?? '';
    if (v.trim().isNotEmpty) return v.trim();
    return 'https://poweranger-turbo.onrender.com'; // fallback
  }
}

class Api {
  static String get baseUrl => AppConfig.baseUrl;

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  // ✅ as you requested
  static String get login => _join(baseUrl, '/login');

  static String? get chartData => null;
}

const String superAdminUser = 'super_user@gmail.com';

/// ---------------- small helpers (React-like) ----------------
dynamic pick(List<dynamic> vals) {
  for (final v in vals) {
    if (v != null) return v;
  }
  return null;
}

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

bool _isFinanceByRoles(Set<String> roleSet) =>
    roleSet.contains('fin_act') || roleSet.contains('fin_act_adm');

bool _isFinanceByStrings(Map<String, dynamic> data, Set<String> roleSet) {
  final ur = _normToken((data['user_role'] ?? '').toString());
  return ur == 'finance' || ur == 'finance_admin' || roleSet.contains('finance');
}

bool _isStudentRole(Set<String> roleSet, String roleDescRaw) {
  final roleDesc = roleDescRaw.toUpperCase();
  if (roleDesc.contains('STU-CURR')) return true;

  const keys = <String>{
    'student',
    'stu_curr',
    'stu_onboard',
    'stu_passed',
    'stu_council',
    'student_council',
  };
  for (final k in keys) {
    if (roleSet.contains(k)) return true;
  }
  return false;
}

String _bestRedirectFromResponse(
    http.Response resp, Map<String, dynamic> data, bool isFinance) {
  final jsonUrl = data['redirect_url'];
  final headerUrl = resp.headers['x-redirect-to'];
  if (jsonUrl is String && jsonUrl.trim().isNotEmpty) return jsonUrl.trim();
  if (headerUrl is String && headerUrl.trim().isNotEmpty) return headerUrl.trim();
  return isFinance ? '/finDashbord' : '/dashboard';
}

bool _hasValidSessionPayload(Map<String, dynamic> auth, Map<String, dynamic> sess) {
  final aUID =
      (auth['userId'] ?? auth['userid'] ?? auth['username'] ?? '').toString();
  final sUID =
      (sess['userId'] ?? sess['userid'] ?? sess['username'] ?? '').toString();
  if (aUID.isEmpty || sUID.isEmpty || aUID != sUID) return false;
  if (auth['isAuthenticated'] != true) return false;

  final tsRaw = (auth['login_time'] ?? '').toString();
  if (tsRaw.isEmpty) return true;

  final ts = DateTime.tryParse(tsRaw)?.millisecondsSinceEpoch ?? 0;
  if (ts <= 0) return true;
  final hours = (DateTime.now().millisecondsSinceEpoch - ts) / 36e5;
  return hours < 24;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _cardFade = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward();

    // ✅ Auto-login (session restore)
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final authStr = prefs.getString('auth');
        final sessStr = prefs.getString('sessionUser');
        if (authStr == null || sessStr == null) return;

        final auth = jsonDecode(authStr);
        final sess = jsonDecode(sessStr);
        if (auth is! Map || sess is! Map) return;

        final authMap = Map<String, dynamic>.from(auth);
        final sessMap = Map<String, dynamic>.from(sess);

        if (!_hasValidSessionPayload(authMap, sessMap)) return;

        final userid = (authMap['userId'] ?? '').toString();
        final roleDesc = (authMap['role_description'] ??
                authMap['user_role'] ??
                'User')
            .toString();
        final roleSet = _buildRoleSet(authMap);

        final isFinance =
            _isFinanceByRoles(roleSet) || _isFinanceByStrings(authMap, roleSet);

        if (!mounted) return;

        if (userid.toLowerCase() == superAdminUser) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AdminDashboardScreen(
                username: userid,
                roleDescription: roleDesc,
              ),
            ),
          );
          return;
        }

        if (_isStudentRole(roleSet, roleDesc)) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => StudentDashboardScreen(
                username: userid,
                roleDescription: roleDesc,
              ),
            ),
          );
          return;
        }

        if (isFinance) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => FinanceDashboardScreen(
                username: userid,
                roleDescription: roleDesc,
              ),
            ),
          );
          return;
        }

        // Check if the role is for a teacher
        if (roleSet.contains('teacher')) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TeacherDashboardScreen(
                username: userid,
                roleDescription: roleDesc,
              ),
            ),
          );
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LoginSuccessScreen(
              roleDescription: roleDesc,
              redirectUrl: authMap['redirect_url']?.toString(),
              rawData: authMap,
            ),
          ),
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ✅ uses env-configured URL
      final uri = Uri.parse(Api.login); // POST /login
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _userController.text.trim(),
          'password': _passController.text,
        }),
      );

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (response.statusCode == 200) {
        final message = (data['message'] ?? 'Login successful').toString();

        final normalizedUserId = (pick([
              data['userid'],
              data['userId'],
              data['user_id'],
              data['username'],
            ]) ??
            '').toString();

        final roleDesc =
            (pick([data['role_description'], data['user_role'], 'User']) ??
                    'User')
                .toString();

        final roleSet = _buildRoleSet(data);

        final isFinance =
            _isFinanceByRoles(roleSet) || _isFinanceByStrings(data, roleSet);
        final isStudent = _isStudentRole(roleSet, roleDesc);

        final teacherId = pick([
          data['teacher_id'],
          data['teacherid'],
          data['teacherId'],
          (data['teacher'] is Map)
              ? (data['teacher']['teacherid'] ?? data['teacher']['id'])
              : null,
        ]);

        final teacherUserid = pick([
          data['teacher_userid'],
          data['teacherUserid'],
          data['teacherUserId'],
          (data['teacher'] is Map)
              ? (data['teacher']['userid'] ?? data['teacher']['user_id'])
              : null,
        ]);

        final stuUserId = pick([
          data['stuuserid'],
          data['student_userid'],
          data['studentUserId'],
        ]);

        final studentSemester = pick([
          data['student_semester'],
          data['stu_curr_semester'],
          data['semester'],
        ]);

        final studentSection = pick([
          data['student_section'],
          data['stu_section'],
          data['section'],
        ]);

        final primaryRoleRaw = (pick([
              data['user_role'],
              data['userroledesc'],
              data['role_description']
            ]) ??
            '')
            .toString();
        final primaryRole = _normToken(primaryRoleRaw);

        final isGroupAdmin = primaryRole == 'grp_adm' || roleSet.contains('grp_adm');
        final isGroupMgmtUser =
            primaryRole == 'grp_mgmt_usr' || roleSet.contains('grp_mgmt_usr');
        final isHr =
            roleSet.contains('hr_leave') || roleSet.contains('role_hr') || roleSet.contains('hr');

        final groupMode = isGroupAdmin
            ? 'group_of_institute'
            : (isGroupMgmtUser ? 'college_under_group' : 'single_college');
        final childUserRole = isGroupAdmin ? 'grp_mgmt_usr' : null;

        final hideCharts = isStudent;
        final redirectUrl = _bestRedirectFromResponse(response, data, isFinance);

        final authPayload = <String, dynamic>{
          'userId': normalizedUserId,
          'userid': normalizedUserId,
          'name': (data['username'] ?? '').toString(),
          'user_role': (data['user_role'] ?? '').toString(),
          'role_description': (data['role_description'] ?? '').toString(),
          'roles': (data['roles'] is List) ? data['roles'] : [],
          'stuuserid': stuUserId,
          'student_semester': studentSemester,
          'student_section': studentSection,
          'teacher_userid': teacherUserid?.toString(),
          'teacher_id': teacherId?.toString(),
          'login_time': DateTime.now().toIso8601String(),
          'hide_charts': hideCharts,
          'isAuthenticated': true,
          'redirect_url': redirectUrl,
          'is_group_admin': isGroupAdmin,
          'is_hr': isHr,
          'group_mode': groupMode,
          'child_user_role': childUserRole,
        };

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth', jsonEncode(authPayload));
        await prefs.setString('sessionUser', jsonEncode(authPayload));
        await prefs.setString('dashboard_hide_charts', hideCharts ? 'true' : 'false');
        await prefs.setString('group_mode', groupMode);
        await prefs.setString('is_group_admin', isGroupAdmin ? 'true' : 'false');
        await prefs.setString('child_user_role', childUserRole ?? '');

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message ($roleDesc)'),
            behavior: SnackBarBehavior.floating,
          ),
        );

        Widget targetScreen;

        if (normalizedUserId.toLowerCase() == superAdminUser) {
          targetScreen = AdminDashboardScreen(
            username: normalizedUserId,
            roleDescription: roleDesc,
          );
        } else if (isStudent) {
          targetScreen = StudentDashboardScreen(
            username: normalizedUserId,
            roleDescription: roleDesc,
          );
        } else if (isFinance) {
          targetScreen = FinanceDashboardScreen(
            username: normalizedUserId,
            roleDescription: roleDesc,
          );
        } else if (roleSet.contains('teacher')) {
          targetScreen = TeacherDashboardScreen(
            username: normalizedUserId,
            roleDescription: roleDesc,
          );
        } else {
          targetScreen = LoginSuccessScreen(
            roleDescription: roleDesc,
            redirectUrl: redirectUrl,
            rawData: authPayload,
          );
        }

        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => targetScreen,
            transitionsBuilder: (_, animation, __, child) {
              final curved =
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        );
      } else {
        final error = (data['error'] ?? 'Login failed').toString();
        setState(() => _errorMessage = error);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not connect to server. ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    const Color primary = Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withOpacity(0.18),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'lib/img/logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CampusOne',
                    style: TextStyle(
                      color: Colors.grey.shade900,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Secure Admin & Student Portal',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SlideTransition(
                position: _cardSlide,
                child: FadeTransition(
                  opacity: _cardFade,
                  child: Container(
                    width: size.width > 520 ? 440 : double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sign in',
                            style: TextStyle(
                              color: Colors.grey.shade900,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Use your CampusOne user ID and password.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'User ID',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _userController,
                            style: const TextStyle(color: Colors.black87),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'e.g. super_user@gmail.com',
                              prefixIcon: const Icon(Icons.person_rounded),
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
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
                                borderSide: const BorderSide(color: primary, width: 1.4),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'User ID is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Password',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _passController,
                            style: const TextStyle(color: Colors.black87),
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
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
                                borderSide: const BorderSide(color: primary, width: 1.4),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          if (_errorMessage != null) ...[
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                elevation: 6,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Sign in',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Powered by CampusOne',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

// For non-super users (debug-style dashboard)
class LoginSuccessScreen extends StatelessWidget {
  final String roleDescription;
  final String? redirectUrl;
  final Map<String, dynamic> rawData;

  const LoginSuccessScreen({
    super.key,
    required this.roleDescription,
    required this.redirectUrl,
    required this.rawData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        title: const Text('Dashboard'),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Logged in as:',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                roleDescription,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (redirectUrl != null)
                Text(
                  'Backend redirect_url: $redirectUrl',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Raw response/auth payload:',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(rawData),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
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

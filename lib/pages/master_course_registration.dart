// lib/pages/master_course_registration.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterCourseRegistrationPage extends StatefulWidget {
  const MasterCourseRegistrationPage({super.key});

  @override
  State<MasterCourseRegistrationPage> createState() => _MasterCourseRegistrationPageState();
}

class _MasterCourseRegistrationPageState extends State<MasterCourseRegistrationPage>
    with TickerProviderStateMixin {
  // ------------------ State ------------------
  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  // Modal/form state
  bool _saving = false;
  String? _modalError;
  String? _editingId;

  // Form controllers (match API payload keys exactly)
  final _courseRegisIdCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _offeringIdCtrl = TextEditingController();
  final _courseTermCtrl = TextEditingController();
  final _courseIsTermCtrl = TextEditingController();
  final _elecGroupCtrl = TextEditingController();
  final _enrollDtCtrl = TextEditingController(); // keep as string (API inserts as provided)
  final _finalGradeCtrl = TextEditingController();
  final _resultStatusCtrl = TextEditingController();
  final _attPerCtrl = TextEditingController();
  final _statusCtrl = TextEditingController(text: 'ACTIVE');

  // Animations
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  // ------------------ Config ------------------
  String get _base => ApiEndpoints.courseRegistration; // ✅ as you requested

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _shimmer = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);
    _shimmerCtrl.repeat(reverse: true);

    _searchCtrl.addListener(_applySearch);

    Future.microtask(() async {
      await _fetchAll();
      _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();

    _courseRegisIdCtrl.dispose();
    _studentIdCtrl.dispose();
    _offeringIdCtrl.dispose();
    _courseTermCtrl.dispose();
    _courseIsTermCtrl.dispose();
    _elecGroupCtrl.dispose();
    _enrollDtCtrl.dispose();
    _finalGradeCtrl.dispose();
    _resultStatusCtrl.dispose();
    _attPerCtrl.dispose();
    _statusCtrl.dispose();

    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ------------------ Utils ------------------
  String _s(dynamic v) => (v ?? '').toString();

  double? _toDoubleOrNull(String v) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
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

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    return headers;
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
    _searchFocus.unfocus();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ------------------ Search ------------------
  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((r) {
        final hay = [
          _s(r['course_regis_id']),
          _s(r['course_studentid']),
          _s(r['courseofferingid']),
          _s(r['courseterm']),
          _s(r['courseisterm']),
          _s(r['course_elec_groupid']),
          _s(r['courseenrollmentdt']),
          _s(r['coursefinalgrade']),
          _s(r['courseresultstatus']),
          _s(r['courseattper']),
          _s(r['coursestatus']),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    });
  }

  // ------------------ API: List ------------------
  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(_base); // GET /
      final headers = await _authHeaders();

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        // expected: { data: [...] }
        if (decoded is Map && decoded['data'] is List) {
          _all = (decoded['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else {
          _all = [];
        }
        _filtered = List<Map<String, dynamic>>.from(_all);
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: course registrations list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load course registrations: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ------------------ API: Create ------------------
  Future<void> _createRegistration() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final id = _courseRegisIdCtrl.text.trim();
      final student = _studentIdCtrl.text.trim();
      final offering = _offeringIdCtrl.text.trim();

      if (id.isEmpty || student.isEmpty || offering.isEmpty) {
        throw Exception('Required: course_regis_id, course_studentid, courseofferingid');
      }

      final body = {
        "course_regis_id": id,
        "course_studentid": student,
        "courseofferingid": offering,
        "courseterm": _courseTermCtrl.text.trim().isEmpty ? null : _courseTermCtrl.text.trim(),
        "courseisterm": _courseIsTermCtrl.text.trim().isEmpty ? null : _courseIsTermCtrl.text.trim(),
        "course_elec_groupid": _elecGroupCtrl.text.trim().isEmpty ? null : _elecGroupCtrl.text.trim(),
        "courseenrollmentdt": _enrollDtCtrl.text.trim().isEmpty ? null : _enrollDtCtrl.text.trim(),
        "coursefinalgrade": _finalGradeCtrl.text.trim().isEmpty ? null : _finalGradeCtrl.text.trim(),
        "courseresultstatus": _resultStatusCtrl.text.trim().isEmpty ? null : _resultStatusCtrl.text.trim(),
        "courseattper": _attPerCtrl.text.trim().isEmpty ? null : _toDoubleOrNull(_attPerCtrl.text),
        "coursestatus": _statusCtrl.text.trim().isEmpty ? "ACTIVE" : _statusCtrl.text.trim(),
      };

      final uri = Uri.parse(_base);
      final headers = await _authHeaders();

      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        await _fetchAll();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _modalError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _modalError = 'Timeout: create registration did not respond in time.';
    } catch (e) {
      _modalError = 'Create failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Update ------------------
  Future<void> _updateRegistration(String id) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final body = {
        "course_studentid": _studentIdCtrl.text.trim(),
        "courseofferingid": _offeringIdCtrl.text.trim(),
        "courseterm": _courseTermCtrl.text.trim().isEmpty ? null : _courseTermCtrl.text.trim(),
        "courseisterm": _courseIsTermCtrl.text.trim().isEmpty ? null : _courseIsTermCtrl.text.trim(),
        "course_elec_groupid": _elecGroupCtrl.text.trim().isEmpty ? null : _elecGroupCtrl.text.trim(),
        "courseenrollmentdt": _enrollDtCtrl.text.trim().isEmpty ? null : _enrollDtCtrl.text.trim(),
        "coursefinalgrade": _finalGradeCtrl.text.trim().isEmpty ? null : _finalGradeCtrl.text.trim(),
        "courseresultstatus": _resultStatusCtrl.text.trim().isEmpty ? null : _resultStatusCtrl.text.trim(),
        "courseattper": _attPerCtrl.text.trim().isEmpty ? null : _toDoubleOrNull(_attPerCtrl.text),
        "coursestatus": _statusCtrl.text.trim().isEmpty ? "ACTIVE" : _statusCtrl.text.trim(),
      };

      final uri = Uri.parse('$_base/$id');
      final headers = await _authHeaders();

      final resp = await http
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        await _fetchAll();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _modalError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _modalError = 'Timeout: update registration did not respond in time.';
    } catch (e) {
      _modalError = 'Update failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Delete ------------------
  Future<void> _deleteRegistration(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Course Registration?',
        message: 'This will permanently delete: $id',
        confirmText: 'Delete',
        confirmColor: const Color(0xFFEF4444),
      ),
    );

    if (ok != true) return;

    try {
      final uri = Uri.parse('$_base/$id');
      final headers = await _authHeaders();

      final resp = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        await _fetchAll();
      } else {
        _toast('Delete failed: HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      _toast('Timeout while deleting.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  // ------------------ Modal open helpers ------------------
  void _resetForm() {
    _modalError = null;
    _courseRegisIdCtrl.clear();
    _studentIdCtrl.clear();
    _offeringIdCtrl.clear();
    _courseTermCtrl.clear();
    _courseIsTermCtrl.clear();
    _elecGroupCtrl.clear();
    _enrollDtCtrl.clear();
    _finalGradeCtrl.clear();
    _resultStatusCtrl.clear();
    _attPerCtrl.clear();
    _statusCtrl.text = 'ACTIVE';
  }

  void _prefillForEdit(Map<String, dynamic> r) {
    _modalError = null;
    _courseRegisIdCtrl.text = _s(r['course_regis_id']);
    _studentIdCtrl.text = _s(r['course_studentid']);
    _offeringIdCtrl.text = _s(r['courseofferingid']);
    _courseTermCtrl.text = _s(r['courseterm']);
    _courseIsTermCtrl.text = _s(r['courseisterm']);
    _elecGroupCtrl.text = _s(r['course_elec_groupid']);
    _enrollDtCtrl.text = _s(r['courseenrollmentdt']);
    _finalGradeCtrl.text = _s(r['coursefinalgrade']);
    _resultStatusCtrl.text = _s(r['courseresultstatus']);
    _attPerCtrl.text = _s(r['courseattper']);
    _statusCtrl.text = _s(r['coursestatus']).isEmpty ? 'ACTIVE' : _s(r['coursestatus']);
  }

  Future<void> _openAddModal() async {
    setState(() {
      _editingId = null;
      _resetForm();
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RegistrationModal(
        title: 'Add Course Registration',
        subtitle: 'Create registration entry',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,

        courseRegisIdController: _courseRegisIdCtrl,
        studentIdController: _studentIdCtrl,
        offeringIdController: _offeringIdCtrl,
        courseTermController: _courseTermCtrl,
        courseIsTermController: _courseIsTermCtrl,
        elecGroupController: _elecGroupCtrl,
        enrollDtController: _enrollDtCtrl,
        finalGradeController: _finalGradeCtrl,
        resultStatusController: _resultStatusCtrl,
        attPerController: _attPerCtrl,
        statusController: _statusCtrl,

        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _createRegistration();
          if (mounted) setState(() {});
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _modalError = null;
    });
  }

  Future<void> _openEditModal(Map<String, dynamic> row) async {
    setState(() {
      _editingId = _s(row['course_regis_id']);
      _prefillForEdit(row);
    });

    final id = _editingId!;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RegistrationModal(
        title: 'Edit Course Registration',
        subtitle: 'Update: $id',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,

        courseRegisIdController: _courseRegisIdCtrl,
        studentIdController: _studentIdCtrl,
        offeringIdController: _offeringIdCtrl,
        courseTermController: _courseTermCtrl,
        courseIsTermController: _courseIsTermCtrl,
        elecGroupController: _elecGroupCtrl,
        enrollDtController: _enrollDtCtrl,
        finalGradeController: _finalGradeCtrl,
        resultStatusController: _resultStatusCtrl,
        attPerController: _attPerCtrl,
        statusController: _statusCtrl,

        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _updateRegistration(id);
          if (mounted) setState(() {});
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _modalError = null;
    });
  }

  // ------------------ UI helpers ------------------
  Widget _pill({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _skeletonRow() {
    return FadeTransition(
      opacity: _shimmer,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 10, width: 190, color: Colors.white.withOpacity(0.6)),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 140, color: Colors.white.withOpacity(0.6)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 22,
              width: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ Build ------------------
  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF7F7FB);
    const primary = Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            children: [
              // ---------- Top Bar ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            size: 20, color: Colors.grey.shade900),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Course Registration',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'White theme • Tailwind style',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loading ? null : _fetchAll,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 2),
                    ElevatedButton.icon(
                      onPressed: _openAddModal,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ---------- Search Bar ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: Colors.grey.shade600),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          decoration: const InputDecoration(
                            hintText:
                                'Search by reg id, student id, offering id, term, grade, status...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchCtrl.text.trim().isNotEmpty)
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () {
                            _searchCtrl.clear();
                            _dismissKeyboard();
                            _applySearch();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Icon(Icons.close_rounded,
                                size: 18, color: Colors.grey.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ---------- Body ----------
              Expanded(
                child: _loading
                    ? ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        itemCount: 8,
                        itemBuilder: (_, __) => _skeletonRow(),
                      )
                    : (_error != null)
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red.withOpacity(0.25)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Error',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _fetchAll,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Retry'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchAll,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                              children: [
                                Row(
                                  children: [
                                    _pill(
                                      icon: Icons.list_alt_rounded,
                                      label: 'Total: ${_filtered.length}',
                                      color: const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 10),
                                    _pill(
                                      icon: Icons.how_to_reg_rounded,
                                      label: 'API: course-registration',
                                      color: const Color(0xFF7C3AED),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                if (_filtered.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.inbox_rounded,
                                            size: 34, color: Colors.grey.shade500),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No registrations found',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Clear search or add a new registration.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                ..._filtered.map((r) => _RegistrationCard(
                                      row: r,
                                      onEdit: () => _openEditModal(r),
                                      onDelete: () => _deleteRegistration(_s(r['course_regis_id'])),
                                    )),
                              ],
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

class _RegistrationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RegistrationCard({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  Color _statusColor(String status) {
    final s = status.toUpperCase();
    if (s == 'ACTIVE') return const Color(0xFF22C55E);
    if (s == 'INACTIVE') return const Color(0xFFEF4444);
    if (s == 'COMPLETED') return const Color(0xFF0EA5E9);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    final id = _s(row['course_regis_id']);
    final student = _s(row['course_studentid']);
    final offering = _s(row['courseofferingid']);
    final term = _s(row['courseterm']);
    final isTerm = _s(row['courseisterm']);
    final elecGroup = _s(row['course_elec_groupid']);
    final enroll = _s(row['courseenrollmentdt']);
    final grade = _s(row['coursefinalgrade']);
    final result = _s(row['courseresultstatus']);
    final att = _s(row['courseattper']);
    final status = _s(row['coursestatus']).isEmpty ? 'ACTIVE' : _s(row['coursestatus']);

    final sc = _statusColor(status);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.how_to_reg_rounded, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reg: $id',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Student: ${student.isEmpty ? '-' : student} • Offering: ${offering.isEmpty ? '-' : offering}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.18)),
                  ),
                  child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF7C3AED)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.18)),
                  ),
                  child: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFEF4444)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(Icons.account_circle_rounded, 'Student: ${student.isEmpty ? '-' : student}', const Color(0xFF2563EB)),
              _tag(Icons.class_rounded, 'Offering: ${offering.isEmpty ? '-' : offering}', const Color(0xFF7C3AED)),
              if (term.isNotEmpty) _tag(Icons.date_range_rounded, 'Term: $term', const Color(0xFF0EA5E9)),
              if (isTerm.isNotEmpty) _tag(Icons.check_circle_rounded, 'IsTerm: $isTerm', const Color(0xFF16A34A)),
              if (elecGroup.isNotEmpty) _tag(Icons.group_work_rounded, 'Group: $elecGroup', const Color(0xFF64748B)),
              if (enroll.isNotEmpty) _tag(Icons.event_available_rounded, 'Enroll: $enroll', const Color(0xFFF97316)),
              if (grade.isNotEmpty) _tag(Icons.grade_rounded, 'Grade: $grade', const Color(0xFF6366F1)),
              if (result.isNotEmpty) _tag(Icons.fact_check_rounded, 'Result: $result', const Color(0xFF334155)),
              if (att.isNotEmpty) _tag(Icons.percent_rounded, 'Att: $att', const Color(0xFF0EA5E9)),
              _tag(Icons.verified_rounded, status, sc),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

class _RegistrationModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final TextEditingController courseRegisIdController;
  final TextEditingController studentIdController;
  final TextEditingController offeringIdController;
  final TextEditingController courseTermController;
  final TextEditingController courseIsTermController;
  final TextEditingController elecGroupController;
  final TextEditingController enrollDtController;
  final TextEditingController finalGradeController;
  final TextEditingController resultStatusController;
  final TextEditingController attPerController;
  final TextEditingController statusController;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _RegistrationModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,

    required this.courseRegisIdController,
    required this.studentIdController,
    required this.offeringIdController,
    required this.courseTermController,
    required this.courseIsTermController,
    required this.elecGroupController,
    required this.enrollDtController,
    required this.finalGradeController,
    required this.resultStatusController,
    required this.attPerController,
    required this.statusController,

    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.how_to_reg_rounded, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              if (errorText != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(
                    errorText!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // IDs row
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.fingerprint_rounded,
                      label: 'Registration ID',
                      hint: 'course_regis_id (required)',
                      controller: courseRegisIdController,
                      enabled: !isEditing,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.verified_rounded,
                      label: 'Status',
                      hint: 'coursestatus (ACTIVE/INACTIVE)',
                      controller: statusController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.account_circle_rounded,
                      label: 'Student ID',
                      hint: 'course_studentid (required)',
                      controller: studentIdController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.class_rounded,
                      label: 'Offering ID',
                      hint: 'courseofferingid (required)',
                      controller: offeringIdController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.date_range_rounded,
                      label: 'Course Term',
                      hint: 'courseterm',
                      controller: courseTermController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.check_circle_rounded,
                      label: 'Course IsTerm',
                      hint: 'courseisterm',
                      controller: courseIsTermController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.group_work_rounded,
                      label: 'Elective Group ID',
                      hint: 'course_elec_groupid',
                      controller: elecGroupController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.event_available_rounded,
                      label: 'Enrollment Date',
                      hint: 'courseenrollmentdt (YYYY-MM-DD)',
                      controller: enrollDtController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.grade_rounded,
                      label: 'Final Grade',
                      hint: 'coursefinalgrade',
                      controller: finalGradeController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.fact_check_rounded,
                      label: 'Result Status',
                      hint: 'courseresultstatus',
                      controller: resultStatusController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.percent_rounded,
                label: 'Attendance %',
                hint: 'courseattper (number)',
                controller: attPerController,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : onCancel,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade800,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : () async => await onSave(),
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(isEditing ? 'Update' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
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

  Widget _input({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    bool enabled = true,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: Colors.grey.shade800),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(confirmText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

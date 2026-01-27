// lib/pages/master_employee_attendance.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterEmployeeAttendancePage extends StatefulWidget {
  const MasterEmployeeAttendancePage({super.key});

  @override
  State<MasterEmployeeAttendancePage> createState() =>
      _MasterEmployeeAttendancePageState();
}

class _MasterEmployeeAttendancePageState extends State<MasterEmployeeAttendancePage>
    with TickerProviderStateMixin {
  // ---------- List state ----------
  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  // ---------- Modal/form state ----------
  bool _saving = false;
  String? _modalError;
  String? _editingId;

  // ---------- Controllers (match API payload keys) ----------
  final _attidCtrl = TextEditingController();
  final _attuseridCtrl = TextEditingController();
  final _attcourseidCtrl = TextEditingController();
  final _attsubjectidCtrl = TextEditingController();
  final _attlatCtrl = TextEditingController();
  final _attlongCtrl = TextEditingController();
  final _atttsInCtrl = TextEditingController(); // string datetime
  final _atttsOutCtrl = TextEditingController(); // string datetime
  bool _attvalid = true;
  final _attvaliddescCtrl = TextEditingController();
  final _attclassidCtrl = TextEditingController();
  final _attdeviceidCtrl = TextEditingController();
  bool _attmaarkedbyemployee = false;

  // ---------- Animations ----------
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  // ---------- Endpoint ----------
  String get _base => ApiEndpoints.employeeAttendance; // ✅ as you requested

  @override
  void initState() {
    super.initState();

    _fadeCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _shimmerCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
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

    _attidCtrl.dispose();
    _attuseridCtrl.dispose();
    _attcourseidCtrl.dispose();
    _attsubjectidCtrl.dispose();
    _attlatCtrl.dispose();
    _attlongCtrl.dispose();
    _atttsInCtrl.dispose();
    _atttsOutCtrl.dispose();
    _attvaliddescCtrl.dispose();
    _attclassidCtrl.dispose();
    _attdeviceidCtrl.dispose();

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

  bool? _toBoolOrNull(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
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
          _s(r['attid']),
          _s(r['attuserid']),
          _s(r['attcourseid']),
          _s(r['attsubjectid']),
          _s(r['attclassid']),
          _s(r['attdeviceid']),
          _s(r['attvaliddesc']),
          _s(r['attts_in']),
          _s(r['attts_out']),
          _s(r['attlat']),
          _s(r['attlong']),
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
        if (decoded is List) {
          _all = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          _all = [];
        }
        _filtered = List<Map<String, dynamic>>.from(_all);
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: employee attendance list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load employee attendance: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ------------------ API: Create ------------------
  Future<void> _create() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final attid = _attidCtrl.text.trim();
      final attuserid = _attuseridCtrl.text.trim();

      if (attid.isEmpty || attuserid.isEmpty) {
        throw Exception('Required: attid, attuserid');
      }

      final body = <String, dynamic>{
        "attid": attid,
        "attuserid": attuserid,
        "attcourseid": _attcourseidCtrl.text.trim().isEmpty ? null : _attcourseidCtrl.text.trim(),
        "attsubjectid": _attsubjectidCtrl.text.trim().isEmpty ? null : _attsubjectidCtrl.text.trim(),
        "attlat": _attlatCtrl.text.trim().isEmpty ? null : _toDoubleOrNull(_attlatCtrl.text),
        "attlong": _attlongCtrl.text.trim().isEmpty ? null : _toDoubleOrNull(_attlongCtrl.text),
        "attts_in": _atttsInCtrl.text.trim().isEmpty ? null : _atttsInCtrl.text.trim(),
        "attts_out": _atttsOutCtrl.text.trim().isEmpty ? null : _atttsOutCtrl.text.trim(),
        "attvalid": _attvalid,
        "attvaliddesc": _attvaliddescCtrl.text.trim().isEmpty ? null : _attvaliddescCtrl.text.trim(),
        "attclassid": _attclassidCtrl.text.trim().isEmpty ? null : _attclassidCtrl.text.trim(),
        "attdeviceid": _attdeviceidCtrl.text.trim().isEmpty ? null : _attdeviceidCtrl.text.trim(),
        "attmaarkedbyemployee": _attmaarkedbyemployee,
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
      _modalError = 'Timeout: create employee attendance did not respond in time.';
    } catch (e) {
      _modalError = 'Create failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Update ------------------
  Future<void> _update(String attid) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final attuserid = _attuseridCtrl.text.trim();
      if (attuserid.isEmpty) {
        throw Exception('Required: attuserid');
      }

      final body = <String, dynamic>{
        "attuserid": attuserid,
        "attcourseid": _attcourseidCtrl.text.trim().isEmpty ? null : _attcourseidCtrl.text.trim(),
        "attsubjectid": _attsubjectidCtrl.text.trim().isEmpty ? null : _attsubjectidCtrl.text.trim(),
        "attlat": _attlatCtrl.text.trim().isEmpty ? null : _toDoubleOrNull(_attlatCtrl.text),
        "attlong": _attlongCtrl.text.trim().isEmpty ? null : _toDoubleOrNull(_attlongCtrl.text),
        "attts_in": _atttsInCtrl.text.trim().isEmpty ? null : _atttsInCtrl.text.trim(),
        "attts_out": _atttsOutCtrl.text.trim().isEmpty ? null : _atttsOutCtrl.text.trim(),
        "attvalid": _attvalid,
        "attvaliddesc": _attvaliddescCtrl.text.trim().isEmpty ? null : _attvaliddescCtrl.text.trim(),
        "attclassid": _attclassidCtrl.text.trim().isEmpty ? null : _attclassidCtrl.text.trim(),
        "attdeviceid": _attdeviceidCtrl.text.trim().isEmpty ? null : _attdeviceidCtrl.text.trim(),
        "attmaarkedbyemployee": _attmaarkedbyemployee,
      };

      final uri = Uri.parse('$_base/$attid');
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
      _modalError = 'Timeout: update employee attendance did not respond in time.';
    } catch (e) {
      _modalError = 'Update failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Delete ------------------
  Future<void> _delete(String attid) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Attendance?',
        message: 'This will permanently delete record AttID: $attid',
        confirmText: 'Delete',
        confirmColor: const Color(0xFFEF4444),
      ),
    );

    if (ok != true) return;

    try {
      final uri = Uri.parse('$_base/$attid');
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

  // ------------------ Modal helpers ------------------
  void _resetForm() {
    _modalError = null;
    _editingId = null;

    _attidCtrl.clear();
    _attuseridCtrl.clear();
    _attcourseidCtrl.clear();
    _attsubjectidCtrl.clear();
    _attlatCtrl.clear();
    _attlongCtrl.clear();
    _atttsInCtrl.clear();
    _atttsOutCtrl.clear();
    _attvaliddescCtrl.clear();
    _attclassidCtrl.clear();
    _attdeviceidCtrl.clear();

    _attvalid = true;
    _attmaarkedbyemployee = false;
  }

  void _prefillForEdit(Map<String, dynamic> r) {
    _modalError = null;
    _editingId = _s(r['attid']);

    _attidCtrl.text = _s(r['attid']);
    _attuseridCtrl.text = _s(r['attuserid']);
    _attcourseidCtrl.text = _s(r['attcourseid']);
    _attsubjectidCtrl.text = _s(r['attsubjectid']);
    _attlatCtrl.text = _s(r['attlat']);
    _attlongCtrl.text = _s(r['attlong']);
    _atttsInCtrl.text = _s(r['attts_in']);
    _atttsOutCtrl.text = _s(r['attts_out']);
    _attvalid = _toBoolOrNull(r['attvalid']) ?? true;
    _attvaliddescCtrl.text = _s(r['attvaliddesc']);
    _attclassidCtrl.text = _s(r['attclassid']);
    _attdeviceidCtrl.text = _s(r['attdeviceid']);
    _attmaarkedbyemployee = _toBoolOrNull(r['attmaarkedbyemployee']) ?? false;
  }

  Future<void> _openAddModal() async {
    setState(() {
      _resetForm();
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AttendanceModal(
        title: 'Add Employee Attendance',
        subtitle: 'Create a new attendance record',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,
        attidController: _attidCtrl,
        attuseridController: _attuseridCtrl,
        attcourseidController: _attcourseidCtrl,
        attsubjectidController: _attsubjectidCtrl,
        attlatController: _attlatCtrl,
        attlongController: _attlongCtrl,
        atttsInController: _atttsInCtrl,
        atttsOutController: _atttsOutCtrl,
        attvalid: _attvalid,
        onToggleValid: (v) => setState(() => _attvalid = v),
        attvaliddescController: _attvaliddescCtrl,
        attclassidController: _attclassidCtrl,
        attdeviceidController: _attdeviceidCtrl,
        attmaarkedbyemployee: _attmaarkedbyemployee,
        onToggleMarkedByEmp: (v) => setState(() => _attmaarkedbyemployee = v),
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _create();
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
      _prefillForEdit(row);
    });

    final id = _editingId!;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AttendanceModal(
        title: 'Edit Attendance',
        subtitle: 'AttID: $id',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,
        attidController: _attidCtrl,
        attuseridController: _attuseridCtrl,
        attcourseidController: _attcourseidCtrl,
        attsubjectidController: _attsubjectidCtrl,
        attlatController: _attlatCtrl,
        attlongController: _attlongCtrl,
        atttsInController: _atttsInCtrl,
        atttsOutController: _atttsOutCtrl,
        attvalid: _attvalid,
        onToggleValid: (v) => setState(() => _attvalid = v),
        attvaliddescController: _attvaliddescCtrl,
        attclassidController: _attclassidCtrl,
        attdeviceidController: _attdeviceidCtrl,
        attmaarkedbyemployee: _attmaarkedbyemployee,
        onToggleMarkedByEmp: (v) => setState(() => _attmaarkedbyemployee = v),
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _update(id);
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
  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
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
                  Container(height: 10, width: 220, color: Colors.white.withOpacity(0.6)),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 140, color: Colors.white.withOpacity(0.6)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 22,
              width: 70,
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
                            'Employee Attendance',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
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
                                'Search attid, user, course, subject, class, device, time...',
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
                                      icon: Icons.verified_user_rounded,
                                      label: 'API: employee-attendance',
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
                                          'No attendance records found',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Clear search or add a new record.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ..._filtered.map(
                                  (r) => _AttendanceCard(
                                    row: r,
                                    onEdit: () => _openEditModal(r),
                                    onDelete: () => _delete(_s(r['attid'])),
                                  ),
                                ),
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

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AttendanceCard({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  Color _accentFromValid(dynamic valid) {
    final b = (valid is bool) ? valid : (valid?.toString().toLowerCase() == 'true');
    return b ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final attid = _s(row['attid']);
    final user = _s(row['attuserid']);
    final course = _s(row['attcourseid']);
    final subject = _s(row['attsubjectid']);
    final classId = _s(row['attclassid']);
    final device = _s(row['attdeviceid']);
    final inTs = _s(row['attts_in']);
    final outTs = _s(row['attts_out']);
    final valid = row['attvalid'];
    final validDesc = _s(row['attvaliddesc']);
    final lat = _s(row['attlat']);
    final lng = _s(row['attlong']);

    final accent = _accentFromValid(valid);

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
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.fingerprint_rounded, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AttID: $attid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'User: ${user.isEmpty ? '-' : user}',
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
              _tag(Icons.school_rounded, 'Course: ${course.isEmpty ? '-' : course}',
                  const Color(0xFF2563EB)),
              _tag(Icons.menu_book_rounded, 'Subject: ${subject.isEmpty ? '-' : subject}',
                  const Color(0xFF0EA5E9)),
              _tag(Icons.meeting_room_rounded, 'Class: ${classId.isEmpty ? '-' : classId}',
                  const Color(0xFF7C3AED)),
              _tag(Icons.devices_rounded, 'Device: ${device.isEmpty ? '-' : device}',
                  const Color(0xFF334155)),
              if (inTs.isNotEmpty)
                _tag(Icons.login_rounded, 'IN: $inTs', const Color(0xFF22C55E)),
              if (outTs.isNotEmpty)
                _tag(Icons.logout_rounded, 'OUT: $outTs', const Color(0xFFF97316)),
              _tag(
                (valid is bool ? valid : valid?.toString().toLowerCase() == 'true')
                    ? Icons.verified_rounded
                    : Icons.cancel_rounded,
                'Valid: ${_s(valid).isEmpty ? '-' : _s(valid)}',
                accent,
              ),
              if (validDesc.isNotEmpty)
                _tag(Icons.info_rounded, validDesc, const Color(0xFF64748B)),
              if (lat.isNotEmpty || lng.isNotEmpty)
                _tag(Icons.location_on_rounded, '($lat, $lng)', const Color(0xFFEF4444)),
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

class _AttendanceModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final TextEditingController attidController;
  final TextEditingController attuseridController;
  final TextEditingController attcourseidController;
  final TextEditingController attsubjectidController;
  final TextEditingController attlatController;
  final TextEditingController attlongController;
  final TextEditingController atttsInController;
  final TextEditingController atttsOutController;

  final bool attvalid;
  final ValueChanged<bool> onToggleValid;

  final TextEditingController attvaliddescController;
  final TextEditingController attclassidController;
  final TextEditingController attdeviceidController;

  final bool attmaarkedbyemployee;
  final ValueChanged<bool> onToggleMarkedByEmp;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _AttendanceModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,
    required this.attidController,
    required this.attuseridController,
    required this.attcourseidController,
    required this.attsubjectidController,
    required this.attlatController,
    required this.attlongController,
    required this.atttsInController,
    required this.atttsOutController,
    required this.attvalid,
    required this.onToggleValid,
    required this.attvaliddescController,
    required this.attclassidController,
    required this.attdeviceidController,
    required this.attmaarkedbyemployee,
    required this.onToggleMarkedByEmp,
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
                    child: Icon(Icons.fingerprint_rounded, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600),
                        ),
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
                      child: Icon(Icons.close_rounded,
                          size: 18, color: Colors.grey.shade700),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // attid + user
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.badge_rounded,
                      label: 'Att ID',
                      hint: 'attid',
                      controller: attidController,
                      enabled: !isEditing, // attid fixed on edit
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.person_rounded,
                      label: 'User ID',
                      hint: 'attuserid',
                      controller: attuseridController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // course + subject
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.school_rounded,
                      label: 'Course ID',
                      hint: 'attcourseid',
                      controller: attcourseidController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.menu_book_rounded,
                      label: 'Subject ID',
                      hint: 'attsubjectid',
                      controller: attsubjectidController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // class + device
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.meeting_room_rounded,
                      label: 'Class ID',
                      hint: 'attclassid',
                      controller: attclassidController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.devices_rounded,
                      label: 'Device ID',
                      hint: 'attdeviceid',
                      controller: attdeviceidController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // lat + long
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.location_on_rounded,
                      label: 'Latitude',
                      hint: 'attlat (number)',
                      controller: attlatController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.location_on_rounded,
                      label: 'Longitude',
                      hint: 'attlong (number)',
                      controller: attlongController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // in + out
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.login_rounded,
                      label: 'Time IN',
                      hint: 'attts_in (e.g. 2025-12-10T09:30:00)',
                      controller: atttsInController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.logout_rounded,
                      label: 'Time OUT',
                      hint: 'attts_out (optional)',
                      controller: atttsOutController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.info_rounded,
                label: 'Valid Desc',
                hint: 'attvaliddesc (optional)',
                controller: attvaliddescController,
              ),

              const SizedBox(height: 12),

              // toggles
              Row(
                children: [
                  Expanded(
                    child: _toggleTile(
                      icon: attvalid ? Icons.verified_rounded : Icons.cancel_rounded,
                      label: 'Valid',
                      value: attvalid,
                      activeColor: attvalid ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                      onChanged: onToggleValid,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _toggleTile(
                      icon: Icons.how_to_reg_rounded,
                      label: 'Marked by Employee',
                      value: attmaarkedbyemployee,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: onToggleMarkedByEmp,
                    ),
                  ),
                ],
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(isEditing ? 'Update' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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

  Widget _toggleTile({
    required IconData icon,
    required String label,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: activeColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: activeColor.withOpacity(0.20)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: activeColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          ),
        ],
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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

// lib/pages/leave_application_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class LeaveApplicationPage extends StatefulWidget {
  const LeaveApplicationPage({super.key});

  @override
  State<LeaveApplicationPage> createState() => _LeaveApplicationPageState();
}

class _LeaveApplicationPageState extends State<LeaveApplicationPage> with TickerProviderStateMixin {
  // ✅ as you requested
  String get _base => ApiEndpoints.leaveApplication;

  // routes (according to your API)
  String get _listUrl => '$_base/list'; // GET
  String _getOneUrl(int id) => '$_base/$id'; // GET (not used now, kept for future)
  String get _addUrl => '$_base/add'; // POST
  String _updateUrl(int id) => '$_base/update/$id'; // PUT
  String _deleteUrl(int id) => '$_base/delete/$id'; // DELETE

  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  // modal state
  bool _saving = false;
  String? _modalError;
  bool _isEditing = false;
  int? _editingId;

  // ---------------- form controllers ----------------
  final TextEditingController _applicantNameCtrl = TextEditingController();
  final TextEditingController _designationCtrl = TextEditingController();
  final TextEditingController _departmentCtrl = TextEditingController();

  // CL
  DateTime? _clFrom;
  DateTime? _clTo;
  final TextEditingController _clReasonCtrl = TextEditingController();

  // OD
  DateTime? _odFrom;
  DateTime? _odTo;
  final TextEditingController _odReasonCtrl = TextEditingController();

  // Comp
  DateTime? _compFrom;
  DateTime? _compTo;
  DateTime? _compInLieuFrom;
  DateTime? _compInLieuTo;
  final TextEditingController _compForCtrl = TextEditingController();
  final TextEditingController _compDetailsCtrl = TextEditingController();

  // Classes adjusted
  final TextEditingController _classesAdjustedCtrl = TextEditingController();

  bool _hodCountersigned = false;
  bool _principalSigned = false;

  // section selector
  LeaveSection _section = LeaveSection.cl;

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

    _applicantNameCtrl.dispose();
    _designationCtrl.dispose();
    _departmentCtrl.dispose();
    _clReasonCtrl.dispose();
    _odReasonCtrl.dispose();
    _compForCtrl.dispose();
    _compDetailsCtrl.dispose();
    _classesAdjustedCtrl.dispose();

    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ---------------- helpers ----------------
  String _s(dynamic v) => (v ?? '').toString();

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

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

  String? _formatDate(dynamic v) {
    if (v == null) return null;
    try {
      if (v is DateTime) return v.toIso8601String();
      final dt = DateTime.parse(v.toString());
      return dt.toIso8601String();
    } catch (_) {
      return null;
    }
  }

  String _prettyDate(dynamic v) {
    final iso = _formatDate(v);
    if (iso == null) return '-';
    final d = DateTime.parse(iso).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  String _prettyDateTime(dynamic v) {
    final iso = _formatDate(v);
    if (iso == null) return '-';
    final d = DateTime.parse(iso).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  bool _hasRange(DateTime? a, DateTime? b) => a != null && b != null;

  bool _validForm() {
    final name = _applicantNameCtrl.text.trim();
    if (name.isEmpty) {
      _modalError = 'Applicant name is required.';
      return false;
    }

    final clOk = _hasRange(_clFrom, _clTo);
    final odOk = _hasRange(_odFrom, _odTo);
    final compOk = _hasRange(_compFrom, _compTo);

    if (!(clOk || odOk || compOk)) {
      _modalError = 'Select at least one section and set a valid From & To date range.';
      return false;
    }

    if (_section == LeaveSection.cl && !clOk) {
      _modalError = 'CL From & To is required.';
      return false;
    }
    if (_section == LeaveSection.od && !odOk) {
      _modalError = 'OD From & To is required.';
      return false;
    }
    if (_section == LeaveSection.comp && !compOk) {
      _modalError = 'Comp From & To is required.';
      return false;
    }

    _modalError = null;
    return true;
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((r) {
        final hay = [
          _s(r['id']),
          _s(r['applicant_name']),
          _s(r['designation']),
          _s(r['department']),
          _s(r['cl_reason']),
          _s(r['od_reason']),
          _s(r['comp_for']),
          _s(r['comp_details']),
          _s(r['classes_adjusted']),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    });
  }

  // ---------------- API calls ----------------
  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final headers = await _authHeaders();
      final resp = await http.get(Uri.parse(_listUrl), headers: headers).timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['applications'] is List) {
          _all = (decoded['applications'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _filtered = List<Map<String, dynamic>>.from(_all);
        } else {
          _error = 'Unexpected response: ${resp.body}';
        }
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: leave application list did not respond.';
    } catch (e) {
      _error = 'Failed to load applications: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _create({VoidCallback? modalRefresh}) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });
    modalRefresh?.call();

    try {
      if (!_validForm()) {
        setState(() => _saving = false);
        modalRefresh?.call();
        return;
      }

      final body = _buildPayloadForSection();

      final headers = await _authHeaders();
      final resp =
          await http.post(Uri.parse(_addUrl), headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        await _fetchAll();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        final msg = _tryFriendlyError(resp.body) ?? 'HTTP ${resp.statusCode}: ${resp.body}';
        setState(() => _modalError = msg);
        modalRefresh?.call();
      }
    } on TimeoutException {
      setState(() => _modalError = 'Timeout: create did not respond.');
      modalRefresh?.call();
    } catch (e) {
      setState(() => _modalError = 'Create failed: $e');
      modalRefresh?.call();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
      modalRefresh?.call();
    }
  }

  Future<void> _update(int id, {VoidCallback? modalRefresh}) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });
    modalRefresh?.call();

    try {
      if (!_validForm()) {
        setState(() => _saving = false);
        modalRefresh?.call();
        return;
      }

      final body = _buildPayloadForSection();

      final headers = await _authHeaders();
      final resp =
          await http.put(Uri.parse(_updateUrl(id)), headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        await _fetchAll();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        final msg = _tryFriendlyError(resp.body) ?? 'HTTP ${resp.statusCode}: ${resp.body}';
        setState(() => _modalError = msg);
        modalRefresh?.call();
      }
    } on TimeoutException {
      setState(() => _modalError = 'Timeout: update did not respond.');
      modalRefresh?.call();
    } catch (e) {
      setState(() => _modalError = 'Update failed: $e');
      modalRefresh?.call();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
      modalRefresh?.call();
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ConfirmDialog(
        title: 'Delete Leave Application?',
        message: 'This will permanently delete the selected application.',
        confirmText: 'Delete',
        confirmColor: Color(0xFFEF4444),
      ),
    );
    if (ok != true) return;

    try {
      final headers = await _authHeaders();
      final resp = await http.delete(Uri.parse(_deleteUrl(id)), headers: headers).timeout(const Duration(seconds: 25));
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

  String? _tryFriendlyError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) return decoded['error'].toString();
      if (decoded is Map && decoded['message'] != null) return decoded['message'].toString();
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _buildPayloadForSection() {
    final base = <String, dynamic>{
      "applicant_name": _applicantNameCtrl.text.trim(),
      "designation": _designationCtrl.text.trim().isEmpty ? null : _designationCtrl.text.trim(),
      "department": _departmentCtrl.text.trim().isEmpty ? null : _departmentCtrl.text.trim(),
      "classes_adjusted": _classesAdjustedCtrl.text.trim().isEmpty ? null : _classesAdjustedCtrl.text.trim(),
      "hod_countersigned": _hodCountersigned,
      "principal_signed": _principalSigned,
    };

    if (_section == LeaveSection.cl) {
      base.addAll({
        "cl_from": _clFrom?.toIso8601String(),
        "cl_to": _clTo?.toIso8601String(),
        "cl_reason": _clReasonCtrl.text.trim().isEmpty ? null : _clReasonCtrl.text.trim(),
        "od_from": null,
        "od_to": null,
        "od_reason": null,
        "comp_from": null,
        "comp_to": null,
        "comp_in_lieu_from": null,
        "comp_in_lieu_to": null,
        "comp_for": null,
        "comp_details": null,
      });
    } else if (_section == LeaveSection.od) {
      base.addAll({
        "od_from": _odFrom?.toIso8601String(),
        "od_to": _odTo?.toIso8601String(),
        "od_reason": _odReasonCtrl.text.trim().isEmpty ? null : _odReasonCtrl.text.trim(),
        "cl_from": null,
        "cl_to": null,
        "cl_reason": null,
        "comp_from": null,
        "comp_to": null,
        "comp_in_lieu_from": null,
        "comp_in_lieu_to": null,
        "comp_for": null,
        "comp_details": null,
      });
    } else {
      base.addAll({
        "comp_from": _compFrom?.toIso8601String(),
        "comp_to": _compTo?.toIso8601String(),
        "comp_in_lieu_from": _compInLieuFrom?.toIso8601String(),
        "comp_in_lieu_to": _compInLieuTo?.toIso8601String(),
        "comp_for": _compForCtrl.text.trim().isEmpty ? null : _compForCtrl.text.trim(),
        "comp_details": _compDetailsCtrl.text.trim().isEmpty ? null : _compDetailsCtrl.text.trim(),
        "cl_from": null,
        "cl_to": null,
        "cl_reason": null,
        "od_from": null,
        "od_to": null,
        "od_reason": null,
      });
    }

    return base;
  }

  // ---------------- date picker ----------------
  Future<DateTime?> _pickDate(DateTime? initial) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
  }

  // ---------------- modal helpers ----------------
  void _resetForm() {
    _modalError = null;
    _isEditing = false;
    _editingId = null;

    _applicantNameCtrl.clear();
    _designationCtrl.clear();
    _departmentCtrl.clear();

    _clFrom = null;
    _clTo = null;
    _clReasonCtrl.clear();

    _odFrom = null;
    _odTo = null;
    _odReasonCtrl.clear();

    _compFrom = null;
    _compTo = null;
    _compInLieuFrom = null;
    _compInLieuTo = null;
    _compForCtrl.clear();
    _compDetailsCtrl.clear();

    _classesAdjustedCtrl.clear();

    _hodCountersigned = false;
    _principalSigned = false;

    _section = LeaveSection.cl;
  }

  void _prefill(Map<String, dynamic> r) {
    _applicantNameCtrl.text = _s(r['applicant_name']);
    _designationCtrl.text = _s(r['designation']);
    _departmentCtrl.text = _s(r['department']);

    _clFrom = _parseDateMaybe(r['cl_from']);
    _clTo = _parseDateMaybe(r['cl_to']);
    _clReasonCtrl.text = _s(r['cl_reason']);

    _odFrom = _parseDateMaybe(r['od_from']);
    _odTo = _parseDateMaybe(r['od_to']);
    _odReasonCtrl.text = _s(r['od_reason']);

    _compFrom = _parseDateMaybe(r['comp_from']);
    _compTo = _parseDateMaybe(r['comp_to']);
    _compInLieuFrom = _parseDateMaybe(r['comp_in_lieu_from']);
    _compInLieuTo = _parseDateMaybe(r['comp_in_lieu_to']);
    _compForCtrl.text = _s(r['comp_for']);
    _compDetailsCtrl.text = _s(r['comp_details']);

    _classesAdjustedCtrl.text = _s(r['classes_adjusted']);
    _hodCountersigned = (r['hod_countersigned'] == true);
    _principalSigned = (r['principal_signed'] == true);

    if (_hasRange(_clFrom, _clTo)) {
      _section = LeaveSection.cl;
    } else if (_hasRange(_odFrom, _odTo)) {
      _section = LeaveSection.od;
    } else if (_hasRange(_compFrom, _compTo)) {
      _section = LeaveSection.comp;
    }
  }

  DateTime? _parseDateMaybe(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  DateTime? _getWhichDate(_WhichDate which) {
    switch (which) {
      case _WhichDate.clFrom:
        return _clFrom;
      case _WhichDate.clTo:
        return _clTo;
      case _WhichDate.odFrom:
        return _odFrom;
      case _WhichDate.odTo:
        return _odTo;
      case _WhichDate.compFrom:
        return _compFrom;
      case _WhichDate.compTo:
        return _compTo;
      case _WhichDate.compInLieuFrom:
        return _compInLieuFrom;
      case _WhichDate.compInLieuTo:
        return _compInLieuTo;
    }
  }

  void _setWhichDate(_WhichDate which, DateTime d) {
    switch (which) {
      case _WhichDate.clFrom:
        _clFrom = d;
        break;
      case _WhichDate.clTo:
        _clTo = d;
        break;
      case _WhichDate.odFrom:
        _odFrom = d;
        break;
      case _WhichDate.odTo:
        _odTo = d;
        break;
      case _WhichDate.compFrom:
        _compFrom = d;
        break;
      case _WhichDate.compTo:
        _compTo = d;
        break;
      case _WhichDate.compInLieuFrom:
        _compInLieuFrom = d;
        break;
      case _WhichDate.compInLieuTo:
        _compInLieuTo = d;
        break;
    }
  }

  Future<void> _openAddModal() async {
    setState(_resetForm);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void modalRefresh() => setModalState(() {});

          return _LeaveModal(
            title: 'Add Leave Application',
            subtitle: 'POST /leave-application/add',
            saving: _saving,
            errorText: _modalError,
            isEditing: false,
            section: _section,
            onSectionChanged: (s) => setModalState(() => _section = s),

            applicantNameCtrl: _applicantNameCtrl,
            designationCtrl: _designationCtrl,
            departmentCtrl: _departmentCtrl,

            clFrom: _clFrom,
            clTo: _clTo,
            clReasonCtrl: _clReasonCtrl,

            odFrom: _odFrom,
            odTo: _odTo,
            odReasonCtrl: _odReasonCtrl,

            compFrom: _compFrom,
            compTo: _compTo,
            compInLieuFrom: _compInLieuFrom,
            compInLieuTo: _compInLieuTo,
            compForCtrl: _compForCtrl,
            compDetailsCtrl: _compDetailsCtrl,

            classesAdjustedCtrl: _classesAdjustedCtrl,

            hodCountersigned: _hodCountersigned,
            principalSigned: _principalSigned,
            onHodChanged: (v) => setModalState(() => _hodCountersigned = v),
            onPrincipalChanged: (v) => setModalState(() => _principalSigned = v),

            onPickDate: (which) async {
              final picked = await _pickDate(_getWhichDate(which));
              if (picked == null) return;
              setModalState(() => _setWhichDate(which, picked));
            },

            onCancel: () => Navigator.pop(context),
            onSave: () async {
              _dismissKeyboard();
              await _create(modalRefresh: modalRefresh);
            },
          );
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
      _resetForm();
      _isEditing = true;
      _editingId = int.tryParse(_s(row['id']));
      _prefill(row);
    });

    if (_editingId == null) {
      _toast('Invalid application id');
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void modalRefresh() => setModalState(() {});

          return _LeaveModal(
            title: 'Edit Leave Application',
            subtitle: 'PUT /leave-application/update/:id',
            saving: _saving,
            errorText: _modalError,
            isEditing: true,
            section: _section,
            onSectionChanged: (s) => setModalState(() => _section = s),

            applicantNameCtrl: _applicantNameCtrl,
            designationCtrl: _designationCtrl,
            departmentCtrl: _departmentCtrl,

            clFrom: _clFrom,
            clTo: _clTo,
            clReasonCtrl: _clReasonCtrl,

            odFrom: _odFrom,
            odTo: _odTo,
            odReasonCtrl: _odReasonCtrl,

            compFrom: _compFrom,
            compTo: _compTo,
            compInLieuFrom: _compInLieuFrom,
            compInLieuTo: _compInLieuTo,
            compForCtrl: _compForCtrl,
            compDetailsCtrl: _compDetailsCtrl,

            classesAdjustedCtrl: _classesAdjustedCtrl,

            hodCountersigned: _hodCountersigned,
            principalSigned: _principalSigned,
            onHodChanged: (v) => setModalState(() => _hodCountersigned = v),
            onPrincipalChanged: (v) => setModalState(() => _principalSigned = v),

            onPickDate: (which) async {
              final picked = await _pickDate(_getWhichDate(which));
              if (picked == null) return;
              setModalState(() => _setWhichDate(which, picked));
            },

            onCancel: () => Navigator.pop(context),
            onSave: () async {
              _dismissKeyboard();
              await _update(_editingId!, modalRefresh: modalRefresh);
            },
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _modalError = null;
    });
  }

  // ---------------- UI bits ----------------
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
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 10, width: 240, color: Colors.white.withOpacity(0.6)),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 160, color: Colors.white.withOpacity(0.6)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 22,
              width: 70,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(999)),
            ),
          ],
        ),
      ),
    );
  }

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
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 8))],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Icon(Icons.arrow_back_rounded, size: 20, color: Colors.grey.shade900),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Leave Application', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          Text('White theme • API connected', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 14, offset: const Offset(0, 8))],
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
                            hintText: 'Search by applicant, dept, reason...',
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
                            child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

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
                                  const Text('Error', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                                  const SizedBox(height: 6),
                                  Text(_error!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent)),
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
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                                    _pill(icon: Icons.list_alt_rounded, label: 'Total: ${_filtered.length}', color: const Color(0xFF2563EB)),
                                    const SizedBox(width: 10),
                                    _pill(icon: Icons.link_rounded, label: 'API: /leave-application', color: const Color(0xFF7C3AED)),
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
                                        Icon(Icons.inbox_rounded, size: 34, color: Colors.grey.shade500),
                                        const SizedBox(height: 8),
                                        Text('No leave applications found',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                                        const SizedBox(height: 4),
                                        Text('Tap Add to create a new leave application.',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ..._filtered.map((r) {
                                  return _LeaveCard(
                                    row: r,
                                    prettyDate: _prettyDate,
                                    prettyDateTime: _prettyDateTime,
                                    onEdit: () => _openEditModal(r),
                                    onDelete: () {
                                      final id = int.tryParse(_s(r['id']));
                                      if (id != null) _delete(id);
                                    },
                                  );
                                }),
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

// ============================ CARD ============================
class _LeaveCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final String Function(dynamic) prettyDate;
  final String Function(dynamic) prettyDateTime;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LeaveCard({
    required this.row,
    required this.prettyDate,
    required this.prettyDateTime,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  bool _hasRange(dynamic a, dynamic b) => a != null && b != null && _s(a).isNotEmpty && _s(b).isNotEmpty;

  LeaveSection _section() {
    if (_hasRange(row['cl_from'], row['cl_to'])) return LeaveSection.cl;
    if (_hasRange(row['od_from'], row['od_to'])) return LeaveSection.od;
    if (_hasRange(row['comp_from'], row['comp_to'])) return LeaveSection.comp;
    return LeaveSection.cl;
  }

  Color _badgeColor(LeaveSection s) {
    switch (s) {
      case LeaveSection.cl:
        return const Color(0xFF2563EB);
      case LeaveSection.od:
        return const Color(0xFFF97316);
      case LeaveSection.comp:
        return const Color(0xFF10B981);
    }
  }

  IconData _badgeIcon(LeaveSection s) {
    switch (s) {
      case LeaveSection.cl:
        return Icons.event_available_rounded;
      case LeaveSection.od:
        return Icons.directions_run_rounded;
      case LeaveSection.comp:
        return Icons.swap_horiz_rounded;
    }
  }

  String _badgeText(LeaveSection s) {
    switch (s) {
      case LeaveSection.cl:
        return 'CL';
      case LeaveSection.od:
        return 'OD';
      case LeaveSection.comp:
        return 'COMP';
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _s(row['id']);
    final name = _s(row['applicant_name']);
    final dept = _s(row['department']);
    final desig = _s(row['designation']);
    final submitted = prettyDateTime(row['submitted_at'] ?? row['created_at']);
    final updated = prettyDateTime(row['updated_at']);

    final sct = _section();
    final color = _badgeColor(sct);

    dynamic from;
    dynamic to;
    String reason = '';

    if (sct == LeaveSection.cl) {
      from = row['cl_from'];
      to = row['cl_to'];
      reason = _s(row['cl_reason']);
    } else if (sct == LeaveSection.od) {
      from = row['od_from'];
      to = row['od_to'];
      reason = _s(row['od_reason']);
    } else {
      from = row['comp_from'];
      to = row['comp_to'];
      reason = _s(row['comp_details']).isNotEmpty ? _s(row['comp_details']) : _s(row['comp_for']);
    }

    final hod = row['hod_countersigned'] == true;
    final principal = row['principal_signed'] == true;

    Widget chip(IconData icon, String text, Color c) {
      if (text.trim().isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withOpacity(0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(_badgeIcon(sct), color: color),
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
                        name.isEmpty ? 'Unknown' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withOpacity(0.22)),
                      ),
                      child: Text(_badgeText(sct), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'ID: $id  •  ${desig.isEmpty ? '—' : desig}  •  ${dept.isEmpty ? '—' : dept}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    chip(Icons.date_range_rounded, '${prettyDate(from)} → ${prettyDate(to)}', const Color(0xFF7C3AED)),
                    chip(Icons.description_rounded, reason, const Color(0xFF0EA5E9)),
                    chip(Icons.schedule_rounded, 'Submitted: $submitted', const Color(0xFF2563EB)),
                    if (updated != '-') chip(Icons.update_rounded, 'Updated: $updated', const Color(0xFF10B981)),
                    chip(Icons.verified_rounded, 'HOD: ${hod ? 'Yes' : 'No'}', hod ? const Color(0xFF10B981) : const Color(0xFF9CA3AF)),
                    chip(Icons.verified_user_rounded, 'Principal: ${principal ? 'Yes' : 'No'}',
                        principal ? const Color(0xFF10B981) : const Color(0xFF9CA3AF)),
                  ],
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
    );
  }
}

// ============================ MODAL ============================
class _LeaveModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final LeaveSection section;
  final ValueChanged<LeaveSection> onSectionChanged;

  final TextEditingController applicantNameCtrl;
  final TextEditingController designationCtrl;
  final TextEditingController departmentCtrl;

  final DateTime? clFrom;
  final DateTime? clTo;
  final TextEditingController clReasonCtrl;

  final DateTime? odFrom;
  final DateTime? odTo;
  final TextEditingController odReasonCtrl;

  final DateTime? compFrom;
  final DateTime? compTo;
  final DateTime? compInLieuFrom;
  final DateTime? compInLieuTo;
  final TextEditingController compForCtrl;
  final TextEditingController compDetailsCtrl;

  final TextEditingController classesAdjustedCtrl;

  final bool hodCountersigned;
  final bool principalSigned;
  final ValueChanged<bool> onHodChanged;
  final ValueChanged<bool> onPrincipalChanged;

  final Future<void> Function(_WhichDate which) onPickDate;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _LeaveModal({
    required this.title,
    required this.subtitle,
    required this.saving,
    required this.errorText,
    required this.isEditing,
    required this.section,
    required this.onSectionChanged,
    required this.applicantNameCtrl,
    required this.designationCtrl,
    required this.departmentCtrl,
    required this.clFrom,
    required this.clTo,
    required this.clReasonCtrl,
    required this.odFrom,
    required this.odTo,
    required this.odReasonCtrl,
    required this.compFrom,
    required this.compTo,
    required this.compInLieuFrom,
    required this.compInLieuTo,
    required this.compForCtrl,
    required this.compDetailsCtrl,
    required this.classesAdjustedCtrl,
    required this.hodCountersigned,
    required this.principalSigned,
    required this.onHodChanged,
    required this.onPrincipalChanged,
    required this.onPickDate,
    required this.onCancel,
    required this.onSave,
  });

  String _prettyDate(DateTime? d) {
    if (d == null) return 'Select date';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  Widget _input({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
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

  Widget _dateButton({required IconData icon, required String label, required DateTime? value, required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                  const SizedBox(height: 4),
                  Text(
                    _prettyDate(value),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: value == null ? Colors.grey.shade600 : Colors.grey.shade900,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_calendar_rounded, size: 18, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _sectionTabs() {
    Widget tab(LeaveSection s, String text, IconData icon, Color c) {
      final active = section == s;
      return Expanded(
        child: InkWell(
          onTap: saving ? null : () => onSectionChanged(s),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? c.withOpacity(0.10) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? c.withOpacity(0.25) : Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: active ? c : Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: active ? c : Colors.grey.shade800)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(LeaveSection.cl, 'CL', Icons.event_available_rounded, const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        tab(LeaveSection.od, 'OD', Icons.directions_run_rounded, const Color(0xFFF97316)),
        const SizedBox(width: 8),
        tab(LeaveSection.comp, 'Comp', Icons.swap_horiz_rounded, const Color(0xFF10B981)),
      ],
    );
  }

  Widget _switchRow({required IconData icon, required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          Switch(
            value: value,
            onChanged: saving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 28, offset: const Offset(0, 18))],
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: primary.withOpacity(0.10), borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.beenhere_rounded, color: primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
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

              _sectionTabs(),
              const SizedBox(height: 12),

              _input(icon: Icons.person_rounded, label: 'Applicant Name *', hint: 'Enter applicant name', controller: applicantNameCtrl),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _input(icon: Icons.badge_rounded, label: 'Designation', hint: 'e.g. Assistant Prof', controller: designationCtrl),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(icon: Icons.apartment_rounded, label: 'Department', hint: 'e.g. CSE', controller: departmentCtrl),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (section == LeaveSection.cl) ...[
                Row(
                  children: [
                    Expanded(
                      child: _dateButton(
                        icon: Icons.date_range_rounded,
                        label: 'CL From *',
                        value: clFrom,
                        onTap: saving ? null : () { onPickDate(_WhichDate.clFrom); },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateButton(
                        icon: Icons.date_range_rounded,
                        label: 'CL To *',
                        value: clTo,
                        onTap: saving ? null : () { onPickDate(_WhichDate.clTo); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _input(icon: Icons.description_rounded, label: 'CL Reason', hint: 'Reason for CL', controller: clReasonCtrl, maxLines: 2),
              ],

              if (section == LeaveSection.od) ...[
                Row(
                  children: [
                    Expanded(
                      child: _dateButton(
                        icon: Icons.date_range_rounded,
                        label: 'OD From *',
                        value: odFrom,
                        onTap: saving ? null : () { onPickDate(_WhichDate.odFrom); },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateButton(
                        icon: Icons.date_range_rounded,
                        label: 'OD To *',
                        value: odTo,
                        onTap: saving ? null : () { onPickDate(_WhichDate.odTo); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _input(icon: Icons.description_rounded, label: 'OD Reason', hint: 'Reason for OD', controller: odReasonCtrl, maxLines: 2),
              ],

              if (section == LeaveSection.comp) ...[
                Row(
                  children: [
                    Expanded(
                      child: _dateButton(
                        icon: Icons.date_range_rounded,
                        label: 'Comp From *',
                        value: compFrom,
                        onTap: saving ? null : () { onPickDate(_WhichDate.compFrom); },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateButton(
                        icon: Icons.date_range_rounded,
                        label: 'Comp To *',
                        value: compTo,
                        onTap: saving ? null : () { onPickDate(_WhichDate.compTo); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _dateButton(
                        icon: Icons.history_toggle_off_rounded,
                        label: 'In-lieu From',
                        value: compInLieuFrom,
                        onTap: saving ? null : () { onPickDate(_WhichDate.compInLieuFrom); },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateButton(
                        icon: Icons.history_toggle_off_rounded,
                        label: 'In-lieu To',
                        value: compInLieuTo,
                        onTap: saving ? null : () { onPickDate(_WhichDate.compInLieuTo); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _input(icon: Icons.flag_rounded, label: 'Comp For', hint: 'Purpose / For', controller: compForCtrl),
                const SizedBox(height: 10),
                _input(icon: Icons.description_rounded, label: 'Comp Details', hint: 'Details', controller: compDetailsCtrl, maxLines: 2),
              ],

              const SizedBox(height: 12),
              _input(
                icon: Icons.class_rounded,
                label: 'Classes Adjusted',
                hint: 'e.g. Mr. X will take class, or period list',
                controller: classesAdjustedCtrl,
                maxLines: 2,
              ),
              const SizedBox(height: 10),

              _switchRow(
                icon: Icons.verified_rounded,
                label: 'HOD Countersigned',
                value: hodCountersigned,
                onChanged: onHodChanged,
              ),
              const SizedBox(height: 10),
              _switchRow(
                icon: Icons.verified_user_rounded,
                label: 'Principal Signed',
                value: principalSigned,
                onChanged: onPrincipalChanged,
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
                      onPressed: saving ? null : () { onSave(); },
                      icon: saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(isEditing ? 'Update' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
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
}

// ============================ CONFIRM DIALOG ============================
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 28, offset: const Offset(0, 18))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
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

// ============================ ENUMS ============================
enum LeaveSection { cl, od, comp }

enum _WhichDate { clFrom, clTo, odFrom, odTo, compFrom, compTo, compInLieuFrom, compInLieuTo }

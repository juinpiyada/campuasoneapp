// lib/pages/master_college_examroutine.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterCollegeExamRoutinePage extends StatefulWidget {
  const MasterCollegeExamRoutinePage({super.key});

  @override
  State<MasterCollegeExamRoutinePage> createState() =>
      _MasterCollegeExamRoutinePageState();
}

class _MasterCollegeExamRoutinePageState extends State<MasterCollegeExamRoutinePage>
    with TickerProviderStateMixin {
  // ---------- UI / State ----------
  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  // ---------- Modal state ----------
  bool _saving = false;
  String? _modalError;

  // Controllers for form
  final _examidCtrl = TextEditingController();
  final _examofferidCtrl = TextEditingController();
  final _examtermidCtrl = TextEditingController();
  final _examtypeCtrl = TextEditingController();
  final _examtitleCtrl = TextEditingController();
  final _examdateCtrl = TextEditingController(); // YYYY-MM-DD
  final _examstTimeCtrl = TextEditingController(); // HH:MM
  final _examenTimeCtrl = TextEditingController(); // HH:MM
  final _examroomidCtrl = TextEditingController();
  final _exammaxmarksCtrl = TextEditingController();
  final _examwtpercentageCtrl = TextEditingController();
  final _examcondbyCtrl = TextEditingController();
  final _examremarksCtrl = TextEditingController();

  bool _editing = false; // false => add, true => edit
  String? _editingExamId;

  // Animations (tailwind-like)
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
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

    _examidCtrl.dispose();
    _examofferidCtrl.dispose();
    _examtermidCtrl.dispose();
    _examtypeCtrl.dispose();
    _examtitleCtrl.dispose();
    _examdateCtrl.dispose();
    _examstTimeCtrl.dispose();
    _examenTimeCtrl.dispose();
    _examroomidCtrl.dispose();
    _exammaxmarksCtrl.dispose();
    _examwtpercentageCtrl.dispose();
    _examcondbyCtrl.dispose();
    _examremarksCtrl.dispose();

    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
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

  String _s(dynamic v) => (v ?? '').toString();
  int _asInt(dynamic v) => int.tryParse(_s(v).replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((r) {
        final hay = [
          _s(r['examid']),
          _s(r['examtitle']),
          _s(r['examtype']),
          _s(r['examdate']),
          _s(r['examroomid']),
          _s(r['examofferid']),
          _s(r['examtermid']),
          _s(r['examcondby']),
          _s(r['examremarks']),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    });
  }

  // ---------- API calls ----------
  String get _base => ApiEndpoints.examRoutineManager; // ✅ as you requested

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(_base); // GET /
      final headers = await _authHeaders();

      final resp = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 25),
          );

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
      _error = 'Timeout: exam routine list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load exam routines: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createRoutine() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final body = {
        "examid": _examidCtrl.text.trim(),
        "examofferid": _examofferidCtrl.text.trim(),
        "examtermid": _examtermidCtrl.text.trim(),
        "examtype": _examtypeCtrl.text.trim(),
        "examtitle": _examtitleCtrl.text.trim(),
        "examdate": _examdateCtrl.text.trim(),
        "examst_time": _examstTimeCtrl.text.trim(),
        "examen_time": _examenTimeCtrl.text.trim(),
        "examroomid": _examroomidCtrl.text.trim(),
        "exammaxmarks": _exammaxmarksCtrl.text.trim().isEmpty
            ? null
            : _asInt(_exammaxmarksCtrl.text),
        "examwtpercentge": _examwtpercentageCtrl.text.trim(),
        "examcondby": _examcondbyCtrl.text.trim(),
        "examremarks": _examremarksCtrl.text.trim(),
      };

      // minimal guard
      if (_s(body["examid"]).isEmpty) {
        throw Exception('Exam ID is required.');
      }
      if (_s(body["examtitle"]).isEmpty) {
        throw Exception('Exam Title is required.');
      }
      if (_s(body["examdate"]).isEmpty) {
        throw Exception('Exam Date (YYYY-MM-DD) is required.');
      }

      final uri = Uri.parse(_base); // POST /
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
      _modalError = 'Timeout: create exam routine did not respond in time.';
    } catch (e) {
      _modalError = 'Create failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _updateRoutine(String examid) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final body = {
        "examofferid": _examofferidCtrl.text.trim(),
        "examtermid": _examtermidCtrl.text.trim(),
        "examtype": _examtypeCtrl.text.trim(),
        "examtitle": _examtitleCtrl.text.trim(),
        "examdate": _examdateCtrl.text.trim(),
        "examst_time": _examstTimeCtrl.text.trim(),
        "examen_time": _examenTimeCtrl.text.trim(),
        "examroomid": _examroomidCtrl.text.trim(),
        "exammaxmarks": _exammaxmarksCtrl.text.trim().isEmpty
            ? null
            : _asInt(_exammaxmarksCtrl.text),
        "examwtpercentge": _examwtpercentageCtrl.text.trim(),
        "examcondby": _examcondbyCtrl.text.trim(),
        "examremarks": _examremarksCtrl.text.trim(),
      };

      if (_s(body["examtitle"]).isEmpty) {
        throw Exception('Exam Title is required.');
      }
      if (_s(body["examdate"]).isEmpty) {
        throw Exception('Exam Date (YYYY-MM-DD) is required.');
      }

      final uri = Uri.parse('$_base/$examid'); // PUT /:examid
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
      _modalError = 'Timeout: update exam routine did not respond in time.';
    } catch (e) {
      _modalError = 'Update failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteRoutine(String examid) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Exam Routine?',
        message: 'This will permanently delete examid: $examid',
        confirmText: 'Delete',
        confirmColor: const Color(0xFFEF4444),
      ),
    );

    if (ok != true) return;

    try {
      final uri = Uri.parse('$_base/$examid');
      final headers = await _authHeaders();

      final resp = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 25));

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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------- Modal helpers ----------
  void _resetForm() {
    _modalError = null;
    _examidCtrl.clear();
    _examofferidCtrl.clear();
    _examtermidCtrl.clear();
    _examtypeCtrl.clear();
    _examtitleCtrl.clear();
    _examdateCtrl.clear();
    _examstTimeCtrl.clear();
    _examenTimeCtrl.clear();
    _examroomidCtrl.clear();
    _exammaxmarksCtrl.clear();
    _examwtpercentageCtrl.clear();
    _examcondbyCtrl.clear();
    _examremarksCtrl.clear();
  }

  void _prefillForEdit(Map<String, dynamic> r) {
    _modalError = null;
    _examidCtrl.text = _s(r['examid']);
    _examofferidCtrl.text = _s(r['examofferid']);
    _examtermidCtrl.text = _s(r['examtermid']);
    _examtypeCtrl.text = _s(r['examtype']);
    _examtitleCtrl.text = _s(r['examtitle']);
    _examdateCtrl.text = _s(r['examdate']).split('T').first; // safe
    _examstTimeCtrl.text = _s(r['examst_time']);
    _examenTimeCtrl.text = _s(r['examen_time']);
    _examroomidCtrl.text = _s(r['examroomid']);
    _exammaxmarksCtrl.text = _s(r['exammaxmarks']);
    _examwtpercentageCtrl.text = _s(r['examwtpercentge']);
    _examcondbyCtrl.text = _s(r['examcondby']);
    _examremarksCtrl.text = _s(r['examremarks']);
  }

  Future<void> _openAddModal() async {
    setState(() {
      _editing = false;
      _editingExamId = null;
      _resetForm();
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RoutineModal(
        title: 'Add Exam Routine',
        subtitle: 'Create a new exam schedule entry',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,
        examidController: _examidCtrl,
        examofferidController: _examofferidCtrl,
        examtermidController: _examtermidCtrl,
        examtypeController: _examtypeCtrl,
        examtitleController: _examtitleCtrl,
        examdateController: _examdateCtrl,
        examstTimeController: _examstTimeCtrl,
        examenTimeController: _examenTimeCtrl,
        examroomidController: _examroomidCtrl,
        exammaxmarksController: _exammaxmarksCtrl,
        examwtpercentageController: _examwtpercentageCtrl,
        examcondbyController: _examcondbyCtrl,
        examremarksController: _examremarksCtrl,
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _createRoutine();
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
      _editing = true;
      _editingExamId = _s(row['examid']);
      _prefillForEdit(row);
    });

    final examid = _editingExamId!;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RoutineModal(
        title: 'Edit Exam Routine',
        subtitle: 'Update schedule for examid: $examid',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,
        examidController: _examidCtrl,
        examofferidController: _examofferidCtrl,
        examtermidController: _examtermidCtrl,
        examtypeController: _examtypeCtrl,
        examtitleController: _examtitleCtrl,
        examdateController: _examdateCtrl,
        examstTimeController: _examstTimeCtrl,
        examenTimeController: _examenTimeCtrl,
        examroomidController: _examroomidCtrl,
        exammaxmarksController: _exammaxmarksCtrl,
        examwtpercentageController: _examwtpercentageCtrl,
        examcondbyController: _examcondbyCtrl,
        examremarksController: _examremarksCtrl,
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _updateRoutine(examid);
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

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
    _searchFocus.unfocus();
  }

  // ---------- Tailwind-ish widgets ----------
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
                  Container(height: 10, width: 180, color: Colors.white.withOpacity(0.6)),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 120, color: Colors.white.withOpacity(0.6)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(height: 22, width: 60, decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(999))),
          ],
        ),
      ),
    );
  }

  // ---------- Build ----------
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
                            'Exam Routine Manager',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'White UI • Tailwind style cards',
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
                            hintText: 'Search by title, date, type, room, offer, term...',
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
                                      icon: Icons.calendar_month_rounded,
                                      label: 'Module: exam-routine-manager',
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
                                          'No routines found',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Try clearing search or add a new routine.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                ..._filtered.map((r) => _RoutineCard(
                                      row: r,
                                      onEdit: () => _openEditModal(r),
                                      onDelete: () => _deleteRoutine(_s(r['examid'])),
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

class _RoutineCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoutineCard({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final examid = _s(row['examid']);
    final title = _s(row['examtitle']);
    final type = _s(row['examtype']);
    final date = _s(row['examdate']).split('T').first;
    final st = _s(row['examst_time']);
    final en = _s(row['examen_time']);
    final room = _s(row['examroomid']);
    final offer = _s(row['examofferid']);
    final term = _s(row['examtermid']);
    final maxMarks = _s(row['exammaxmarks']);
    final wt = _s(row['examwtpercentge']);
    final cond = _s(row['examcondby']);

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
          // Title row
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
                child: const Icon(
                  Icons.event_note_rounded,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '(No Title)' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Exam ID: $examid',
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
                  child: const Icon(Icons.edit_rounded,
                      size: 18, color: Color(0xFF7C3AED)),
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
                  child: const Icon(Icons.delete_rounded,
                      size: 18, color: Color(0xFFEF4444)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(Icons.calendar_month_rounded, date, const Color(0xFF2563EB)),
              _tag(Icons.schedule_rounded, (st.isEmpty && en.isEmpty) ? 'Time: -' : '$st → $en',
                  const Color(0xFF0EA5E9)),
              _tag(Icons.category_rounded, type.isEmpty ? 'Type: -' : type, const Color(0xFF7C3AED)),
              _tag(Icons.meeting_room_rounded, room.isEmpty ? 'Room: -' : 'Room: $room',
                  const Color(0xFFF97316)),
              if (offer.isNotEmpty) _tag(Icons.local_offer_rounded, 'Offer: $offer', const Color(0xFF16A34A)),
              if (term.isNotEmpty) _tag(Icons.layers_rounded, 'Term: $term', const Color(0xFF334155)),
              if (maxMarks.isNotEmpty) _tag(Icons.scoreboard_rounded, 'Max: $maxMarks', const Color(0xFF6366F1)),
              if (wt.isNotEmpty) _tag(Icons.percent_rounded, 'Wt: $wt', const Color(0xFFEA580C)),
              if (cond.isNotEmpty) _tag(Icons.person_pin_rounded, 'By: $cond', const Color(0xFF22C55E)),
            ],
          ),
          const SizedBox(height: 8),

          if (_s(row['examremarks']).isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _s(row['examremarks']),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
}

class _RoutineModal extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final TextEditingController examidController;
  final TextEditingController examofferidController;
  final TextEditingController examtermidController;
  final TextEditingController examtypeController;
  final TextEditingController examtitleController;
  final TextEditingController examdateController;
  final TextEditingController examstTimeController;
  final TextEditingController examenTimeController;
  final TextEditingController examroomidController;
  final TextEditingController exammaxmarksController;
  final TextEditingController examwtpercentageController;
  final TextEditingController examcondbyController;
  final TextEditingController examremarksController;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _RoutineModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,
    required this.examidController,
    required this.examofferidController,
    required this.examtermidController,
    required this.examtypeController,
    required this.examtitleController,
    required this.examdateController,
    required this.examstTimeController,
    required this.examenTimeController,
    required this.examroomidController,
    required this.exammaxmarksController,
    required this.examwtpercentageController,
    required this.examcondbyController,
    required this.examremarksController,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_RoutineModal> createState() => _RoutineModalState();
}

class _RoutineModalState extends State<_RoutineModal> {
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final init = _tryParseDate(widget.examdateController.text) ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      widget.examdateController.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  DateTime? _tryParseDate(String s) {
    try {
      if (s.trim().isEmpty) return null;
      final parts = s.trim().split('-');
      if (parts.length != 3) return null;
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

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
                      color: widget.accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.edit_calendar_rounded,
                        color: widget.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: widget.onCancel,
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

              if (widget.errorText != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(
                    widget.errorText!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Form fields (tailwind style)
              _fieldRow(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.fingerprint_rounded,
                      label: 'Exam ID',
                      hint: 'e.g. EXAM-001',
                      controller: widget.examidController,
                      enabled: !widget.isEditing, // examid is path key for PUT
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.badge_rounded,
                      label: 'Exam Type',
                      hint: 'e.g. Mid Sem',
                      controller: widget.examtypeController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.title_rounded,
                label: 'Exam Title',
                hint: 'e.g. Mathematics - Paper 1',
                controller: widget.examtitleController,
              ),
              const SizedBox(height: 10),

              _fieldRow(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.local_offer_rounded,
                      label: 'Offer ID',
                      hint: 'offer id',
                      controller: widget.examofferidController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.layers_rounded,
                      label: 'Term ID',
                      hint: 'term id',
                      controller: widget.examtermidController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _fieldRow(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: AbsorbPointer(
                        child: _input(
                          icon: Icons.calendar_month_rounded,
                          label: 'Exam Date',
                          hint: 'YYYY-MM-DD',
                          controller: widget.examdateController,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.meeting_room_rounded,
                      label: 'Room ID',
                      hint: 'room id',
                      controller: widget.examroomidController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _fieldRow(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.schedule_rounded,
                      label: 'Start Time',
                      hint: 'HH:MM',
                      controller: widget.examstTimeController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.schedule_send_rounded,
                      label: 'End Time',
                      hint: 'HH:MM',
                      controller: widget.examenTimeController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _fieldRow(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.scoreboard_rounded,
                      label: 'Max Marks',
                      hint: 'e.g. 100',
                      controller: widget.exammaxmarksController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.percent_rounded,
                      label: 'Weight %',
                      hint: 'e.g. 30',
                      controller: widget.examwtpercentageController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.person_pin_rounded,
                label: 'Conducted By',
                hint: 'teacher / employee id',
                controller: widget.examcondbyController,
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.notes_rounded,
                label: 'Remarks',
                hint: 'optional notes',
                controller: widget.examremarksController,
                maxLines: 3,
              ),

              const SizedBox(height: 16),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.saving ? null : widget.onCancel,
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
                      onPressed: widget.saving ? null : () async {
                        await widget.onSave();
                        if (mounted) setState(() {});
                      },
                      icon: widget.saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(widget.isEditing ? 'Update' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
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

  Widget _fieldRow({required List<Widget> children}) {
    return Row(children: children);
  }

  Widget _input({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    bool enabled = true,
    int maxLines = 1,
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
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
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
                  maxLines: maxLines,
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
                  style: const TextStyle(
                    fontSize: 13,
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
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
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

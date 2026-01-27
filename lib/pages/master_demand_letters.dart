// lib/pages/master_demand_letters.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterDemandLettersPage extends StatefulWidget {
  const MasterDemandLettersPage({super.key});

  @override
  State<MasterDemandLettersPage> createState() => _MasterDemandLettersPageState();
}

class _MasterDemandLettersPageState extends State<MasterDemandLettersPage>
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
  bool _editing = false;
  String? _editingId;

  // Form controllers (match API payload)
  final _studentIdCtrl = TextEditingController();
  final _courseIdCtrl = TextEditingController();
  final _feeHeadCtrl = TextEditingController();
  final _feeAmountCtrl = TextEditingController();
  final _dueDateCtrl = TextEditingController(); // string (YYYY-MM-DD)
  final _acadYearCtrl = TextEditingController();

  // Animations
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  // ------------------ Config ------------------
  String get _base => ApiEndpoints.demandLetters; // ✅ as you requested

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

    _studentIdCtrl.dispose();
    _courseIdCtrl.dispose();
    _feeHeadCtrl.dispose();
    _feeAmountCtrl.dispose();
    _dueDateCtrl.dispose();
    _acadYearCtrl.dispose();

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
          _s(r['demand_id']),
          _s(r['student_id']),
          _s(r['course_id']),
          _s(r['fee_head']),
          _s(r['fee_amount']),
          _s(r['due_date']),
          _s(r['academic_year']),
          _s(r['created_at']),
          _s(r['updated_at']),
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
        // expected: rows array directly
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
      _error = 'Timeout: demand letters list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load demand letters: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ------------------ API: Create ------------------
  Future<void> _createDemand() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final studentId = _studentIdCtrl.text.trim();
      final courseId = _courseIdCtrl.text.trim();
      final feeHead = _feeHeadCtrl.text.trim();
      final feeAmountStr = _feeAmountCtrl.text.trim();
      final dueDate = _dueDateCtrl.text.trim();
      final acadYear = _acadYearCtrl.text.trim();

      if (studentId.isEmpty || courseId.isEmpty || feeHead.isEmpty || feeAmountStr.isEmpty) {
        throw Exception('Required: student_id, course_id, fee_head, fee_amount');
      }

      final feeAmount = _toDoubleOrNull(feeAmountStr);
      if (feeAmount == null) throw Exception('fee_amount must be a number');

      final body = {
        "student_id": studentId,
        "course_id": courseId,
        "fee_head": feeHead,
        "fee_amount": feeAmount,
        "due_date": dueDate.isEmpty ? null : dueDate,
        "academic_year": acadYear.isEmpty ? null : acadYear,
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
      _modalError = 'Timeout: create demand letter did not respond in time.';
    } catch (e) {
      _modalError = 'Create failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Update ------------------
  Future<void> _updateDemand(String demandId) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final studentId = _studentIdCtrl.text.trim();
      final courseId = _courseIdCtrl.text.trim();
      final feeHead = _feeHeadCtrl.text.trim();
      final feeAmountStr = _feeAmountCtrl.text.trim();
      final dueDate = _dueDateCtrl.text.trim();
      final acadYear = _acadYearCtrl.text.trim();

      if (studentId.isEmpty || courseId.isEmpty || feeHead.isEmpty || feeAmountStr.isEmpty) {
        throw Exception('Required: student_id, course_id, fee_head, fee_amount');
      }

      final feeAmount = _toDoubleOrNull(feeAmountStr);
      if (feeAmount == null) throw Exception('fee_amount must be a number');

      final body = {
        "student_id": studentId,
        "course_id": courseId,
        "fee_head": feeHead,
        "fee_amount": feeAmount,
        "due_date": dueDate.isEmpty ? null : dueDate,
        "academic_year": acadYear.isEmpty ? null : acadYear,
      };

      final uri = Uri.parse('$_base/$demandId');
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
      _modalError = 'Timeout: update demand letter did not respond in time.';
    } catch (e) {
      _modalError = 'Update failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Delete ------------------
  Future<void> _deleteDemand(String demandId) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Demand Letter?',
        message: 'This will permanently delete Demand ID: $demandId',
        confirmText: 'Delete',
        confirmColor: const Color(0xFFEF4444),
      ),
    );

    if (ok != true) return;

    try {
      final uri = Uri.parse('$_base/$demandId');
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
    _studentIdCtrl.clear();
    _courseIdCtrl.clear();
    _feeHeadCtrl.clear();
    _feeAmountCtrl.clear();
    _dueDateCtrl.clear();
    _acadYearCtrl.clear();
  }

  void _prefillForEdit(Map<String, dynamic> r) {
    _modalError = null;
    _studentIdCtrl.text = _s(r['student_id']);
    _courseIdCtrl.text = _s(r['course_id']);
    _feeHeadCtrl.text = _s(r['fee_head']);
    _feeAmountCtrl.text = _s(r['fee_amount']);
    _dueDateCtrl.text = _s(r['due_date']);
    _acadYearCtrl.text = _s(r['academic_year']);
  }

  Future<void> _openAddModal() async {
    setState(() {
      _editing = false;
      _editingId = null;
      _resetForm();
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DemandModal(
        title: 'Create Demand Letter',
        subtitle: 'Generate a new fee demand',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,
        studentIdController: _studentIdCtrl,
        courseIdController: _courseIdCtrl,
        feeHeadController: _feeHeadCtrl,
        feeAmountController: _feeAmountCtrl,
        dueDateController: _dueDateCtrl,
        academicYearController: _acadYearCtrl,
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _createDemand();
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
      _editingId = _s(row['demand_id']);
      _prefillForEdit(row);
    });

    final id = _editingId!;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DemandModal(
        title: 'Edit Demand Letter',
        subtitle: 'Demand ID: $id',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,
        studentIdController: _studentIdCtrl,
        courseIdController: _courseIdCtrl,
        feeHeadController: _feeHeadCtrl,
        feeAmountController: _feeAmountCtrl,
        dueDateController: _dueDateCtrl,
        academicYearController: _acadYearCtrl,
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _updateDemand(id);
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
                  Container(height: 10, width: 210, color: Colors.white.withOpacity(0.6)),
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
                        child: Icon(Icons.arrow_back_rounded, size: 20, color: Colors.grey.shade900),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Demand Letters',
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
                      label: const Text('Create'),
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
                            hintText: 'Search by demand_id, student_id, course_id, head, amount, year...',
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
                                    _pill(
                                      icon: Icons.list_alt_rounded,
                                      label: 'Total: ${_filtered.length}',
                                      color: const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 10),
                                    _pill(
                                      icon: Icons.request_page_rounded,
                                      label: 'API: demand-letters',
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
                                        Icon(Icons.inbox_rounded, size: 34, color: Colors.grey.shade500),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No demand letters found',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Clear search or create a new demand letter.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                ..._filtered.map((r) => _DemandCard(
                                      row: r,
                                      onEdit: () => _openEditModal(r),
                                      onDelete: () => _deleteDemand(_s(r['demand_id'])),
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

class _DemandCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DemandCard({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  String _money(dynamic v) {
    if (v == null) return '₹0';
    final n = double.tryParse(v.toString());
    if (n == null) return '₹${v.toString()}';
    return '₹${n.toStringAsFixed(2)}';
    }

  Color _accentFromHead(String head) {
    final h = head.toLowerCase();
    if (h.contains('tuition')) return const Color(0xFF2563EB);
    if (h.contains('hostel')) return const Color(0xFF0EA5E9);
    if (h.contains('exam')) return const Color(0xFF7C3AED);
    if (h.contains('library')) return const Color(0xFF22C55E);
    return const Color(0xFFF97316);
  }

  @override
  Widget build(BuildContext context) {
    final demandId = _s(row['demand_id']);
    final studentId = _s(row['student_id']);
    final courseId = _s(row['course_id']);
    final feeHead = _s(row['fee_head']);
    final feeAmount = _money(row['fee_amount']);
    final dueDate = _s(row['due_date']);
    final acadYear = _s(row['academic_year']);

    final createdAt = _s(row['created_at']);
    final updatedAt = _s(row['updated_at']);

    final accent = _accentFromHead(feeHead);

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
                child: Icon(Icons.request_page_rounded, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demand: $demandId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Student: ${studentId.isEmpty ? '-' : studentId} • Course: ${courseId.isEmpty ? '-' : courseId}',
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
              _tag(Icons.category_rounded, 'Head: ${feeHead.isEmpty ? '-' : feeHead}', accent),
              _tag(Icons.currency_rupee_rounded, 'Amount: $feeAmount', const Color(0xFF0EA5E9)),
              if (dueDate.isNotEmpty)
                _tag(Icons.event_rounded, 'Due: $dueDate', const Color(0xFFF97316)),
              if (acadYear.isNotEmpty)
                _tag(Icons.school_rounded, 'AY: $acadYear', const Color(0xFF2563EB)),
              if (createdAt.isNotEmpty)
                _tag(Icons.schedule_rounded, 'Created: $createdAt', const Color(0xFF64748B)),
              if (updatedAt.isNotEmpty)
                _tag(Icons.update_rounded, 'Updated: $updatedAt', const Color(0xFF64748B)),
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

class _DemandModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final TextEditingController studentIdController;
  final TextEditingController courseIdController;
  final TextEditingController feeHeadController;
  final TextEditingController feeAmountController;
  final TextEditingController dueDateController;
  final TextEditingController academicYearController;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _DemandModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,
    required this.studentIdController,
    required this.courseIdController,
    required this.feeHeadController,
    required this.feeAmountController,
    required this.dueDateController,
    required this.academicYearController,
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
                    child: Icon(Icons.request_page_rounded, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
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

              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.account_circle_rounded,
                      label: 'Student ID',
                      hint: 'student_id',
                      controller: studentIdController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.school_rounded,
                      label: 'Course ID',
                      hint: 'course_id',
                      controller: courseIdController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.category_rounded,
                label: 'Fee Head',
                hint: 'fee_head (e.g. Tuition / Hostel / Exam)',
                controller: feeHeadController,
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.currency_rupee_rounded,
                      label: 'Fee Amount',
                      hint: 'fee_amount (number)',
                      controller: feeAmountController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.event_rounded,
                      label: 'Due Date',
                      hint: 'due_date (YYYY-MM-DD)',
                      controller: dueDateController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _input(
                icon: Icons.date_range_rounded,
                label: 'Academic Year',
                hint: 'academic_year (e.g. 2025-2026)',
                controller: academicYearController,
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

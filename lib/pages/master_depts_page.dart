// lib/pages/master_depts_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterDeptsPage extends StatefulWidget {
  const MasterDeptsPage({super.key});

  @override
  State<MasterDeptsPage> createState() => _MasterDeptsPageState();
}

class _MasterDeptsPageState extends State<MasterDeptsPage> with TickerProviderStateMixin {
  // ✅ base url as you requested
  String get _base => ApiEndpoints.masterDepts;

  // API map (according to your routes)
  String get _listUrl => _base; // GET /
  String get _selectorUrl => '$_base/selector'; // GET /selector
  String get _postUrl => _base; // POST /
  String _putUrl(String id) => '$_base/$id'; // PUT /:id
  String _deleteUrl(String id) => '$_base/$id'; // DELETE /:id

  // state
  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  // selector IDs (optional)
  bool _selectorLoading = false;
  List<String> _deptIds = [];

  // modal state
  bool _saving = false;
  String? _modalError;
  bool _isEditing = false;

  // form ctrls (fields from API)
  final TextEditingController _deptIdCtrl = TextEditingController(); // collegedeptid
  final TextEditingController _collegeIdCtrl = TextEditingController(); // collegeid
  final TextEditingController _deptCodeCtrl = TextEditingController(); // colldept_code
  final TextEditingController _deptDescCtrl = TextEditingController(); // collegedeptdesc
  final TextEditingController _hodCtrl = TextEditingController(); // colldepthod
  final TextEditingController _emailCtrl = TextEditingController(); // colldepteaail
  final TextEditingController _phoneCtrl = TextEditingController(); // colldeptphno

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

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
      await _fetchSelector();
      _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _deptIdCtrl.dispose();
    _collegeIdCtrl.dispose();
    _deptCodeCtrl.dispose();
    _deptDescCtrl.dispose();
    _hodCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
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

  // ---------------- search ----------------
  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((r) {
        final hay = [
          _s(r['collegedeptid']),
          _s(r['collegeid']),
          _s(r['colldept_code']),
          _s(r['collegedeptdesc']),
          _s(r['colldepthod']),
          _s(r['colldepteaail']),
          _s(r['colldeptphno']),
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
        if (decoded is List) {
          _all = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _filtered = List<Map<String, dynamic>>.from(_all);
        } else {
          _error = 'Unexpected response: ${resp.body}';
        }
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: departments list did not respond.';
    } catch (e) {
      _error = 'Failed to load departments: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchSelector() async {
    setState(() => _selectorLoading = true);
    try {
      final headers = await _authHeaders();
      final resp = await http.get(Uri.parse(_selectorUrl), headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          _deptIds =
              decoded.map((e) => _s((e as Map)['collegedeptid'])).where((x) => x.trim().isNotEmpty).toSet().toList()
                ..sort();
        }
      }
    } catch (_) {
      // optional
    } finally {
      if (!mounted) return;
      setState(() => _selectorLoading = false);
    }
  }

  Future<void> _createDept() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final deptId = _deptIdCtrl.text.trim();
      final body = {
        "collegedeptid": deptId,
        "collegeid": _collegeIdCtrl.text.trim(),
        "colldept_code": _deptCodeCtrl.text.trim(),
        "collegedeptdesc": _deptDescCtrl.text.trim(),
        "colldepthod": _hodCtrl.text.trim(),
        "colldepteaail": _emailCtrl.text.trim(),
        "colldeptphno": _phoneCtrl.text.trim(),
      };

      if (deptId.isEmpty) throw Exception('collegedeptid is required');

      final headers = await _authHeaders();
      final resp = await http
          .post(Uri.parse(_postUrl), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        await _fetchAll();
        await _fetchSelector();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _modalError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _modalError = 'Timeout: create did not respond.';
    } catch (e) {
      _modalError = 'Create failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _updateDept(String id) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final body = {
        "collegeid": _collegeIdCtrl.text.trim(),
        "colldept_code": _deptCodeCtrl.text.trim(),
        "collegedeptdesc": _deptDescCtrl.text.trim(),
        "colldepthod": _hodCtrl.text.trim(),
        "colldepteaail": _emailCtrl.text.trim(),
        "colldeptphno": _phoneCtrl.text.trim(),
      };

      final headers = await _authHeaders();
      final resp = await http
          .put(Uri.parse(_putUrl(id)), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        await _fetchAll();
        await _fetchSelector();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _modalError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _modalError = 'Timeout: update did not respond.';
    } catch (e) {
      _modalError = 'Update failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteDept(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Department?',
        message: 'This will permanently delete department:\n$id',
        confirmText: 'Delete',
        confirmColor: const Color(0xFFEF4444),
      ),
    );
    if (ok != true) return;

    try {
      final headers = await _authHeaders();
      final resp = await http.delete(Uri.parse(_deleteUrl(id)), headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        await _fetchAll();
        await _fetchSelector();
      } else {
        _toast('Delete failed: HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      _toast('Timeout while deleting.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  // ---------------- modal helpers ----------------
  void _resetForm() {
    _modalError = null;
    _isEditing = false;
    _deptIdCtrl.clear();
    _collegeIdCtrl.clear();
    _deptCodeCtrl.clear();
    _deptDescCtrl.clear();
    _hodCtrl.clear();
    _emailCtrl.clear();
    _phoneCtrl.clear();
  }

  void _prefill(Map<String, dynamic> r) {
    _deptIdCtrl.text = _s(r['collegedeptid']);
    _collegeIdCtrl.text = _s(r['collegeid']);
    _deptCodeCtrl.text = _s(r['colldept_code']);
    _deptDescCtrl.text = _s(r['collegedeptdesc']);
    _hodCtrl.text = _s(r['colldepthod']);
    _emailCtrl.text = _s(r['colldepteaail']);
    _phoneCtrl.text = _s(r['colldeptphno']);
  }

  Future<void> _openAddModal() async {
    setState(_resetForm);
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DeptModal(
        title: 'Add Department',
        subtitle: 'POST /master-depts',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,
        selectorIds: _deptIds,
        selectorLoading: _selectorLoading,
        deptIdCtrl: _deptIdCtrl,
        collegeIdCtrl: _collegeIdCtrl,
        deptCodeCtrl: _deptCodeCtrl,
        deptDescCtrl: _deptDescCtrl,
        hodCtrl: _hodCtrl,
        emailCtrl: _emailCtrl,
        phoneCtrl: _phoneCtrl,
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _createDept();
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
      _resetForm();
      _isEditing = true;
      _prefill(row);
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DeptModal(
        title: 'Edit Department',
        subtitle: 'PUT /master-depts/:id',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,
        selectorIds: _deptIds,
        selectorLoading: _selectorLoading,
        deptIdCtrl: _deptIdCtrl,
        collegeIdCtrl: _collegeIdCtrl,
        deptCodeCtrl: _deptCodeCtrl,
        deptDescCtrl: _deptDescCtrl,
        hodCtrl: _hodCtrl,
        emailCtrl: _emailCtrl,
        phoneCtrl: _phoneCtrl,
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          final id = _deptIdCtrl.text.trim();
          if (id.isEmpty) {
            setState(() => _modalError = 'collegedeptid is required');
            return;
          }
          await _updateDept(id);
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

  // ---------------- UI ----------------
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
            Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(14))),
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
            Container(height: 22, width: 70, decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(999))),
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
                          const Text('Department Manager', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          Text('White theme • Tailwind style', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
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
                            hintText: 'Search dept id, code, desc, hod, phone...',
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
                                    _pill(icon: Icons.apartment_rounded, label: 'Total: ${_filtered.length}', color: const Color(0xFF2563EB)),
                                    const SizedBox(width: 10),
                                    _pill(icon: Icons.link_rounded, label: 'API: /master-depts', color: const Color(0xFF7C3AED)),
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
                                        Text('No departments found',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                                        const SizedBox(height: 4),
                                        Text('Tap Add to create a new department.',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ..._filtered.map((r) {
                                  return _DeptCard(
                                    row: r,
                                    onEdit: () => _openEditModal(r),
                                    onDelete: () => _deleteDept(_s(r['collegedeptid'])),
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

class _DeptCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeptCard({required this.row, required this.onEdit, required this.onDelete});

  String _s(dynamic v) => (v ?? '').toString();

  Widget _chip(IconData icon, String text, Color color) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
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
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deptId = _s(row['collegedeptid']);
    final code = _s(row['colldept_code']);
    final desc = _s(row['collegedeptdesc']);
    final hod = _s(row['colldepthod']);
    final phone = _s(row['colldeptphno']);
    final email = _s(row['colldepteaail']);
    final collegeId = _s(row['collegeid']);

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
              color: const Color(0xFF2563EB).withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.account_balance_rounded, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deptId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                if (desc.trim().isNotEmpty)
                  Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.tag_rounded, code, const Color(0xFF7C3AED)),
                    _chip(Icons.school_rounded, collegeId, const Color(0xFF2563EB)),
                    _chip(Icons.person_rounded, hod, const Color(0xFF10B981)),
                    _chip(Icons.phone_rounded, phone, const Color(0xFFF97316)),
                    _chip(Icons.email_rounded, email, const Color(0xFF0EA5E9)),
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

class _DeptModal extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final List<String> selectorIds;
  final bool selectorLoading;

  final TextEditingController deptIdCtrl;
  final TextEditingController collegeIdCtrl;
  final TextEditingController deptCodeCtrl;
  final TextEditingController deptDescCtrl;
  final TextEditingController hodCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _DeptModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,
    required this.selectorIds,
    required this.selectorLoading,
    required this.deptIdCtrl,
    required this.collegeIdCtrl,
    required this.deptCodeCtrl,
    required this.deptDescCtrl,
    required this.hodCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_DeptModal> createState() => _DeptModalState();
}

class _DeptModalState extends State<_DeptModal> {
  String? _selectedDeptId;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _selectedDeptId = widget.deptIdCtrl.text.trim().isEmpty ? null : widget.deptIdCtrl.text.trim();
    }
  }

  Widget _input({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    bool readOnly = false,
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
                  readOnly: readOnly,
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

  Widget _deptIdField() {
    final canDropdown = widget.selectorIds.isNotEmpty && !widget.isEditing;

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
            child: Icon(Icons.badge_rounded, size: 18, color: Colors.grey.shade800),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Department ID *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                const SizedBox(height: 6),
                if (widget.selectorLoading)
                  Row(
                    children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Loading...', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  )
                else if (canDropdown)
                  DropdownButtonFormField<String>(
                    value: _selectedDeptId,
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    hint: Text('Select dept id (optional)', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w700, fontSize: 12)),
                    items: widget.selectorIds
                        .map((u) => DropdownMenuItem<String>(
                              value: u,
                              child: Text(u, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedDeptId = v;
                        widget.deptIdCtrl.text = v ?? '';
                      });
                    },
                  )
                else
                  TextField(
                    controller: widget.deptIdCtrl,
                    readOnly: widget.isEditing, // id from URL param
                    decoration: InputDecoration(
                      hintText: 'Enter collegedeptid',
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
                    decoration: BoxDecoration(color: widget.accent.withOpacity(0.10), borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Icon(Icons.apartment_rounded, color: widget.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(widget.subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
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
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade700),
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
                  child: Text(widget.errorText!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                ),
                const SizedBox(height: 12),
              ],

              _deptIdField(),
              const SizedBox(height: 10),

              _input(icon: Icons.school_rounded, label: 'College ID', hint: 'e.g. COL_001', controller: widget.collegeIdCtrl),
              const SizedBox(height: 10),

              _input(icon: Icons.tag_rounded, label: 'Dept Code', hint: 'e.g. CSE', controller: widget.deptCodeCtrl),
              const SizedBox(height: 10),

              _input(
                icon: Icons.description_rounded,
                label: 'Dept Description',
                hint: 'e.g. Computer Science & Engineering',
                controller: widget.deptDescCtrl,
                maxLines: 2,
              ),
              const SizedBox(height: 10),

              _input(icon: Icons.person_rounded, label: 'HOD', hint: 'e.g. Dr. ABC', controller: widget.hodCtrl),
              const SizedBox(height: 10),

              _input(icon: Icons.email_rounded, label: 'Email', hint: 'dept@email.com', controller: widget.emailCtrl, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),

              _input(icon: Icons.phone_rounded, label: 'Phone', hint: '9876543210', controller: widget.phoneCtrl, keyboardType: TextInputType.phone),

              const SizedBox(height: 16),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.saving ? null : () async => await widget.onSave(),
                      icon: widget.saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(widget.isEditing ? 'Update' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
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

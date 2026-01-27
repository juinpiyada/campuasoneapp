// lib/pages/master_student.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Your backend base for STUDENT module:
const String studentApiBaseUrl = 'https://powerangers-zeo.vercel.app/api/student';

class MasterStudentScreen extends StatefulWidget {
  final bool openAddOnStart;
  const MasterStudentScreen({super.key, this.openAddOnStart = false});

  @override
  State<MasterStudentScreen> createState() => _MasterStudentScreenState();
}

class _MasterStudentScreenState extends State<MasterStudentScreen> {
  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applySearch);
    Future.microtask(() async {
      await _fetchStudents();
      if (widget.openAddOnStart && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openAddSheet();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------- Helpers ----------------------

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final authStr = prefs.getString('auth');
    if (authStr == null) return null;
    try {
      final decoded = jsonDecode(authStr);
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        return (m['token'] ?? m['jwt'] ?? m['access_token'])?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      h['Authorization'] = 'Bearer ${token.trim()}';
    }
    return h;
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Map<String, dynamic>>.from(_students));
      return;
    }
    final out = _students.where((s) {
      final name = _s(s['stuname']).toLowerCase();
      final id = _s(s['stuid']).toLowerCase();
      final mob = _s(s['stumob1']).toLowerCase();
      final course = _s(s['stu_course_id']).toLowerCase();
      return name.contains(q) || id.contains(q) || mob.contains(q) || course.contains(q);
    }).toList();
    setState(() => _filtered = out);
  }

  // ---------------------- API Calls ----------------------

  // ✅ Updated endpoints based on your base:
  // GET    https://powerangers-zeo.vercel.app/api/student/list
  // POST   https://powerangers-zeo.vercel.app/api/student/add
  // PUT    https://powerangers-zeo.vercel.app/api/student/update/:stuid
  // DELETE https://powerangers-zeo.vercel.app/api/student/delete/:stuid

  Future<void> _fetchStudents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$studentApiBaseUrl/list');
      final resp = await http.get(uri, headers: await _headers()).timeout(
            const Duration(seconds: 20),
          );

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        List list = [];
        if (decoded is Map && decoded['students'] is List) {
          list = decoded['students'] as List;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'] as List;
        } else if (decoded is List) {
          list = decoded;
        }
        _students = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _filtered = List<Map<String, dynamic>>.from(_students);
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: /api/student/list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load students: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteStudent(String stuid) async {
    try {
      final uri = Uri.parse('$studentApiBaseUrl/delete/$stuid');
      final resp = await http.delete(uri, headers: await _headers()).timeout(
            const Duration(seconds: 20),
          );
      if (resp.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student deleted'), behavior: SnackBarBehavior.floating),
        );
        await _fetchStudents();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: HTTP ${resp.statusCode}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _upsertStudent({
    required bool isEdit,
    required Map<String, dynamic> payload,
    required String stuid,
  }) async {
    final uri = isEdit
        ? Uri.parse('$studentApiBaseUrl/update/$stuid')
        : Uri.parse('$studentApiBaseUrl/add');

    try {
      final resp = await (isEdit
              ? http.put(uri, headers: await _headers(), body: jsonEncode(payload))
              : http.post(uri, headers: await _headers(), body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(); // close sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Student updated' : 'Student added'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _fetchStudents();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: HTTP ${resp.statusCode}\n${resp.body}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timeout while saving'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ---------------------- UI ----------------------

  void _openAddSheet() {
    _openStudentSheet(isEdit: false, existing: null);
  }

  void _openEditSheet(Map<String, dynamic> existing) {
    _openStudentSheet(isEdit: true, existing: existing);
  }

  Future<void> _openStudentSheet({
    required bool isEdit,
    required Map<String, dynamic>? existing,
  }) async {
    final data = _StudentFormData.fromExisting(existing);

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return _StudentBottomSheet(
            isEdit: isEdit,
            data: data,
            onSubmit: (payload) async {
              final id = data.stuid.text.trim();
              if (id.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('stuid is required'), behavior: SnackBarBehavior.floating),
                );
                return;
              }
              await _upsertStudent(isEdit: isEdit, payload: payload, stuid: id);
            },
          );
        },
      );
    } finally {
      data.dispose();
    }
  }

  Future<void> _confirmDelete(String stuid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Student?'),
        content: Text('Delete "$name" (ID: $stuid)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteStudent(stuid);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Students',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetchStudents,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Add Student',
            onPressed: _openAddSheet,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text('Add Student', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name / ID / mobile / course',
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
                    suffixIcon: _searchCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              _applySearch();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchStudents,
                child: _loading
                    ? ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                        itemCount: 8,
                        itemBuilder: (_, __) => _skeletonCard(),
                      )
                    : (_filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(16, 40, 16, 120),
                            children: [
                              Icon(Icons.school_rounded, size: 42, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              Center(
                                child: Text(
                                  'No students found',
                                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  'Tap “Add Student” to create one.',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final s = _filtered[i];
                              final stuid = _s(s['stuid']);
                              final name = _s(s['stuname']);
                              final course = _s(s['stu_course_id']);
                              final prog = _s(s['programdescription']);
                              final sem = _s(s['stu_curr_semester']);
                              final mob = _s(s['stumob1']);

                              return _studentCard(
                                name: name.isEmpty ? '(No Name)' : name,
                                stuid: stuid,
                                course: course,
                                program: prog,
                                semester: sem,
                                mobile: mob,
                                onEdit: () => _openEditSheet(s),
                                onDelete: () => _confirmDelete(stuid, name),
                              );
                            },
                          )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentCard({
    required String name,
    required String stuid,
    required String course,
    required String program,
    required String semester,
    required String mobile,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.school_rounded, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          'ID: $stuid',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(Icons.menu_book_rounded, course.isEmpty ? 'Course: -' : 'Course: $course'),
                  _pill(Icons.timeline_rounded, semester.isEmpty ? 'Sem: -' : 'Sem: $semester'),
                  _pill(Icons.call_rounded, mobile.isEmpty ? 'Mobile: -' : 'Mobile: $mobile'),
                ],
              ),
              if (program.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  program,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  Widget _skeletonCard() {
    Widget box(double w, double h, {BorderRadius? br}) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: br ?? BorderRadius.circular(12),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          box(42, 42, br: BorderRadius.circular(999)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(180, 12),
                const SizedBox(height: 8),
                box(110, 10),
                const SizedBox(height: 10),
                Row(
                  children: [
                    box(90, 26, br: BorderRadius.circular(999)),
                    const SizedBox(width: 8),
                    box(80, 26, br: BorderRadius.circular(999)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======================= Bottom Sheet Form =======================

class _StudentFormData {
  final TextEditingController stuid = TextEditingController();
  final TextEditingController stuname = TextEditingController();
  final TextEditingController stumob1 = TextEditingController();
  final TextEditingController stuemailid = TextEditingController();
  final TextEditingController stu_course_id = TextEditingController();
  final TextEditingController programdescription = TextEditingController();
  final TextEditingController stu_curr_semester = TextEditingController();
  final TextEditingController stuadmissiondt = TextEditingController();

  final TextEditingController semfees = TextEditingController(text: '0');
  final TextEditingController scholrshipfees = TextEditingController(text: '0');
  final TextEditingController program_fee_override = TextEditingController();

  final List<TextEditingController> sem = List.generate(10, (_) => TextEditingController(text: '0'));
  final List<TextEditingController> hostel = List.generate(10, (_) => TextEditingController(text: '0'));
  final TextEditingController hostel_total_fee = TextEditingController(text: '0');

  _StudentFormData();

  static _StudentFormData fromExisting(Map<String, dynamic>? e) {
    final d = _StudentFormData();
    if (e == null) return d;

    d.stuid.text = (e['stuid'] ?? '').toString();
    d.stuname.text = (e['stuname'] ?? '').toString();
    d.stumob1.text = (e['stumob1'] ?? '').toString();
    d.stuemailid.text = (e['stuemailid'] ?? '').toString();
    d.stu_course_id.text = (e['stu_course_id'] ?? '').toString();
    d.programdescription.text = (e['programdescription'] ?? '').toString();
    d.stu_curr_semester.text = (e['stu_curr_semester'] ?? '').toString();

    final adm = e['stuadmissiondt']?.toString() ?? '';
    d.stuadmissiondt.text = adm.isEmpty ? '' : adm.split('T').first;

    d.semfees.text = (e['semfees'] ?? '0').toString();
    d.scholrshipfees.text = (e['scholrshipfees'] ?? '0').toString();
    d.hostel_total_fee.text = (e['hostel_total_fee'] ?? '0').toString();

    for (int i = 0; i < 10; i++) {
      d.sem[i].text = (e['sem${i + 1}'] ?? '0').toString();
      d.hostel[i].text = (e['hostel_sem${i + 1}'] ?? '0').toString();
    }
    return d;
  }

  void dispose() {
    stuid.dispose();
    stuname.dispose();
    stumob1.dispose();
    stuemailid.dispose();
    stu_course_id.dispose();
    programdescription.dispose();
    stu_curr_semester.dispose();
    stuadmissiondt.dispose();
    semfees.dispose();
    scholrshipfees.dispose();
    program_fee_override.dispose();
    hostel_total_fee.dispose();
    for (final c in sem) {
      c.dispose();
    }
    for (final c in hostel) {
      c.dispose();
    }
  }
}

class _StudentBottomSheet extends StatefulWidget {
  final bool isEdit;
  final _StudentFormData data;
  final Future<void> Function(Map<String, dynamic> payload) onSubmit;

  const _StudentBottomSheet({
    required this.isEdit,
    required this.data,
    required this.onSubmit,
  });

  @override
  State<_StudentBottomSheet> createState() => _StudentBottomSheetState();
}

class _StudentBottomSheetState extends State<_StudentBottomSheet> {
  bool _saving = false;
  bool _showAdvanced = false;
  bool _showHostel = true;

  double _num(TextEditingController c) {
    final s = c.text.trim();
    if (s.isEmpty) return 0;
    return double.tryParse(s.replaceAll(RegExp(r'[^0-9\.\-]'), '')) ?? 0;
  }

  Map<String, dynamic> _buildPayload() {
    final d = widget.data;

    return <String, dynamic>{
      'stuid': d.stuid.text.trim(),
      'stuname': d.stuname.text.trim(),
      'stumob1': d.stumob1.text.trim(),
      'stuemailid': d.stuemailid.text.trim(),
      'stu_course_id': d.stu_course_id.text.trim(),
      'programdescription': d.programdescription.text.trim(),
      'stu_curr_semester': d.stu_curr_semester.text.trim(),
      'stuadmissiondt': d.stuadmissiondt.text.trim(),
      'semfees': _num(d.semfees),
      'scholrshipfees': _num(d.scholrshipfees),
      'program_fee_override': d.program_fee_override.text.trim().isEmpty ? null : _num(d.program_fee_override),
      for (int i = 0; i < 10; i++) 'sem${i + 1}': _num(d.sem[i]),
      for (int i = 0; i < 10; i++) 'hostel_sem${i + 1}': _num(d.hostel[i]),
      'hostel_total_fee': _num(d.hostel_total_fee),
    };
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    DateTime initial = now;
    if (ctrl.text.trim().isNotEmpty) {
      final parts = ctrl.text.trim().split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          initial = DateTime(y, m, d);
        }
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 2),
    );

    if (picked != null) {
      ctrl.text = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        widget.isEdit ? 'Edit Student' : 'Add Student',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(
                    label: 'Student ID (stuid) *',
                    controller: widget.data.stuid,
                    enabled: !widget.isEdit,
                    keyboardType: TextInputType.text,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    label: 'Student Name *',
                    controller: widget.data.stuname,
                    keyboardType: TextInputType.name,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          label: 'Mobile',
                          controller: widget.data.stumob1,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          label: 'Current Semester',
                          controller: widget.data.stu_curr_semester,
                          keyboardType: TextInputType.text,
                          hint: 'e.g. Sem 1 / 1',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          label: 'Course ID',
                          controller: widget.data.stu_course_id,
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          label: 'Admission Date',
                          controller: widget.data.stuadmissiondt,
                          readOnly: true,
                          onTap: () => _pickDate(widget.data.stuadmissiondt),
                          suffix: const Icon(Icons.calendar_month_rounded),
                          hint: 'YYYY-MM-DD',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(
                    label: 'Program Description',
                    controller: widget.data.programdescription,
                    keyboardType: TextInputType.text,
                    hint: 'e.g. BTech CSE / MCA / Diploma',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          label: 'Sem Fee (semfees)',
                          controller: widget.data.semfees,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          label: 'Scholarship (scholrshipfees)',
                          controller: widget.data.scholrshipfees,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(
                    label: 'Course Total Override (optional)',
                    controller: widget.data.program_fee_override,
                    keyboardType: TextInputType.number,
                    hint: 'program_fee_override',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _togglePill(
                        label: _showAdvanced ? 'Hide Sem-wise Fees' : 'Show Sem-wise Fees',
                        icon: Icons.payments_rounded,
                        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                      ),
                      const SizedBox(width: 10),
                      _togglePill(
                        label: _showHostel ? 'Hide Hostel' : 'Show Hostel',
                        icon: Icons.bed_rounded,
                        onTap: () => setState(() => _showHostel = !_showHostel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_showAdvanced) ...[
                    const Text('Semester Fees (sem1..sem10)', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    _grid10(widget.data.sem, prefix: 'Sem '),
                    const SizedBox(height: 14),
                  ],
                  if (_showHostel) ...[
                    const Text('Hostel Fees (hostel_sem1..hostel_sem10)', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    _grid10(widget.data.hostel, prefix: 'Hostel '),
                    const SizedBox(height: 10),
                    _field(
                      label: 'Hostel Total Fee (manual)',
                      controller: widget.data.hostel_total_fee,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              try {
                                await widget.onSubmit(_buildPayload());
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_saving)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.save_rounded, color: Colors.white),
                          const SizedBox(width: 10),
                          Text(
                            _saving ? 'Saving...' : (widget.isEdit ? 'Update Student' : 'Add Student'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Hostel remaining fee is auto-calculated by backend. Hostel total is manual.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _togglePill({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade800),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
          ],
        ),
      ),
    );
  }

  Widget _grid10(List<TextEditingController> ctrls, {required String prefix}) {
    return Column(
      children: [
        for (int r = 0; r < 5; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: _field(
                    label: '$prefix${r * 2 + 1}',
                    controller: ctrls[r * 2],
                    keyboardType: TextInputType.number,
                    dense: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    label: '$prefix${r * 2 + 2}',
                    controller: ctrls[r * 2 + 1],
                    keyboardType: TextInputType.number,
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    bool enabled = true,
    bool readOnly = false,
    String? hint,
    Widget? suffix,
    VoidCallback? onTap,
    bool dense = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
            filled: true,
            fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 12 : 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}

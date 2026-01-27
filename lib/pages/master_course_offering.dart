// lib/pages/master_course_offering.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterCourseOfferingPage extends StatefulWidget {
  const MasterCourseOfferingPage({super.key});

  @override
  State<MasterCourseOfferingPage> createState() => _MasterCourseOfferingPageState();
}

class _MasterCourseOfferingPageState extends State<MasterCourseOfferingPage>
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
  String? _editingOfferId;

  // Form controllers (match your API payload keys)
  final _offeridCtrl = TextEditingController();
  final _offerProgramidCtrl = TextEditingController();
  final _offerCourseidCtrl = TextEditingController();
  final _offferTermCtrl = TextEditingController(); // NOTE: triple 'f' (your API)
  final _offerFacultyidCtrl = TextEditingController();
  final _offerSemCtrl = TextEditingController();
  final _offerSectionCtrl = TextEditingController();
  final _offerCapacityCtrl = TextEditingController();
  final _offerRoomCtrl = TextEditingController();
  final _offerCollegeCtrl = TextEditingController();
  final _offerStatusCtrl = TextEditingController(text: 'ACTIVE');
  final _electGroupCtrl = TextEditingController();

  bool _isLab = false;
  bool _isElective = false;

  // Derived helper dropdowns from API
  bool _subjLoading = false;
  bool _teacherLoading = false;
  String? _subjError;
  String? _teacherError;

  List<Map<String, dynamic>> _subjects = []; // from /subjects?courseid=&semester=
  List<Map<String, dynamic>> _teachersForDept = []; // from /teachers-for-department?departmentid=
  List<Map<String, dynamic>> _teachersForSubject = []; // from /teachers-for-subject?subjectid=

  // Animations
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  // ------------------ Config ------------------
  String get _base => ApiEndpoints.courseOffering; // ✅ as you requested

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

    _offeridCtrl.dispose();
    _offerProgramidCtrl.dispose();
    _offerCourseidCtrl.dispose();
    _offferTermCtrl.dispose();
    _offerFacultyidCtrl.dispose();
    _offerSemCtrl.dispose();
    _offerSectionCtrl.dispose();
    _offerCapacityCtrl.dispose();
    _offerRoomCtrl.dispose();
    _offerCollegeCtrl.dispose();
    _offerStatusCtrl.dispose();
    _electGroupCtrl.dispose();

    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ------------------ Utils ------------------
  String _s(dynamic v) => (v ?? '').toString();

  int? _toIntOrNull(String v) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    final s = _s(v).trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
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
          _s(r['offerid']),
          _s(r['offer_programid']),
          _s(r['offer_programid']), // also allow offer_programid style
          _s(r['offer_courseid']),
          _s(r['offfer_term']),
          _s(r['offer_facultyid']),
          _s(r['offer_section']),
          _s(r['offerroom']),
          _s(r['offer_collegename']),
          _s(r['offerstatus']),
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
        // expected: { offerings: [...] }
        if (decoded is Map && decoded['offerings'] is List) {
          _all = (decoded['offerings'] as List)
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
      _error = 'Timeout: course offering list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load course offerings: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ------------------ API: Create ------------------
  Future<void> _createOffering() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final offerid = _offeridCtrl.text.trim();
      if (offerid.isEmpty) throw Exception('offerid is required');

      final body = {
        "offerid": offerid,
        "offer_programid": _offerProgramidCtrl.text.trim(),
        "offer_courseid": _offerCourseidCtrl.text.trim(),
        "offfer_term": _offferTermCtrl.text.trim(), // ✅ triple f
        "offer_facultyid": _offerFacultyidCtrl.text.trim(),
        "offer_semesterno": _toIntOrNull(_offerSemCtrl.text),
        "offer_section": _offerSectionCtrl.text.trim(),
        "offerislab": _isLab,
        "offer_capacity": _toIntOrNull(_offerCapacityCtrl.text),
        "offeriselective": _isElective,
        "offerelectgroupid": _electGroupCtrl.text.trim().isEmpty ? null : _electGroupCtrl.text.trim(),
        "offerroom": _offerRoomCtrl.text.trim().isEmpty ? null : _offerRoomCtrl.text.trim(),
        "offer_collegename": _offerCollegeCtrl.text.trim().isEmpty ? null : _offerCollegeCtrl.text.trim(),
        "offerstatus": _offerStatusCtrl.text.trim().isEmpty ? "ACTIVE" : _offerStatusCtrl.text.trim(),
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
      _modalError = 'Timeout: create offering did not respond in time.';
    } catch (e) {
      _modalError = 'Create failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Update ------------------
  Future<void> _updateOffering(String offerid) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final body = {
        "offer_programid": _offerProgramidCtrl.text.trim(),
        "offer_courseid": _offerCourseidCtrl.text.trim(),
        "offfer_term": _offferTermCtrl.text.trim(), // ✅ triple f
        "offer_facultyid": _offerFacultyidCtrl.text.trim(),
        "offer_semesterno": _toIntOrNull(_offerSemCtrl.text),
        "offer_section": _offerSectionCtrl.text.trim(),
        "offerislab": _isLab,
        "offer_capacity": _toIntOrNull(_offerCapacityCtrl.text),
        "offeriselective": _isElective,
        "offerelectgroupid": _electGroupCtrl.text.trim().isEmpty ? null : _electGroupCtrl.text.trim(),
        "offerroom": _offerRoomCtrl.text.trim().isEmpty ? null : _offerRoomCtrl.text.trim(),
        "offer_collegename": _offerCollegeCtrl.text.trim().isEmpty ? null : _offerCollegeCtrl.text.trim(),
        "offerstatus": _offerStatusCtrl.text.trim().isEmpty ? "ACTIVE" : _offerStatusCtrl.text.trim(),
      };

      final uri = Uri.parse('$_base/$offerid');
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
      _modalError = 'Timeout: update offering did not respond in time.';
    } catch (e) {
      _modalError = 'Update failed: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ------------------ API: Delete ------------------
  Future<void> _deleteOffering(String offerid) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Course Offering?',
        message: 'This will permanently delete offerid: $offerid',
        confirmText: 'Delete',
        confirmColor: const Color(0xFFEF4444),
      ),
    );

    if (ok != true) return;

    try {
      final uri = Uri.parse('$_base/$offerid');
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

  // ------------------ API: Subjects for Course (+ optional semester) ------------------
  Future<void> _fetchSubjectsForCourse() async {
    final courseid = _offerProgramidCtrl.text.trim(); // per your API: courseid is master_course.courseid
    final sem = _toIntOrNull(_offerSemCtrl.text);

    if (courseid.isEmpty) {
      setState(() {
        _subjects = [];
        _subjError = 'Enter Course/Program ID first';
      });
      return;
    }

    setState(() {
      _subjLoading = true;
      _subjError = null;
    });

    try {
      final qp = <String, String>{"courseid": courseid};
      if (sem != null) qp["semester"] = sem.toString();

      final uri = Uri.parse('$_base/subjects').replace(queryParameters: qp);
      final headers = await _authHeaders();

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['subjects'] is List) {
          _subjects = (decoded['subjects'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else {
          _subjects = [];
        }
      } else {
        _subjError = 'HTTP ${resp.statusCode}: ${resp.body}';
        _subjects = [];
      }
    } on TimeoutException {
      _subjError = 'Timeout while loading subjects.';
      _subjects = [];
    } catch (e) {
      _subjError = 'Failed to load subjects: $e';
      _subjects = [];
    } finally {
      if (!mounted) return;
      setState(() => _subjLoading = false);
    }
  }

  // ------------------ API: Teachers for Subject ------------------
  Future<void> _fetchTeachersForSubject(String subjectid) async {
    if (subjectid.trim().isEmpty) return;

    setState(() {
      _teacherLoading = true;
      _teacherError = null;
      _teachersForSubject = [];
    });

    try {
      final uri = Uri.parse('$_base/teachers-for-subject')
          .replace(queryParameters: {"subjectid": subjectid});
      final headers = await _authHeaders();

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['teachers'] is List) {
          _teachersForSubject = (decoded['teachers'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } else {
        _teacherError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _teacherError = 'Timeout while loading teachers for subject.';
    } catch (e) {
      _teacherError = 'Failed to load teachers: $e';
    } finally {
      if (!mounted) return;
      setState(() => _teacherLoading = false);
    }
  }

  // ------------------ API: Teachers for Department ------------------
  Future<void> _fetchTeachersForDepartment(String departmentid) async {
    if (departmentid.trim().isEmpty) return;

    setState(() {
      _teacherLoading = true;
      _teacherError = null;
      _teachersForDept = [];
    });

    try {
      final uri = Uri.parse('$_base/teachers-for-department')
          .replace(queryParameters: {"departmentid": departmentid});
      final headers = await _authHeaders();

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['teachers'] is List) {
          _teachersForDept = (decoded['teachers'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } else {
        _teacherError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _teacherError = 'Timeout while loading teachers for department.';
    } catch (e) {
      _teacherError = 'Failed to load teachers: $e';
    } finally {
      if (!mounted) return;
      setState(() => _teacherLoading = false);
    }
  }

  // ------------------ Modal open helpers ------------------
  void _resetForm() {
    _modalError = null;

    _offeridCtrl.clear();
    _offerProgramidCtrl.clear();
    _offerCourseidCtrl.clear();
    _offferTermCtrl.clear();
    _offerFacultyidCtrl.clear();
    _offerSemCtrl.clear();
    _offerSectionCtrl.clear();
    _offerCapacityCtrl.clear();
    _offerRoomCtrl.clear();
    _offerCollegeCtrl.clear();
    _offerStatusCtrl.text = 'ACTIVE';
    _electGroupCtrl.clear();

    _isLab = false;
    _isElective = false;

    _subjects = [];
    _teachersForDept = [];
    _teachersForSubject = [];
    _subjError = null;
    _teacherError = null;
  }

  void _prefillForEdit(Map<String, dynamic> r) {
    _modalError = null;

    _offeridCtrl.text = _s(r['offerid']);
    _offerProgramidCtrl.text = _s(r['offer_programid'] ?? r['offer_programid']);
    _offerCourseidCtrl.text = _s(r['offer_courseid']);
    _offferTermCtrl.text = _s(r['offfer_term']);
    _offerFacultyidCtrl.text = _s(r['offer_facultyid']);
    _offerSemCtrl.text = _s(r['offer_semesterno']);
    _offerSectionCtrl.text = _s(r['offer_section']);
    _offerCapacityCtrl.text = _s(r['offer_capacity']);
    _offerRoomCtrl.text = _s(r['offerroom'] ?? r['offerroom'] ?? r['offer_room']);
    _offerCollegeCtrl.text = _s(r['offer_collegename']);
    _offerStatusCtrl.text = _s(r['offerstatus']).isEmpty ? 'ACTIVE' : _s(r['offerstatus']);
    _electGroupCtrl.text = _s(r['offerelectgroupid']);

    _isLab = _toBool(r['offerislab']);
    _isElective = _toBool(r['offeriselective']);
  }

  Future<void> _openAddModal() async {
    setState(() {
      _editingOfferId = null;
      _resetForm();
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _OfferingModal(
        title: 'Add Course Offering',
        subtitle: 'Create offering (with subjects & teachers helpers)',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,

        offeridController: _offeridCtrl,
        offerProgramidController: _offerProgramidCtrl,
        offerCourseidController: _offerCourseidCtrl,
        offferTermController: _offferTermCtrl,
        offerFacultyidController: _offerFacultyidCtrl,
        offerSemController: _offerSemCtrl,
        offerSectionController: _offerSectionCtrl,
        offerCapacityController: _offerCapacityCtrl,
        offerRoomController: _offerRoomCtrl,
        offerCollegeController: _offerCollegeCtrl,
        offerStatusController: _offerStatusCtrl,
        electGroupController: _electGroupCtrl,

        isLab: _isLab,
        isElective: _isElective,
        onToggleLab: (v) => setState(() => _isLab = v),
        onToggleElective: (v) => setState(() => _isElective = v),

        // helpers
        subjLoading: _subjLoading,
        subjError: _subjError,
        subjects: _subjects,
        teacherLoading: _teacherLoading,
        teacherError: _teacherError,
        teachersForSubject: _teachersForSubject,
        teachersForDept: _teachersForDept,

        onLoadSubjects: () async {
          _dismissKeyboard();
          await _fetchSubjectsForCourse();
          if (mounted) setState(() {});
        },
        onPickSubject: (subjectid) async {
          _offerCourseidCtrl.text = subjectid;
          await _fetchTeachersForSubject(subjectid);
          if (mounted) setState(() {});
        },
        onLoadTeachersForDept: (departmentid) async {
          _dismissKeyboard();
          await _fetchTeachersForDepartment(departmentid);
          if (mounted) setState(() {});
        },
        onPickTeacher: (teacherid) {
          _offerFacultyidCtrl.text = teacherid;
          setState(() {});
        },

        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _createOffering();
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
      _editingOfferId = _s(row['offerid']);
      _prefillForEdit(row);
      _subjects = [];
      _teachersForSubject = [];
      _teachersForDept = [];
      _subjError = null;
      _teacherError = null;
    });

    final offerid = _editingOfferId!;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _OfferingModal(
        title: 'Edit Course Offering',
        subtitle: 'Update offering for offerid: $offerid',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,

        offeridController: _offeridCtrl,
        offerProgramidController: _offerProgramidCtrl,
        offerCourseidController: _offerCourseidCtrl,
        offferTermController: _offferTermCtrl,
        offerFacultyidController: _offerFacultyidCtrl,
        offerSemController: _offerSemCtrl,
        offerSectionController: _offerSectionCtrl,
        offerCapacityController: _offerCapacityCtrl,
        offerRoomController: _offerRoomCtrl,
        offerCollegeController: _offerCollegeCtrl,
        offerStatusController: _offerStatusCtrl,
        electGroupController: _electGroupCtrl,

        isLab: _isLab,
        isElective: _isElective,
        onToggleLab: (v) => setState(() => _isLab = v),
        onToggleElective: (v) => setState(() => _isElective = v),

        subjLoading: _subjLoading,
        subjError: _subjError,
        subjects: _subjects,
        teacherLoading: _teacherLoading,
        teacherError: _teacherError,
        teachersForSubject: _teachersForSubject,
        teachersForDept: _teachersForDept,

        onLoadSubjects: () async {
          _dismissKeyboard();
          await _fetchSubjectsForCourse();
          if (mounted) setState(() {});
        },
        onPickSubject: (subjectid) async {
          _offerCourseidCtrl.text = subjectid;
          await _fetchTeachersForSubject(subjectid);
          if (mounted) setState(() {});
        },
        onLoadTeachersForDept: (departmentid) async {
          _dismissKeyboard();
          await _fetchTeachersForDepartment(departmentid);
          if (mounted) setState(() {});
        },
        onPickTeacher: (teacherid) {
          _offerFacultyidCtrl.text = teacherid;
          setState(() {});
        },

        onCancel: () => Navigator.pop(context),
        onSave: () async {
          _dismissKeyboard();
          await _updateOffering(offerid);
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

  // ------------------ UI bits ------------------
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
                            'Course Offering',
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
                                'Search by offerid, course/program, subject, teacher, section, room...',
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
                                      icon: Icons.link_rounded,
                                      label: 'API: course-offering',
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
                                          'No offerings found',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Clear search or add a new offering.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                ..._filtered.map((r) => _OfferingCard(
                                      row: r,
                                      onEdit: () => _openEditModal(r),
                                      onDelete: () => _deleteOffering(_s(r['offerid'])),
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

class _OfferingCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OfferingCard({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    final s = _s(v).trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  @override
  Widget build(BuildContext context) {
    final offerid = _s(row['offerid']);
    final programId = _s(row['offer_programid']);
    final subjectId = _s(row['offer_courseid']);
    final termId = _s(row['offfer_term']);
    final facultyId = _s(row['offer_facultyid']);
    final sem = _s(row['offer_semesterno']);
    final section = _s(row['offer_section']);
    final cap = _s(row['offer_capacity']);
    final room = _s(row['offerroom']);
    final college = _s(row['offer_collegename']);
    final status = _s(row['offerstatus']).isEmpty ? 'ACTIVE' : _s(row['offerstatus']);
    final isLab = _toBool(row['offerislab']);
    final isElect = _toBool(row['offeriselective']);
    final electGroup = _s(row['offerelectgroupid']);

    Color statusColor() {
      final s = status.toUpperCase();
      if (s == 'ACTIVE') return const Color(0xFF22C55E);
      if (s == 'INACTIVE') return const Color(0xFFEF4444);
      return const Color(0xFF0EA5E9);
    }

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
                child: const Icon(Icons.hub_rounded, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offer: $offerid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Program: ${programId.isEmpty ? '-' : programId} • Sem: ${sem.isEmpty ? '-' : sem} • Sec: ${section.isEmpty ? '-' : section}',
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
              _tag(Icons.book_rounded, 'Subject: ${subjectId.isEmpty ? '-' : subjectId}', const Color(0xFF2563EB)),
              if (termId.isNotEmpty) _tag(Icons.date_range_rounded, 'Term: $termId', const Color(0xFF7C3AED)),
              if (facultyId.isNotEmpty) _tag(Icons.person_rounded, 'Teacher: $facultyId', const Color(0xFF0EA5E9)),
              if (room.isNotEmpty) _tag(Icons.meeting_room_rounded, 'Room: $room', const Color(0xFFF97316)),
              if (college.isNotEmpty) _tag(Icons.apartment_rounded, college, const Color(0xFF334155)),
              if (cap.isNotEmpty) _tag(Icons.groups_rounded, 'Cap: $cap', const Color(0xFF16A34A)),
              _tag(Icons.verified_rounded, status, statusColor()),
              if (isLab) _tag(Icons.science_rounded, 'LAB', const Color(0xFF6366F1)),
              if (isElect) _tag(Icons.star_rounded, 'ELECTIVE', const Color(0xFFEA580C)),
              if (electGroup.isNotEmpty) _tag(Icons.group_work_rounded, 'Group: $electGroup', const Color(0xFF64748B)),
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

class _OfferingModal extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final TextEditingController offeridController;
  final TextEditingController offerProgramidController;
  final TextEditingController offerCourseidController;
  final TextEditingController offferTermController;
  final TextEditingController offerFacultyidController;
  final TextEditingController offerSemController;
  final TextEditingController offerSectionController;
  final TextEditingController offerCapacityController;
  final TextEditingController offerRoomController;
  final TextEditingController offerCollegeController;
  final TextEditingController offerStatusController;
  final TextEditingController electGroupController;

  final bool isLab;
  final bool isElective;
  final ValueChanged<bool> onToggleLab;
  final ValueChanged<bool> onToggleElective;

  // Helpers data
  final bool subjLoading;
  final String? subjError;
  final List<Map<String, dynamic>> subjects;

  final bool teacherLoading;
  final String? teacherError;
  final List<Map<String, dynamic>> teachersForSubject;
  final List<Map<String, dynamic>> teachersForDept;

  final Future<void> Function() onLoadSubjects;
  final Future<void> Function(String subjectid) onPickSubject;

  final Future<void> Function(String departmentid) onLoadTeachersForDept;
  final void Function(String teacherid) onPickTeacher;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _OfferingModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,

    required this.offeridController,
    required this.offerProgramidController,
    required this.offerCourseidController,
    required this.offferTermController,
    required this.offerFacultyidController,
    required this.offerSemController,
    required this.offerSectionController,
    required this.offerCapacityController,
    required this.offerRoomController,
    required this.offerCollegeController,
    required this.offerStatusController,
    required this.electGroupController,

    required this.isLab,
    required this.isElective,
    required this.onToggleLab,
    required this.onToggleElective,

    required this.subjLoading,
    required this.subjError,
    required this.subjects,

    required this.teacherLoading,
    required this.teacherError,
    required this.teachersForSubject,
    required this.teachersForDept,

    required this.onLoadSubjects,
    required this.onPickSubject,

    required this.onLoadTeachersForDept,
    required this.onPickTeacher,

    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_OfferingModal> createState() => _OfferingModalState();
}

class _OfferingModalState extends State<_OfferingModal> {
  final _deptCtrl = TextEditingController(); // used only to load teachers by dept

  @override
  void dispose() {
    _deptCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString();

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
                    child: Icon(Icons.add_circle_outline_rounded, color: widget.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(widget.subtitle,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
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
                  child: Text(
                    widget.errorText!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Offer ID + Status
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.fingerprint_rounded,
                      label: 'Offer ID',
                      hint: 'offerid (required)',
                      controller: widget.offeridController,
                      enabled: !widget.isEditing,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.verified_rounded,
                      label: 'Status',
                      hint: 'ACTIVE / INACTIVE',
                      controller: widget.offerStatusController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Program/Course + Semester
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.school_rounded,
                      label: 'Course/Program ID',
                      hint: 'offer_programid (master_course.courseid)',
                      controller: widget.offerProgramidController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.filter_9_plus_rounded,
                      label: 'Semester No',
                      hint: 'offer_semesterno',
                      controller: widget.offerSemController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Section + Capacity
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.view_week_rounded,
                      label: 'Section',
                      hint: 'offer_section',
                      controller: widget.offerSectionController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.groups_rounded,
                      label: 'Capacity',
                      hint: 'offer_capacity',
                      controller: widget.offerCapacityController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Term + Room
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.date_range_rounded,
                      label: 'Academic Year ID',
                      hint: 'offfer_term (college_acad_year.id)',
                      controller: widget.offferTermController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.meeting_room_rounded,
                      label: 'Room',
                      hint: 'offerroom',
                      controller: widget.offerRoomController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // College
              _input(
                icon: Icons.apartment_rounded,
                label: 'College Name',
                hint: 'offer_collegename',
                controller: widget.offerCollegeController,
              ),
              const SizedBox(height: 10),

              // Subject ID + Teacher ID
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.book_rounded,
                      label: 'Subject ID',
                      hint: 'offer_courseid (master_subject.subjectid)',
                      controller: widget.offerCourseidController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.person_rounded,
                      label: 'Teacher ID',
                      hint: 'offer_facultyid (master_teacher.teacherid)',
                      controller: widget.offerFacultyidController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Flags
              Row(
                children: [
                  Expanded(
                    child: _switchTile(
                      icon: Icons.science_rounded,
                      title: 'Is Lab',
                      value: widget.isLab,
                      onChanged: widget.onToggleLab,
                      accent: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _switchTile(
                      icon: Icons.star_rounded,
                      title: 'Is Elective',
                      value: widget.isElective,
                      onChanged: widget.onToggleElective,
                      accent: const Color(0xFFEA580C),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              _input(
                icon: Icons.group_work_rounded,
                label: 'Elective Group ID (optional)',
                hint: 'offerelectgroupid',
                controller: widget.electGroupController,
              ),

              const SizedBox(height: 14),

              // ---------- Helpers Section ----------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_fix_high_rounded, color: Colors.grey.shade800),
                        const SizedBox(width: 8),
                        const Text(
                          'Helpers (Optional)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        _miniBtn(
                          icon: Icons.menu_book_rounded,
                          label: 'Load Subjects',
                          onTap: widget.onLoadSubjects,
                          color: const Color(0xFF2563EB),
                          loading: widget.subjLoading,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.subjError != null)
                      Text(
                        widget.subjError!,
                        style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w700),
                      ),

                    if (widget.subjects.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Pick a subject (fills Subject ID + loads teachers for that subject):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          itemCount: widget.subjects.length,
                          itemBuilder: (_, i) {
                            final s = widget.subjects[i];
                            final sid = _s(s['subjectid']);
                            final desc = _s(s['subjectdesc']);
                            final code = _s(s['subjectcode']);
                            return InkWell(
                              onTap: () async {
                                await widget.onPickSubject(sid);
                                if (mounted) setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.book_rounded, size: 18, color: Color(0xFF2563EB)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('$sid  •  ${code.isEmpty ? '-' : code}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 2),
                                          Text(desc.isEmpty ? '-' : desc,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        const Icon(Icons.school_outlined),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Teachers by Department (optional)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                        ),
                        _miniBtn(
                          icon: Icons.people_alt_rounded,
                          label: 'Load',
                          onTap: () async {
                            final dept = _deptCtrl.text.trim();
                            if (dept.isEmpty) return;
                            await widget.onLoadTeachersForDept(dept);
                            if (mounted) setState(() {});
                          },
                          color: const Color(0xFF7C3AED),
                          loading: widget.teacherLoading,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _input(
                      icon: Icons.account_tree_rounded,
                      label: 'Department ID',
                      hint: 'departmentid',
                      controller: _deptCtrl,
                    ),
                    if (widget.teacherError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          widget.teacherError!,
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w700),
                        ),
                      ),

                    if (widget.teachersForSubject.isNotEmpty || widget.teachersForDept.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('Pick a teacher (fills Teacher ID):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 140,
                        child: ListView(
                          children: [
                            ...widget.teachersForSubject.map((t) => _teacherTile(t, label: 'Subject Teacher')),
                            ...widget.teachersForDept.map((t) => _teacherTile(t, label: 'Dept Teacher')),
                          ],
                        ),
                      )
                    ],
                  ],
                ),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.saving
                          ? null
                          : () async {
                              await widget.onSave();
                              if (mounted) setState(() {});
                            },
                      icon: widget.saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
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

  Widget _teacherTile(Map<String, dynamic> t, {required String label}) {
    final id = _s(t['teacherid']);
    final name = _s(t['teachername']);
    final desig = _s(t['teacherdesig']);
    return InkWell(
      onTap: () {
        widget.onPickTeacher(id);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_rounded, size: 18, color: Color(0xFF0EA5E9)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$id • $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(
                    '${desig.isEmpty ? '-' : desig} • $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
    required Color color,
    required bool loading,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accent,
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
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withOpacity(0.18)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          ),
          Switch(
            value: value,
            activeColor: accent,
            onChanged: onChanged,
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
                Text(label,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
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

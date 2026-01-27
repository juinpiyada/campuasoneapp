// lib/pages/bulktecher.dart

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class TeacherMasterPage extends StatefulWidget {
  const TeacherMasterPage({super.key});

  @override
  State<TeacherMasterPage> createState() => _TeacherMasterPageState();
}

class _TeacherMasterPageState extends State<TeacherMasterPage>
    with TickerProviderStateMixin {
  // ✅ As you said
  String get _bulkUpUrl => ApiEndpoints.teacherMasterBulkUp;

  // Derive base url from /teacher-master-bulk-up  →  /teacher-master
  String get _teacherBaseUrl {
    final u = _bulkUpUrl.replaceAll(RegExp(r'\/+$'), '');
    final derived =
        u.replaceAll(RegExp(r'\/teacher-master-bulk-up$'), '/teacher-master');
    return derived;
  }

  // API endpoints from base
  String _oneUrl(String teacherid) => '$_teacherBaseUrl/$teacherid';

  late final TabController _tabCtrl;

  // =================== AUTH HEADERS ===================
  Future<Map<String, String>> _authHeaders({bool jsonType = true}) async {
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
      if (jsonType) 'Content-Type': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    return headers;
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

  String _s(dynamic v) => (v ?? '').toString();

  // =================== BULK UPLOAD STATE ===================
  PlatformFile? _pickedCsv;
  bool _uploading = false;
  String? _uploadError;
  Map<String, dynamic>? _uploadResult;

  // =================== LIST STATE ===================
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _listLoading = true;
  String? _listError;

  int _limit = 25;
  int _offset = 0;
  int _total = 0;

  List<Map<String, dynamic>> _rows = [];

  // =================== Columns (for hint/template) ===================
  static const List<String> COLS = [
    'teacherid',
    'teacheruserid',
    'teachername',
    'teacheraddress',
    'teacheremailid',
    'teachermob1',
    'teachermob2',
    'teachergender',
    'teachercaste',
    'teacherdoj',
    'teacherdesig',
    'teachertype',
    'teachermaxweekhrs',
    'teachercollegeid',
    'teachervalid',
    'teacherparentname1',
    'teacherparentname2',
    'pancardno',
    'aadharno',
    'communication_address',
    'permanent_address',
    'teacherdob',
    'ismarried',
    'emergency_contact_name',
    'emergency_contact_address',
    'emergency_contact_phone',
    'createdat',
    'updatedat',
    'teacher_dept_id',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _offset = 0;
        _fetchTeachers();
      });
    });

    Future.microtask(() async {
      await _fetchTeachers();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // =================== BULK UPLOAD ===================
  Future<void> _pickCsv() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true, // IMPORTANT for web + avoids dart:io
      );
      if (res == null || res.files.isEmpty) return;

      setState(() {
        _pickedCsv = res.files.first;
        _uploadError = null;
        _uploadResult = null;
      });
    } catch (e) {
      setState(() => _uploadError = 'File pick failed: $e');
    }
  }

  Future<void> _uploadCsv() async {
    if (_pickedCsv == null) {
      _toast('Please choose a CSV file first.');
      return;
    }

    setState(() {
      _uploading = true;
      _uploadError = null;
      _uploadResult = null;
    });

    try {
      final headers = await _authHeaders(jsonType: false);

      final req = http.MultipartRequest('POST', Uri.parse(_bulkUpUrl));
      req.headers.addAll(headers);

      // Field name must be "file" as your API expects upload.single('file')
      final bytes = _pickedCsv!.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception(
            'File bytes are empty. Please re-pick the CSV (withData:true).');
      }

      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _pickedCsv!.name,
        ),
      );

      final streamed =
          await req.send().timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final decoded = jsonDecode(resp.body);
        setState(() => _uploadResult = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : {"raw": decoded});
        _toast('Bulk upload done.');
        await _fetchTeachers(); // refresh list after upload
        if (mounted) _tabCtrl.animateTo(1); // go to list tab
      } else {
        String msg = 'HTTP ${resp.statusCode}: ${resp.body}';
        try {
          final d = jsonDecode(resp.body);
          if (d is Map && (d['error'] != null || d['message'] != null)) {
            msg = (d['error'] ?? d['message']).toString();
          }
        } catch (_) {}
        setState(() => _uploadError = msg);
      }
    } on TimeoutException {
      setState(() => _uploadError = 'Upload timeout. Please try again.');
    } catch (e) {
      setState(() => _uploadError = 'Upload failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _uploading = false);
    }
  }

  // =================== LIST TEACHERS ===================
  Future<void> _fetchTeachers() async {
    setState(() {
      _listLoading = true;
      _listError = null;
    });

    try {
      final headers = await _authHeaders();
      final q = _searchCtrl.text.trim();

      final uri = Uri.parse(_teacherBaseUrl).replace(
        queryParameters: {
          if (q.isNotEmpty) 'q': q,
          'limit': _limit.toString(),
          'offset': _offset.toString(),
        },
      );

      final resp =
          await http.get(uri, headers: headers).timeout(
                const Duration(seconds: 25),
              );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          final total = decoded['total'];
          final rows = decoded['rows'];

          setState(() {
            _total =
                (total is int) ? total : int.tryParse(_s(total)) ?? 0;
            _rows = (rows is List)
                ? rows
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList()
                : <Map<String, dynamic>>[];
          });
        } else {
          setState(() => _listError = 'Unexpected response: ${resp.body}');
        }
      } else {
        setState(() => _listError = 'HTTP ${resp.statusCode}: ${resp.body}');
      }
    } on TimeoutException {
      setState(
          () => _listError = 'Timeout: teacher list did not respond.');
    } catch (e) {
      setState(() => _listError = 'Failed to load teachers: $e');
    } finally {
      if (!mounted) return;
      setState(() => _listLoading = false);
    }
  }

  Future<void> _deleteTeacher(String teacherid) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ConfirmDialog(
        title: 'Delete Teacher?',
        message: 'This will permanently delete this teacher record.',
        confirmText: 'Delete',
        confirmColor: Color(0xFFEF4444),
      ),
    );
    if (ok != true) return;

    try {
      final headers = await _authHeaders();
      final resp = await http
          .delete(Uri.parse(_oneUrl(teacherid)), headers: headers)
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        _toast('Deleted');
        await _fetchTeachers();
      } else {
        _toast('Delete failed: HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      _toast('Timeout while deleting.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _openEditTeacher(Map<String, dynamic> row) async {
    final teacherid = _s(row['teacherid']);
    if (teacherid.trim().isEmpty) {
      _toast('Invalid teacherid');
      return;
    }

    // Edit only common fields (partial update is supported by your API)
    final nameCtrl =
        TextEditingController(text: _s(row['teachername']));
    final emailCtrl =
        TextEditingController(text: _s(row['teacheremailid']));
    final mobCtrl = TextEditingController(text: _s(row['teachermob1']));
    final addrCtrl =
        TextEditingController(text: _s(row['teacheraddress']));
    final desigCtrl =
        TextEditingController(text: _s(row['teacherdesig']));
    final collegeCtrl =
        TextEditingController(text: _s(row['teachercollegeid']));
    final deptCtrl =
        TextEditingController(text: _s(row['teacher_dept_id']));
    final validCtrl =
        TextEditingController(text: _s(row['teachervalid'])); // text

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _TeacherEditDialog(
        teacherid: teacherid,
        nameCtrl: nameCtrl,
        emailCtrl: emailCtrl,
        mobCtrl: mobCtrl,
        addrCtrl: addrCtrl,
        desigCtrl: desigCtrl,
        collegeCtrl: collegeCtrl,
        deptCtrl: deptCtrl,
        validCtrl: validCtrl,
        onSave: () async {
          final body = <String, dynamic>{
            "teachername": nameCtrl.text.trim(),
            "teacheremailid": emailCtrl.text.trim().isEmpty
                ? null
                : emailCtrl.text.trim(),
            "teachermob1": mobCtrl.text.trim().isEmpty
                ? null
                : mobCtrl.text.trim(),
            "teacheraddress": addrCtrl.text.trim().isEmpty
                ? null
                : addrCtrl.text.trim(),
            "teacherdesig": desigCtrl.text.trim().isEmpty
                ? null
                : desigCtrl.text.trim(),
            "teachercollegeid": collegeCtrl.text.trim().isEmpty
                ? null
                : collegeCtrl.text.trim(),
            "teacher_dept_id": deptCtrl.text.trim().isEmpty
                ? null
                : deptCtrl.text.trim(),
            "teachervalid": validCtrl.text.trim().isEmpty
                ? null
                : validCtrl.text.trim(),
          };

          final headers = await _authHeaders();
          final resp = await http
              .put(Uri.parse(_oneUrl(teacherid)),
                  headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 25));

          if (resp.statusCode == 200) {
            _toast('Updated');
            await _fetchTeachers();
            if (mounted) Navigator.pop(context, true);
          } else {
            String msg = 'HTTP ${resp.statusCode}: ${resp.body}';
            try {
              final d = jsonDecode(resp.body);
              if (d is Map &&
                  (d['error'] != null || d['message'] != null)) {
                msg = (d['error'] ?? d['message']).toString();
              }
            } catch (_) {}
            _toast(msg);
          }
        },
      ),
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
    mobCtrl.dispose();
    addrCtrl.dispose();
    desigCtrl.dispose();
    collegeCtrl.dispose();
    deptCtrl.dispose();
    validCtrl.dispose();

    if (result == true) {
      // already refreshed
    }
  }

  // =================== UI ===================
  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF7F7FB);
    const primary = Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          )
                        ],
                        border:
                            Border.all(color: Colors.grey.shade200),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: Colors.grey.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Teacher Master',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'White theme • Bulk Upload + List',
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
                    tooltip: 'Refresh list',
                    onPressed: _listLoading ? null : _fetchTeachers,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),

            // Tabs
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  indicator: BoxDecoration(
                    color: primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: primary,
                  unselectedLabelColor: Colors.grey.shade700,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.upload_file_rounded),
                      text: 'Bulk Upload',
                    ),
                    Tab(
                      icon: Icon(Icons.people_alt_rounded),
                      text: 'Teachers',
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _bulkUploadTab(primary: primary),
                  _teachersTab(primary: primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulkUploadTab({required Color primary}) {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(
            icon: Icons.link_rounded,
            title: 'Endpoint',
            subtitle: _bulkUpUrl,
            color: const Color(0xFF7C3AED),
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.rule_rounded,
            title: 'CSV Headers Required',
            subtitle:
                'Your backend validates all columns. Keep header names exactly same.',
            color: const Color(0xFF2563EB),
            trailing: TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    insetPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 18),
                    backgroundColor: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(0.10),
                            blurRadius: 28,
                            offset: const Offset(0, 18),
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Required Columns',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: COLS
                                .map(
                                  (c) => Container(
                                    padding:
                                        const EdgeInsets
                                                .symmetric(
                                            horizontal: 10,
                                            vertical: 6),
                                    decoration:
                                        BoxDecoration(
                                      color: Colors
                                          .grey.shade100,
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                                  999),
                                      border: Border.all(
                                        color: Colors.grey
                                            .shade200,
                                      ),
                                    ),
                                    child: Text(
                                      c,
                                      style:
                                          const TextStyle(
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 14),
                          Align(
                            alignment:
                                Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  Navigator.pop(
                                      context),
                              icon: const Icon(
                                  Icons.close_rounded),
                              label:
                                  const Text('Close'),
                              style: OutlinedButton
                                  .styleFrom(
                                foregroundColor: Colors
                                    .grey.shade800,
                                side: BorderSide(
                                  color: Colors
                                      .grey.shade300,
                                ),
                                padding: const EdgeInsets
                                        .symmetric(
                                    horizontal: 14,
                                    vertical: 12),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                              14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('View'),
            ),
          ),
          const SizedBox(height: 12),

          // File picker card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withOpacity(0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary
                            .withOpacity(0.10),
                        borderRadius:
                            BorderRadius.circular(
                                14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.insert_drive_file_rounded,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Choose CSV File',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                          Text(
                            _pickedCsv == null
                                ? 'No file selected'
                                : '${_pickedCsv!.name} • ${(_pickedCsv!.size / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors
                                  .grey.shade700,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed:
                          _uploading ? null : _pickCsv,
                      icon: const Icon(
                          Icons.folder_open_rounded),
                      label: const Text('Browse'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors
                            .grey.shade900,
                        side: BorderSide(
                          color: Colors
                              .grey.shade300,
                        ),
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                                  14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed:
                      _uploading ? null : _uploadCsv,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.cloud_upload_rounded),
                  label: Text(
                    _uploading
                        ? 'Uploading...'
                        : 'Upload to Server',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                              14),
                    ),
                  ),
                ),

                if (_uploadError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red
                          .withOpacity(0.06),
                      borderRadius:
                          BorderRadius.circular(
                              14),
                      border: Border.all(
                        color: Colors.red
                            .withOpacity(0.25),
                      ),
                    ),
                    child: Text(
                      _uploadError!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight:
                            FontWeight.w700,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],

                if (_uploadResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(
                              0xFF10B981)
                          .withOpacity(0.06),
                      borderRadius:
                          BorderRadius.circular(
                              14),
                      border: Border.all(
                        color: const Color(
                                0xFF10B981)
                            .withOpacity(0.25),
                      ),
                    ),
                    child: Text(
                      jsonEncode(_uploadResult),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight:
                            FontWeight.w700,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teachersTab({required Color primary}) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withOpacity(0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration:
                        const InputDecoration(
                      hintText:
                          'Search teacherid, name, email, phone...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searchCtrl.text
                    .trim()
                    .isNotEmpty)
                  InkWell(
                    borderRadius:
                        BorderRadius.circular(
                            999),
                    onTap: () {
                      _searchCtrl.clear();
                      _offset = 0;
                      _fetchTeachers();
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors
                            .grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors
                              .grey.shade200,
                        ),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors
                            .grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        Expanded(
          child: _listLoading
              ? ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(
                          18, 0, 18, 18),
                  itemCount: 8,
                  itemBuilder: (_, __) =>
                      _skeletonRow(),
                )
              : (_listError != null)
                  ? SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(
                              18, 0, 18, 18),
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.all(
                                14),
                        decoration:
                            BoxDecoration(
                          color: Colors.red
                              .withOpacity(0.06),
                          borderRadius:
                              BorderRadius
                                  .circular(
                                      16),
                          border: Border.all(
                            color: Colors.red
                                .withOpacity(
                                    0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            const Text(
                              'Error',
                              style:
                                  TextStyle(
                                fontSize:
                                    14,
                                fontWeight:
                                    FontWeight
                                        .w900,
                                color: Colors
                                    .redAccent,
                              ),
                            ),
                            const SizedBox(
                                height: 6),
                            Text(
                              _listError!,
                              style:
                                  const TextStyle(
                                fontSize:
                                    12,
                                fontWeight:
                                    FontWeight
                                        .w700,
                                color: Colors
                                    .redAccent,
                              ),
                            ),
                            const SizedBox(
                                height: 12),
                            ElevatedButton
                                .icon(
                              onPressed:
                                  _fetchTeachers,
                              icon: const Icon(
                                  Icons
                                      .refresh_rounded),
                              label: const Text(
                                  'Retry'),
                              style: ElevatedButton
                                  .styleFrom(
                                backgroundColor:
                                    primary,
                                foregroundColor:
                                    Colors
                                        .white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets
                                            .symmetric(
                                      horizontal:
                                          14,
                                      vertical:
                                          12,
                                    ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                              14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh:
                          _fetchTeachers,
                      child: ListView(
                        padding:
                            const EdgeInsets
                                    .fromLTRB(
                                18, 0, 18, 18),
                        children: [
                          Row(
                            children: [
                              _pill(
                                icon: Icons
                                    .list_alt_rounded,
                                label:
                                    'Total: $_total',
                                color:
                                    const Color(
                                        0xFF2563EB),
                              ),
                              const SizedBox(
                                  width: 10),
                              _pill(
                                icon: Icons
                                    .link_rounded,
                                label:
                                    'API: $_teacherBaseUrl',
                                color:
                                    const Color(
                                        0xFF7C3AED),
                              ),
                            ],
                          ),
                          const SizedBox(
                              height: 12),

                          if (_rows.isEmpty)
                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets
                                          .all(
                                      16),
                              decoration:
                                  BoxDecoration(
                                color: Colors
                                    .white,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                            16),
                                border: Border.all(
                                  color: Colors
                                      .grey
                                      .shade200,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons
                                        .inbox_rounded,
                                    size: 34,
                                    color: Colors
                                        .grey
                                        .shade500,
                                  ),
                                  const SizedBox(
                                      height:
                                          8),
                                  Text(
                                    'No teachers found',
                                    style:
                                        TextStyle(
                                      fontSize:
                                          13,
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                      color: Colors
                                          .grey
                                          .shade800,
                                    ),
                                  ),
                                  const SizedBox(
                                      height:
                                          4),
                                  Text(
                                    'Upload CSV from Bulk Upload tab.',
                                    style:
                                        TextStyle(
                                      fontSize:
                                          12,
                                      color: Colors
                                          .grey
                                          .shade600,
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          ..._rows.map(
                            (r) => _TeacherCard(
                              row: r,
                              onEdit: () =>
                                  _openEditTeacher(
                                      r),
                              onDelete: () =>
                                  _deleteTeacher(
                                      _s(r['teacherid'])),
                            ),
                          ),

                          const SizedBox(
                              height: 10),
                          _paginationBar(
                              primary:
                                  primary),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _paginationBar({required Color primary}) {
    final canPrev = _offset > 0;
    final canNext = (_offset + _limit) < _total;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canPrev
                ? () {
                    setState(() {
                      _offset = (_offset - _limit)
                          .clamp(0, 1 << 30);
                    });
                    _fetchTeachers();
                  }
                : null,
            icon:
                const Icon(Icons.chevron_left_rounded),
            label: const Text('Prev'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  Colors.grey.shade900,
              side: BorderSide(
                color: Colors.grey.shade300,
              ),
              padding:
                  const EdgeInsets.symmetric(
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canNext
                ? () {
                    setState(() {
                      _offset = _offset + _limit;
                    });
                    _fetchTeachers();
                  }
                : null,
            icon: const Icon(
                Icons.chevron_right_rounded),
            label: const Text('Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonRow() {
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius:
                  BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Container(
                  height: 10,
                  width: 220,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 160,
                  color: Colors.grey.shade200,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 22,
            width: 70,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius:
                  BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors
                        .grey.shade700,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

// ============================ TEACHER CARD ============================
class _TeacherCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TeacherCard({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final id = _s(row['teacherid']);
    final name = _s(row['teachername']);
    final email = _s(row['teacheremailid']);
    final mob = _s(row['teachermob1']);
    final desig = _s(row['teacherdesig']);
    final dept = _s(row['teacher_dept_id']);

    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 7,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB)
                  .withOpacity(0.10),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unknown' : name,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ID: $id  •  ${desig.isEmpty ? '—' : desig}  •  Dept: ${dept.isEmpty ? '—' : dept}',
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors
                        .grey.shade700,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${mob.isEmpty ? '' : mob}  ${email.isEmpty ? '' : '• $email'}',
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors
                        .grey.shade700,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onEdit,
            borderRadius:
                BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED)
                    .withOpacity(0.08),
                borderRadius:
                    BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(
                          0xFF7C3AED)
                      .withOpacity(0.18),
                ),
              ),
              child: const Icon(
                Icons.edit_rounded,
                size: 18,
                color: Color(0xFF7C3AED),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onDelete,
            borderRadius:
                BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444)
                    .withOpacity(0.08),
                borderRadius:
                    BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(
                          0xFFEF4444)
                      .withOpacity(0.18),
                ),
              ),
              child: const Icon(
                Icons.delete_rounded,
                size: 18,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ EDIT DIALOG ============================
class _TeacherEditDialog extends StatefulWidget {
  final String teacherid;

  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController mobCtrl;
  final TextEditingController addrCtrl;
  final TextEditingController desigCtrl;
  final TextEditingController collegeCtrl;
  final TextEditingController deptCtrl;
  final TextEditingController validCtrl;

  final Future<void> Function() onSave;

  const _TeacherEditDialog({
    required this.teacherid,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.mobCtrl,
    required this.addrCtrl,
    required this.desigCtrl,
    required this.collegeCtrl,
    required this.deptCtrl,
    required this.validCtrl,
    required this.onSave,
  });

  @override
  State<_TeacherEditDialog> createState() =>
      _TeacherEditDialogState();
}

class _TeacherEditDialogState
    extends State<_TeacherEditDialog> {
  bool _saving = false;

  Widget _field({
    required IconData icon,
    required String label,
    required TextEditingController ctrl,
    String hint = '',
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade200,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w800,
                    color: Colors
                        .grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: ctrl,
                  maxLines: maxLines,
                  decoration:
                      InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors
                          .grey.shade500,
                      fontSize: 12,
                      fontWeight:
                          FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w700,
                  ),
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
    const primary = Color(0xFF2563EB);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(22),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withOpacity(0.10),
              blurRadius: 28,
              offset: const Offset(0, 18),
            )
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primary
                          .withOpacity(0.10),
                      borderRadius:
                          BorderRadius.circular(
                              14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'Edit Teacher',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Teacher ID: ${widget.teacherid}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors
                                .grey.shade600,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius:
                        BorderRadius.circular(
                            999),
                    onTap: _saving
                        ? null
                        : () =>
                            Navigator.pop(
                                context,
                                false),
                    child: Container(
                      padding:
                          const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors
                            .grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors
                              .grey.shade200,
                        ),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors
                            .grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _field(
                icon: Icons.person_rounded,
                label: 'Name',
                ctrl: widget.nameCtrl,
                hint: 'Teacher name',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.email_rounded,
                label: 'Email',
                ctrl: widget.emailCtrl,
                hint: 'Email address',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.call_rounded,
                label: 'Mobile',
                ctrl: widget.mobCtrl,
                hint: 'Primary mobile',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.badge_rounded,
                label: 'Designation',
                ctrl: widget.desigCtrl,
                hint: 'e.g. Assistant Prof',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.apartment_rounded,
                label: 'College ID',
                ctrl: widget.collegeCtrl,
                hint: 'teachercollegeid',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.account_tree_rounded,
                label: 'Dept ID',
                ctrl: widget.deptCtrl,
                hint: 'teacher_dept_id',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.check_circle_rounded,
                label: 'Valid (text)',
                ctrl: widget.validCtrl,
                hint: 'true/false or 1/0',
              ),
              const SizedBox(height: 10),
              _field(
                icon: Icons.home_rounded,
                label: 'Address',
                ctrl: widget.addrCtrl,
                hint: 'Address',
                maxLines: 2,
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(
                              context, false),
                      icon: const Icon(
                          Icons.close_rounded),
                      label: const Text('Cancel'),
                      style: OutlinedButton
                          .styleFrom(
                        foregroundColor: Colors
                            .grey.shade800,
                        side: BorderSide(
                          color: Colors
                              .grey.shade300,
                        ),
                        padding:
                            const EdgeInsets
                                    .symmetric(
                          vertical: 12,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() =>
                                  _saving =
                                      true);
                              try {
                                await widget
                                    .onSave();
                              } finally {
                                if (mounted) {
                                  setState(() =>
                                      _saving =
                                          false);
                                }
                              }
                            },
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors
                                    .white,
                              ),
                            )
                          : const Icon(
                              Icons.save_rounded,
                            ),
                      label: const Text(
                          'Update'),
                      style: ElevatedButton
                          .styleFrom(
                        backgroundColor:
                            primary,
                        foregroundColor:
                            Colors.white,
                        elevation: 0,
                        padding:
                            const EdgeInsets
                                    .symmetric(
                          vertical: 12,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                                      14),
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
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withOpacity(0.10),
              blurRadius: 28,
              offset: const Offset(0, 18),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(
                            context, false),
                    style: OutlinedButton
                        .styleFrom(
                      side: BorderSide(
                        color: Colors
                            .grey.shade300,
                      ),
                      foregroundColor:
                          Colors
                              .grey.shade800,
                      padding:
                          const EdgeInsets
                                  .symmetric(
                        vertical: 12,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                                    14),
                      ),
                    ),
                    child: const Text(
                        'Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(
                            context, true),
                    style: ElevatedButton
                        .styleFrom(
                      backgroundColor:
                          confirmColor,
                      foregroundColor:
                          Colors.white,
                      elevation: 0,
                      padding:
                          const EdgeInsets
                                  .symmetric(
                        vertical: 12,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                                    14),
                      ),
                    ),
                    child: Text(
                      confirmText,
                    ),
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

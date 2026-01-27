// lib/pages/master_classroom.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// ----------------- ENV + API CONFIG -----------------
class AppConfig {
  static String get baseUrl {
    final v = dotenv.env['BASE_URL'] ?? '';
    if (v.trim().isNotEmpty) return v.trim();
    return 'https://poweranger-turbo.onrender.com'; // fallback
  }

  static String get apiPrefix {
    final v = dotenv.env['API_PREFIX'] ?? '';
    if (v.trim().isNotEmpty) return v.trim(); // e.g. /api
    return '/api';
  }
}

class Api {
  static String get baseUrl => AppConfig.baseUrl;
  static String get apiPrefix => AppConfig.apiPrefix;

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  // ✅ requested by you
  static String get classRoom => _join(baseUrl, '$apiPrefix/class-room');

  static String classRoomById(String classroomid) =>
      _join(baseUrl, '$apiPrefix/class-room/$classroomid');
}

/// ----------------- MODEL -----------------
class Classroom {
  final String classroomid;
  final String? classroomcollege;
  final String? classroomdept;
  final String? classroomcode;
  final String classroomname;
  final String? classroomtype;
  final int? classroomcapacity;
  final bool? classroomisavailable;
  final bool? classroomprojector;
  final int? classfloornumber;
  final double? classroomlat;
  final double? classroomlong;
  final String? classroomloc;

  Classroom({
    required this.classroomid,
    required this.classroomname,
    this.classroomcollege,
    this.classroomdept,
    this.classroomcode,
    this.classroomtype,
    this.classroomcapacity,
    this.classroomisavailable,
    this.classroomprojector,
    this.classfloornumber,
    this.classroomlat,
    this.classroomlong,
    this.classroomloc,
  });

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
    return null;
  }

  factory Classroom.fromJson(Map<String, dynamic> j) {
    return Classroom(
      classroomid: (j['classroomid'] ?? '').toString(),
      classroomname: (j['classroomname'] ?? '').toString(),
      classroomcollege: j['classroomcollege']?.toString(),
      classroomdept: j['classroomdept']?.toString(),
      classroomcode: j['classroomcode']?.toString(),
      classroomtype: j['classroomtype']?.toString(),
      classroomcapacity: _toInt(j['classroomcapacity']),
      classroomisavailable: _toBool(j['classroomisavailable']),
      classroomprojector: _toBool(j['classroomprojector']),
      classfloornumber: _toInt(j['classfloornumber']),
      classroomlat: _toDouble(j['classroomlat']),
      classroomlong: _toDouble(j['classroomlong']),
      classroomloc: j['classroomloc']?.toString(),
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'classroomid': classroomid,
      'classroomcollege': classroomcollege,
      'classroomdept': classroomdept,
      'classroomcode': classroomcode,
      'classroomname': classroomname,
      'classroomtype': classroomtype,
      'classroomcapacity': classroomcapacity,
      'classroomisavailable': classroomisavailable,
      'classroomprojector': classroomprojector,
      'classfloornumber': classfloornumber,
      'classroomlat': classroomlat,
      'classroomlong': classroomlong,
      'classroomloc': classroomloc,
    };
  }
}

/// ----------------- UI PAGE -----------------
class MasterClassroomPage extends StatefulWidget {
  const MasterClassroomPage({super.key});

  @override
  State<MasterClassroomPage> createState() => _MasterClassroomPageState();
}

class _MasterClassroomPageState extends State<MasterClassroomPage> {
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Classroom> _all = [];
  List<Classroom> _filtered = [];

  @override
  void initState() {
    super.initState();
    _fetch();
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Classroom>.from(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((c) {
        final hay = [
          c.classroomid,
          c.classroomname,
          c.classroomcode ?? '',
          c.classroomtype ?? '',
          c.classroomdept ?? '',
          c.classroomcollege ?? '',
          c.classroomloc ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    });
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(Api.classRoom); // GET /api/class-room
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        List<dynamic> rows = [];

        // Your API returns: { classrooms: [...] }
        if (decoded is Map && decoded['classrooms'] is List) {
          rows = decoded['classrooms'];
        } else if (decoded is List) {
          rows = decoded;
        }

        final list = rows
            .whereType<Map>()
            .map((m) => Classroom.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        setState(() {
          _all = list;
          _filtered = List<Classroom>.from(list);
        });
      } else {
        setState(() => _error = 'HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      setState(() => _error = 'Failed to load classrooms: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String classroomid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete classroom?'),
        content: Text('This will delete classroom: $classroomid'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final uri = Uri.parse(Api.classRoomById(classroomid));
      final resp = await http.delete(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Classroom deleted'), behavior: SnackBarBehavior.floating),
        );
        _fetch();
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
        SnackBar(content: Text('Delete error: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _openEditor({Classroom? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClassroomEditorSheet(
        existing: existing,
        onSaved: () => _fetch(),
      ),
    );
  }

  // Tailwind-ish tokens
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _primary = Color(0xFF2563EB);
  static const Color _card = Colors.white;
  static const Color _muted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Master Classroom'),
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: Colors.black,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Classroom'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetch,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
            children: [
              // Header card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.meeting_room_rounded, color: _primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Classrooms',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'API: ${Api.classRoom}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_filtered.length}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Search bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search by id / name / code / type / dept / college...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (_loading) ...[
                _skeletonList(),
              ] else if (_error != null) ...[
                _errorCard(_error!, onRetry: _fetch),
              ] else if (_filtered.isEmpty) ...[
                _emptyCard(),
              ] else ...[
                ..._filtered.map((c) => _classroomCard(c)).toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _classroomCard(Classroom c) {
    final available = c.classroomisavailable == true;
    final projector = c.classroomprojector == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.class_rounded, color: _primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.classroomname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${c.classroomid}${(c.classroomcode ?? '').trim().isEmpty ? '' : ' • Code: ${c.classroomcode}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    if (v == 'edit') _openEditor(existing: c);
                    if (v == 'delete') _delete(c.classroomid);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                )
              ],
            ),

            const SizedBox(height: 12),

            // Tags (Tailwind-ish pills)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  icon: available ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  text: available ? 'Available' : 'Not Available',
                  color: available ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
                ),
                _pill(
                  icon: projector ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  text: projector ? 'Projector' : 'No Projector',
                  color: projector ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                ),
                if ((c.classroomtype ?? '').trim().isNotEmpty)
                  _pill(
                    icon: Icons.category_rounded,
                    text: c.classroomtype!,
                    color: const Color(0xFF7C3AED),
                  ),
                if (c.classroomcapacity != null)
                  _pill(
                    icon: Icons.people_alt_rounded,
                    text: 'Cap: ${c.classroomcapacity}',
                    color: const Color(0xFFF97316),
                  ),
                if (c.classfloornumber != null)
                  _pill(
                    icon: Icons.layers_rounded,
                    text: 'Floor: ${c.classfloornumber}',
                    color: const Color(0xFF0EA5E9),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Details grid
            _kvRow(Icons.account_balance_rounded, 'College', c.classroomcollege),
            _kvRow(Icons.apartment_rounded, 'Department', c.classroomdept),
            _kvRow(Icons.place_rounded, 'Location', c.classroomloc),
            if (c.classroomlat != null || c.classroomlong != null)
              _kvRow(
                Icons.my_location_rounded,
                'Geo',
                '${c.classroomlat ?? '-'}, ${c.classroomlong ?? '-'}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(IconData icon, String k, String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(
              k,
              style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String msg, {required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Failed to load', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Row(
        children: [
          Icon(Icons.inbox_rounded, color: Color(0xFF64748B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No classrooms found.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonList() {
    Widget skel() => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
        );

    return Column(
      children: List.generate(6, (_) => skel()),
    );
  }
}

/// ----------------- EDITOR SHEET -----------------
class _ClassroomEditorSheet extends StatefulWidget {
  final Classroom? existing;
  final VoidCallback onSaved;

  const _ClassroomEditorSheet({required this.existing, required this.onSaved});

  @override
  State<_ClassroomEditorSheet> createState() => _ClassroomEditorSheetState();
}

class _ClassroomEditorSheetState extends State<_ClassroomEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  late final TextEditingController idCtrl;
  late final TextEditingController collegeCtrl;
  late final TextEditingController deptCtrl;
  late final TextEditingController codeCtrl;
  late final TextEditingController nameCtrl;
  late final TextEditingController typeCtrl;
  late final TextEditingController capCtrl;
  late final TextEditingController floorCtrl;
  late final TextEditingController latCtrl;
  late final TextEditingController longCtrl;
  late final TextEditingController locCtrl;

  bool isAvailable = true;
  bool hasProjector = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    idCtrl = TextEditingController(text: e?.classroomid ?? '');
    collegeCtrl = TextEditingController(text: e?.classroomcollege ?? '');
    deptCtrl = TextEditingController(text: e?.classroomdept ?? '');
    codeCtrl = TextEditingController(text: e?.classroomcode ?? '');
    nameCtrl = TextEditingController(text: e?.classroomname ?? '');
    typeCtrl = TextEditingController(text: e?.classroomtype ?? '');
    capCtrl = TextEditingController(text: e?.classroomcapacity?.toString() ?? '');
    floorCtrl = TextEditingController(text: e?.classfloornumber?.toString() ?? '');
    latCtrl = TextEditingController(text: e?.classroomlat?.toString() ?? '');
    longCtrl = TextEditingController(text: e?.classroomlong?.toString() ?? '');
    locCtrl = TextEditingController(text: e?.classroomloc ?? '');

    isAvailable = e?.classroomisavailable ?? true;
    hasProjector = e?.classroomprojector ?? false;
  }

  @override
  void dispose() {
    idCtrl.dispose();
    collegeCtrl.dispose();
    deptCtrl.dispose();
    codeCtrl.dispose();
    nameCtrl.dispose();
    typeCtrl.dispose();
    capCtrl.dispose();
    floorCtrl.dispose();
    latCtrl.dispose();
    longCtrl.dispose();
    locCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  double? _parseDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = {
      'classroomid': idCtrl.text.trim(),
      'classroomcollege': collegeCtrl.text.trim().isEmpty ? null : collegeCtrl.text.trim(),
      'classroomdept': deptCtrl.text.trim().isEmpty ? null : deptCtrl.text.trim(),
      'classroomcode': codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
      'classroomname': nameCtrl.text.trim(),
      'classroomtype': typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
      'classroomcapacity': _parseInt(capCtrl.text),
      'classroomisavailable': isAvailable,
      'classroomprojector': hasProjector,
      'classfloornumber': _parseInt(floorCtrl.text),
      'classroomlat': _parseDouble(latCtrl.text),
      'classroomlong': _parseDouble(longCtrl.text),
      'classroomloc': locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
    };

    try {
      final isEdit = widget.existing != null;
      final uri = Uri.parse(isEdit ? Api.classRoomById(widget.existing!.classroomid) : Api.classRoom);

      final resp = await (isEdit
              ? http.put(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
              : http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (!mounted) return;
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Classroom updated' : 'Classroom added'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _error = 'HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const Color _primary = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Container(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(isEdit ? Icons.edit_rounded : Icons.add_rounded, color: _primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEdit ? 'Edit Classroom' : 'Add Classroom',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
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
                    const SizedBox(height: 10),
                  ],

                  // Row: ID + Name
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: idCtrl,
                          label: 'Classroom ID *',
                          icon: Icons.badge_rounded,
                          enabled: !isEdit, // ID fixed on edit (matches PUT /:id)
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'Required';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          controller: nameCtrl,
                          label: 'Name *',
                          icon: Icons.class_rounded,
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'Required';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Row: Code + Type
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: codeCtrl,
                          label: 'Code',
                          icon: Icons.qr_code_2_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          controller: typeCtrl,
                          label: 'Type',
                          icon: Icons.category_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Row: College + Dept
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: collegeCtrl,
                          label: 'College',
                          icon: Icons.account_balance_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          controller: deptCtrl,
                          label: 'Department',
                          icon: Icons.apartment_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Row: Capacity + Floor
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: capCtrl,
                          label: 'Capacity',
                          icon: Icons.people_alt_rounded,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          controller: floorCtrl,
                          label: 'Floor No.',
                          icon: Icons.layers_rounded,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Geo
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: latCtrl,
                          label: 'Latitude',
                          icon: Icons.my_location_rounded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          controller: longCtrl,
                          label: 'Longitude',
                          icon: Icons.explore_rounded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  _field(
                    controller: locCtrl,
                    label: 'Location / Room Info',
                    icon: Icons.place_rounded,
                  ),

                  const SizedBox(height: 12),

                  // Switches
                  Row(
                    children: [
                      Expanded(
                        child: _switchTile(
                          icon: Icons.check_circle_rounded,
                          title: 'Available',
                          value: isAvailable,
                          onChanged: _saving ? null : (v) => setState(() => isAvailable = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _switchTile(
                          icon: Icons.videocam_rounded,
                          title: 'Projector',
                          value: hasProjector,
                          onChanged: _saving ? null : (v) => setState(() => hasProjector = v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        elevation: 6,
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : Icon(isEdit ? Icons.save_rounded : Icons.add_rounded),
                      label: Text(isEdit ? 'Update Classroom' : 'Add Classroom'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primary, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF334155)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _primary,
          ),
        ],
      ),
    );
  }
}

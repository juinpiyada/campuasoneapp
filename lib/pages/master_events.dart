// lib/pages/master_events.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_endpoints.dart';

class MasterEventsPage extends StatefulWidget {
  const MasterEventsPage({super.key});

  @override
  State<MasterEventsPage> createState() => _MasterEventsPageState();
}

class _MasterEventsPageState extends State<MasterEventsPage>
    with TickerProviderStateMixin {
  // ---------------- Endpoint ----------------
  String get _base => ApiEndpoints.events;
  String get _addUrl => '$_base/add-event';
  String get _listUrl => '$_base/view-events';
  String _viewUrl(dynamic id) => '$_base/view-event/$id';
  String _editUrl(dynamic id) => '$_base/edit-event/$id';
  String _deleteUrl(dynamic id) => '$_base/delete-event/$id';

  // ---------------- List state ----------------
  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  // ---------------- Modal state ----------------
  bool _saving = false;
  String? _modalError;

  // ---------------- Form controllers ----------------
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // optional base64 fields
  final _photoB64Ctrl = TextEditingController();
  final _imageB64Ctrl = TextEditingController();
  final _pdfB64Ctrl = TextEditingController();

  // event time (strings)
  final _fromCtrl = TextEditingController(); // yyyy-mm-dd (to match React)
  final _toCtrl = TextEditingController(); // yyyy-mm-dd (to match React)

  // ---------------- Animations ----------------
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

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
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();

    _titleCtrl.dispose();
    _descCtrl.dispose();
    _photoB64Ctrl.dispose();
    _imageB64Ctrl.dispose();
    _pdfB64Ctrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();

    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ---------------- Helpers ----------------
  String _s(dynamic v) => (v ?? '').toString();
  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // Prefer date-only (YYYY-MM-DD), same as React UI
  String _dateOnly(String raw) {
    if (raw.trim().isEmpty) return '';
    // If already yyyy-mm-dd, return as-is
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (re.hasMatch(raw)) return raw;
    // Try parse ISO/datetime and extract date
    try {
      final d = DateTime.parse(raw);
      final yyyy = d.year.toString().padLeft(4, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    } catch (_) {
      return raw; // let server decide if non-date string arrives
    }
  }

  // Extract a usable id for /:id routes
  dynamic _rowId(Map<String, dynamic> r) {
    final candidates = [r['id'], r['eventid'], r['event_id'], r['uuid']];
    for (final c in candidates) {
      if (c == null) continue;
      final s = c.toString().trim();
      if (s.isEmpty) continue;
      final n = int.tryParse(s);
      return n ?? s;
    }
    return null;
  }

  Future<Map<String, String>> _authHeaders({bool json = true}) async {
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
      if (json) 'Content-Type': 'application/json',
      // Some proxies check this for XHR semantics
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    return headers;
  }

  Uint8List? _tryDecodeBase64Image(String raw) {
    try {
      final s = raw.trim();
      if (s.isEmpty) return null;
      final idx = s.indexOf('base64,');
      final b64 = (idx >= 0) ? s.substring(idx + 7) : s;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  // ---------------- Search ----------------
  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
      return;
    }

    setState(() {
      _filtered = _all.where((r) {
        final hay = [
          _s(_rowId(r)),
          _s(r['title']),
          _s(r['description']),
          _s(r['event_from']),
          _s(r['event_to']),
          _s(r['created_at']),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    });
  }

  // ---------------- API: List ----------------
  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final headers = await _authHeaders();
      final resp = await http
          .get(Uri.parse(_listUrl), headers: headers)
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final events = (decoded is Map && decoded['events'] is List)
            ? decoded['events'] as List
            : <dynamic>[];

        _all = events.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _filtered = List<Map<String, dynamic>>.from(_all);
      } else if (resp.statusCode == 404) {
        _all = [];
        _filtered = [];
      } else {
        _error = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } on TimeoutException {
      _error = 'Timeout: events list did not respond in time.';
    } catch (e) {
      _error = 'Failed to load events: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // Build a payload that covers both snake_case and camelCase keys
  Map<String, dynamic> _buildDualCasePayload({
    required String title,
    required String description,
    required String eventFrom,
    required String eventTo,
    String? photoBase64,
    String? imageBase64,
    String? pdfBase64,
  }) {
    final from = _dateOnly(eventFrom);
    final to = _dateOnly(eventTo);

    final out = <String, dynamic>{
      // snake_case
      "title": title,
      "description": description,
      "event_from": from,
      "event_to": to,
      if ((photoBase64 ?? '').trim().isNotEmpty)
        "photo_base64": photoBase64!.trim(),
      if ((imageBase64 ?? '').trim().isNotEmpty)
        "image_base64": imageBase64!.trim(),
      if ((pdfBase64 ?? '').trim().isNotEmpty) "pdf_base64": pdfBase64!.trim(),

      // camelCase mirrors
      "eventFrom": from,
      "eventTo": to,
    };

    // optional camel mirrors for attachments
    if ((photoBase64 ?? '').trim().isNotEmpty) {
      out["photoBase64"] = photoBase64!.trim();
    }
    if ((imageBase64 ?? '').trim().isNotEmpty) {
      out["imageBase64"] = imageBase64!.trim();
    }
    if ((pdfBase64 ?? '').trim().isNotEmpty) {
      out["pdfBase64"] = pdfBase64!.trim();
    }

    return out;
  }

  // ---------------- API: Create ----------------
  Future<void> _create() async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final title = _titleCtrl.text.trim();
      final desc = _descCtrl.text.trim();
      final from = _fromCtrl.text.trim();
      final to = _toCtrl.text.trim();

      if (title.isEmpty || desc.isEmpty || from.isEmpty || to.isEmpty) {
        throw Exception('Required: title, description, event_from, event_to');
      }

      final body = _buildDualCasePayload(
        title: title,
        description: desc,
        eventFrom: from,
        eventTo: to,
        photoBase64: _photoB64Ctrl.text.trim(),
        imageBase64: _imageB64Ctrl.text.trim(),
        pdfBase64: _pdfB64Ctrl.text.trim(),
      );

      final headers = await _authHeaders();
      http.Response resp;
      try {
        resp = await http
            .post(Uri.parse(_addUrl),
                headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 25));
      } on TimeoutException {
        throw Exception('Timeout: add-event did not respond in time.');
      }

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        await _fetchAll();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _modalError =
            'Create failed (HTTP ${resp.statusCode}): ${resp.body.isEmpty ? "(empty)" : resp.body}';
      }
    } catch (e) {
      _modalError = e.toString();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ---------------- API: Update ----------------
  Future<void> _update(dynamic id) async {
    setState(() {
      _saving = true;
      _modalError = null;
    });

    try {
      final title = _titleCtrl.text.trim();
      final desc = _descCtrl.text.trim();
      final from = _fromCtrl.text.trim();
      final to = _toCtrl.text.trim();

      if (title.isEmpty || desc.isEmpty || from.isEmpty || to.isEmpty) {
        throw Exception('Required: title, description, event_from, event_to');
      }

      final body = _buildDualCasePayload(
        title: title,
        description: desc,
        eventFrom: from,
        eventTo: to,
        photoBase64: _photoB64Ctrl.text.trim(),
        imageBase64: _imageB64Ctrl.text.trim(),
        pdfBase64: _pdfB64Ctrl.text.trim(),
      );

      final baseHeaders = await _authHeaders();
      http.Response resp;
      try {
        // Try PUT first
        resp = await http
            .put(Uri.parse(_editUrl(id)),
                headers: baseHeaders, body: jsonEncode(body))
            .timeout(const Duration(seconds: 25));

        // Some servers don’t allow PUT; fallback to POST (same path) with method override
        if (resp.statusCode == 404 ||
            resp.statusCode == 405 ||
            resp.statusCode == 501) {
          final headers = Map<String, String>.from(baseHeaders)
            ..['X-HTTP-Method-Override'] = 'PUT';
          resp = await http
              .post(Uri.parse(_editUrl(id)),
                  headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 25));
        }
      } on TimeoutException {
        throw Exception('Timeout: edit-event did not respond in time.');
      }

      if (resp.statusCode == 200) {
        await _fetchAll();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _modalError =
            'Update failed (HTTP ${resp.statusCode}): ${resp.body.isEmpty ? "(empty)" : resp.body}';
      }
    } catch (e) {
      _modalError = e.toString();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  // ---------------- API: Delete ----------------
  Future<void> _delete(dynamic id) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ConfirmDialog(
        title: 'Delete Event?',
        message: 'This will permanently delete the selected event.',
        confirmText: 'Delete',
        confirmColor: Color(0xFFEF4444),
      ),
    );
    if (ok != true) return;

    try {
      final baseHeaders = await _authHeaders(json: false);
      http.Response resp;
      try {
        // DELETE first
        final headers = Map<String, String>.from(baseHeaders)
          ..['Accept'] = 'application/json';
        resp = await http
            .delete(Uri.parse(_deleteUrl(id)), headers: headers)
            .timeout(const Duration(seconds: 25));

        // Fallback: POST + override (and include id body for Express validators/middlewares)
        if (resp.statusCode == 404 ||
            resp.statusCode == 405 ||
            resp.statusCode == 501) {
          final headers2 = await _authHeaders(); // with Content-Type json
          headers2['X-HTTP-Method-Override'] = 'DELETE';
          resp = await http
              .post(Uri.parse(_deleteUrl(id)),
                  headers: headers2, body: jsonEncode({"id": id}))
              .timeout(const Duration(seconds: 25));
        }
      } on TimeoutException {
        _toast('Timeout while deleting.');
        return;
      }

      if (resp.statusCode == 200) {
        await _fetchAll();
      } else {
        _toast(
            'Delete failed (HTTP ${resp.statusCode}): ${resp.body.isEmpty ? "(empty)" : resp.body}');
      }
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  // ---------------- Modal helpers ----------------
  void _resetForm() {
    _modalError = null;

    _titleCtrl.clear();
    _descCtrl.clear();
    _photoB64Ctrl.clear();
    _imageB64Ctrl.clear();
    _pdfB64Ctrl.clear();
    _fromCtrl.clear();
    _toCtrl.clear();
  }

  Future<void> _prefillForEdit(dynamic id) async {
    setState(() {
      _modalError = null;
      _saving = true;
    });

    try {
      final headers = await _authHeaders();
      final resp = await http
          .get(Uri.parse(_viewUrl(id)), headers: headers)
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final ev = (decoded is Map && decoded['event'] is Map)
            ? Map<String, dynamic>.from(decoded['event'] as Map)
            : <String, dynamic>{};

        _titleCtrl.text = _s(ev['title']);
        _descCtrl.text = _s(ev['description']);

        // attachments (snake or camel)
        final photo = _s(
            ev['photo_base64'] ?? ev['photoBase64'] ?? '');
        final image = _s(
            ev['image_base64'] ?? ev['imageBase64'] ?? '');
        final pdf = _s(ev['pdf_base64'] ?? ev['pdfBase64'] ?? '');

        _photoB64Ctrl.text = photo;
        _imageB64Ctrl.text = image;
        _pdfB64Ctrl.text = pdf;

        // dates (prefer date-only for inputs)
        final fromRaw = _s(ev['event_from'] ?? ev['eventFrom']);
        final toRaw = _s(ev['event_to'] ?? ev['eventTo']);
        _fromCtrl.text = _dateOnly(fromRaw);
        _toCtrl.text = _dateOnly(toRaw);
      } else {
        _modalError = 'Failed to load event: HTTP ${resp.statusCode}';
      }
    } on TimeoutException {
      _modalError = 'Timeout while loading event details.';
    } catch (e) {
      _modalError = 'Failed to load event: $e';
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _pickDateInto(TextEditingController ctrl) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (d == null) return;
    ctrl.text = _dateOnly(d.toIso8601String());
    if (mounted) setState(() {});
  }

  Future<void> _openAddModal() async {
    setState(_resetForm);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _EventModal(
        title: 'Add Event',
        subtitle: 'Create a new event',
        accent: const Color(0xFF2563EB),
        saving: _saving,
        errorText: _modalError,
        isEditing: false,
        titleCtrl: _titleCtrl,
        descCtrl: _descCtrl,
        photoB64Ctrl: _photoB64Ctrl,
        imageB64Ctrl: _imageB64Ctrl,
        pdfB64Ctrl: _pdfB64Ctrl,
        fromCtrl: _fromCtrl,
        toCtrl: _toCtrl,
        onPickFrom: () => _pickDateInto(_fromCtrl),
        onPickTo: () => _pickDateInto(_toCtrl),
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

  Future<void> _openEditModal(dynamic id) async {
    await _prefillForEdit(id);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _EventModal(
        title: 'Edit Event',
        subtitle: 'Event ID: $id',
        accent: const Color(0xFF7C3AED),
        saving: _saving,
        errorText: _modalError,
        isEditing: true,
        titleCtrl: _titleCtrl,
        descCtrl: _descCtrl,
        photoB64Ctrl: _photoB64Ctrl,
        imageB64Ctrl: _imageB64Ctrl,
        pdfB64Ctrl: _pdfB64Ctrl,
        fromCtrl: _fromCtrl,
        toCtrl: _toCtrl,
        onPickFrom: () => _pickDateInto(_fromCtrl),
        onPickTo: () => _pickDateInto(_toCtrl),
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

  // ---------------- UI bits ----------------
  Widget _pill(
      {required IconData icon, required String label, required Color color}) {
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
            style:
                TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 10,
                      width: 220,
                      color: Colors.white.withOpacity(0.6)),
                  const SizedBox(height: 8),
                  Container(
                      height: 10,
                      width: 160,
                      color: Colors.white.withOpacity(0.6)),
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

  // ---------------- Build ----------------
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
              // Top bar
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
                            'Events Manager',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w900),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: Colors.grey.shade600),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          decoration: const InputDecoration(
                            hintText: 'Search title, description, date, id...',
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

              // Body
              Expanded(
                child: _loading
                    ? ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        itemCount: 8,
                        itemBuilder: (_, __) => _skeletonRow(),
                      )
                    : (_error != null)
                        ? SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.25)),
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchAll,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 0, 18, 18),
                              children: [
                                Row(
                                  children: [
                                    _pill(
                                      icon: Icons.event_note_rounded,
                                      label: 'Total: ${_filtered.length}',
                                      color: const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 10),
                                    _pill(
                                      icon: Icons.link_rounded,
                                      label: 'API: /events',
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
                                      border: Border.all(
                                          color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.inbox_rounded,
                                            size: 34,
                                            color: Colors.grey.shade500),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No events found',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tap Add to create a new event.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ..._filtered.map((r) {
                                  final idAny = _rowId(r);
                                  return _EventCard(
                                    row: r,
                                    imageBytes: _tryDecodeBase64Image(
                                      _s(r['image_base64']).isNotEmpty
                                          ? _s(r['image_base64'])
                                          : _s(r['photo_base64']),
                                    ),
                                    onEdit: idAny == null
                                        ? () {}
                                        : () => _openEditModal(idAny),
                                    onDelete: idAny == null
                                        ? () {}
                                        : () => _delete(idAny),
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

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final Uint8List? imageBytes;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventCard({
    required this.row,
    required this.imageBytes,
    required this.onEdit,
    required this.onDelete,
  });

  String _s(dynamic v) => (v ?? '').toString();

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
                fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = _s(row['id']?.toString().isNotEmpty == true
        ? row['id']
        : (row['eventid'] ?? row['event_id'] ?? row['uuid']));
    final title = _s(row['title']);
    final desc = _s(row['description']);
    final from =
        _s(row['event_from']?.toString().isNotEmpty == true ? row['event_from'] : row['eventFrom']);
    final to =
        _s(row['event_to']?.toString().isNotEmpty == true ? row['event_to'] : row['eventTo']);
    final created = _s(row['created_at']);
    final hasPdf = _s(row['pdf_base64']).trim().isNotEmpty ||
        _s(row['pdfBase64']).trim().isNotEmpty;

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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: imageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(imageBytes!,
                            width: 40, height: 40, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.event_available_rounded,
                        color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Untitled Event' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${id.isEmpty ? "-" : id} • Created: ${created.isEmpty ? '-' : created}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w700),
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
                    border: Border.all(
                        color: const Color(0xFF7C3AED).withOpacity(0.18)),
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
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.18)),
                  ),
                  child: const Icon(Icons.delete_rounded,
                      size: 18, color: Color(0xFFEF4444)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (desc.isNotEmpty)
            Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                  height: 1.3),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (from.isNotEmpty)
                _tag(Icons.schedule_rounded, 'From: $from',
                    const Color(0xFF22C55E)),
              if (to.isNotEmpty)
                _tag(Icons.schedule_send_rounded, 'To: $to',
                    const Color(0xFFF97316)),
              _tag(
                  hasPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded,
                  hasPdf ? 'PDF attached' : 'No PDF',
                  hasPdf
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF64748B)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final bool saving;
  final String? errorText;
  final bool isEditing;

  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController photoB64Ctrl;
  final TextEditingController imageB64Ctrl;
  final TextEditingController pdfB64Ctrl;
  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;

  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _EventModal({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.saving,
    required this.errorText,
    required this.isEditing,
    required this.titleCtrl,
    required this.descCtrl,
    required this.photoB64Ctrl,
    required this.imageB64Ctrl,
    required this.pdfB64Ctrl,
    required this.fromCtrl,
    required this.toCtrl,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onCancel,
    required this.onSave,
  });

  Widget _input({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
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
                      color: Colors.grey.shade800),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  readOnly: readOnly,
                  onTap: onTap,
                  maxLines: maxLines,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
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
                        borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Icon(Icons.event_rounded, color: accent),
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
                    border:
                        Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(
                    errorText!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              _input(
                icon: Icons.title_rounded,
                label: 'Title *',
                hint: 'Enter event title',
                controller: titleCtrl,
              ),
              const SizedBox(height: 10),
              _input(
                icon: Icons.notes_rounded,
                label: 'Description *',
                hint: 'Enter description',
                controller: descCtrl,
                maxLines: 4,
              ),
              const SizedBox(height: 10),

              // from/to date pickers (date-only to mirror React)
              Row(
                children: [
                  Expanded(
                    child: _input(
                      icon: Icons.schedule_rounded,
                      label: 'Event From *',
                      hint: 'Pick date',
                      controller: fromCtrl,
                      readOnly: true,
                      onTap: onPickFrom,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      icon: Icons.schedule_send_rounded,
                      label: 'Event To *',
                      hint: 'Pick date',
                      controller: toCtrl,
                      readOnly: true,
                      onTap: onPickTo,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // base64 fields
              _input(
                icon: Icons.photo_rounded,
                label: 'Photo Base64 (optional)',
                hint: 'Paste base64 / data:image/...;base64,...',
                controller: photoB64Ctrl,
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _input(
                icon: Icons.image_rounded,
                label: 'Image Base64 (optional)',
                hint: 'Paste base64 / data:image/...;base64,...',
                controller: imageB64Ctrl,
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _input(
                icon: Icons.picture_as_pdf_rounded,
                label: 'PDF Base64 (optional)',
                hint: 'Paste base64 / data:application/pdf;base64,...',
                controller: pdfB64Ctrl,
                maxLines: 3,
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
                            borderRadius: BorderRadius.circular(14)),
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
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(isEditing ? 'Update' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600),
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
                          borderRadius: BorderRadius.circular(14)),
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
                          borderRadius: BorderRadius.circular(14)),
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

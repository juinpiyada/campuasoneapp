import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class MasterNoticeScreen extends StatefulWidget {
  const MasterNoticeScreen({super.key});

  @override
  State<MasterNoticeScreen> createState() => _MasterNoticeScreenState();
}

class _MasterNoticeScreenState extends State<MasterNoticeScreen>
    with SingleTickerProviderStateMixin {
  static const String apiBase =
      'https://poweranger-turbo.onrender.com/api/notices';

  // UI state
  bool loading = true;
  String? error;

  // Pagination
  int page = 1;
  int limit = 20;
  bool hasNext = false;
  int totalRecords = 0;

  // Search
  final TextEditingController searchCtrl = TextEditingController();
  String appliedSearch = '';

  // Data
  List<Map<String, dynamic>> notices = [];

  // Skeleton anim
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);

    _fetchNotices(goPage: 1);
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ----------------- API -----------------
  Future<void> _fetchNotices({int? goPage, String? search}) async {
    setState(() {
      loading = true;
      error = null;
    });

    final p = goPage ?? page;
    final s = (search ?? appliedSearch).trim();

    try {
      final uri = Uri.parse(apiBase).replace(queryParameters: {
        'page': p.toString(),
        'limit': limit.toString(),
        if (s.isNotEmpty) 'search': s,
      });

      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final data = (decoded is Map) ? decoded['data'] : null;
        final pag = (decoded is Map) ? decoded['pagination'] : null;

        final list = <Map<String, dynamic>>[];
        if (data is List) {
          for (final it in data) {
            if (it is Map) list.add(Map<String, dynamic>.from(it));
          }
        }

        setState(() {
          notices = list;
          page = p;
          appliedSearch = s;
          hasNext = (pag is Map) ? (pag['has_next'] == true) : false;
          totalRecords =
              (pag is Map) ? _safeInt(pag['total_records']) : list.length;
          loading = false;
        });
      } else {
        setState(() {
          loading = false;
          error = 'HTTP ${resp.statusCode}: ${resp.body}';
        });
      }
    } on TimeoutException {
      setState(() {
        loading = false;
        error = 'Timeout: API did not respond in time.';
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = 'Failed to load notices: $e';
      });
    }
  }

  Future<void> _createNotice({
    required String title,
    required String description,
    String? pdfBase64,
    String? imageBase64,
  }) async {
    final body = {
      'title': title.trim(),
      'description': description.trim(),
      'pdf_base64': (pdfBase64 ?? '').trim().isEmpty ? null : pdfBase64!.trim(),
      'image_base64':
          (imageBase64 ?? '').trim().isEmpty ? null : imageBase64!.trim(),
    };

    final resp = await http
        .post(
          Uri.parse(apiBase),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Create failed: HTTP ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> _updateNotice({
    required int id,
    required String title,
    required String description,
    String? pdfBase64,
    String? imageBase64,
  }) async {
    final body = {
      'title': title.trim(),
      'description': description.trim(),
      'pdf_base64': (pdfBase64 ?? '').trim().isEmpty ? null : pdfBase64!.trim(),
      'image_base64':
          (imageBase64 ?? '').trim().isEmpty ? null : imageBase64!.trim(),
    };

    final resp = await http
        .put(
          Uri.parse('$apiBase/$id'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));

    if (resp.statusCode != 200) {
      throw Exception('Update failed: HTTP ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> _deleteNotice(int id) async {
    final resp = await http
        .delete(Uri.parse('$apiBase/$id'))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('Delete failed: HTTP ${resp.statusCode} ${resp.body}');
    }
  }

  // ----------------- Helpers -----------------
  String _safeStr(dynamic v) => (v == null) ? '' : v.toString();

  int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_safeStr(v)) ?? 0;
  }

  DateTime? _parseDate(dynamic v) {
    final s = _safeStr(v).trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Uint8List? _decodeBase64Any(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;

    final comma = s.indexOf(',');
    if (s.startsWith('data:') && comma != -1) {
      s = s.substring(comma + 1);
    }

    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  String _guessImageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _prettyDate(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openPdfFromBase64(String? pdfBase64) async {
    final bytes = _decodeBase64Any(pdfBase64);
    if (bytes == null) {
      _toast('No valid PDF found');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/notice_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(path);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ----------------- File Pickers -----------------
  Future<_PickedFile?> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.bytes == null) return null;
    return _PickedFile(
      name: f.name,
      bytes: f.bytes!,
      mime: _guessImageMime(f.name),
    );
  }

  Future<_PickedFile?> _pickPdf() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.bytes == null) return null;
    return _PickedFile(name: f.name, bytes: f.bytes!, mime: 'application/pdf');
  }

  // ----------------- Add/Edit Dialog -----------------
  Future<void> _showAddEditDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final id = _safeInt(existing?['id']);

    final titleCtrl = TextEditingController(text: _safeStr(existing?['title']));
    final descCtrl =
        TextEditingController(text: _safeStr(existing?['description']));

    String? imageBase64 = _safeStr(existing?['image_base64']).trim();
    String? pdfBase64 = _safeStr(existing?['pdf_base64']).trim();

    _PickedFile? pickedImg;
    _PickedFile? pickedPdf;

    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final imgBytes = pickedImg?.bytes ?? _decodeBase64Any(imageBase64);
          final hasImg = imgBytes != null;
          final hasPdf = (pickedPdf != null) || (pdfBase64?.isNotEmpty == true);

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Container(
              width: 680,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                        child: const Icon(Icons.campaign_rounded, color: Color(0xFF2563EB)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEdit ? 'Edit Notice #$id' : 'Create Notice',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          TextField(
                            controller: titleCtrl,
                            decoration: InputDecoration(
                              labelText: 'Title *',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: descCtrl,
                            minLines: 3,
                            maxLines: 6,
                            decoration: InputDecoration(
                              labelText: 'Description *',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Attachments
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7FB),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Attachments',
                                        style: TextStyle(fontWeight: FontWeight.w900)),
                                    const Spacer(),
                                    if (hasImg || hasPdf)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${hasImg ? 'IMG ' : ''}${hasPdf ? 'PDF' : ''}'.trim(),
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final p = await _pickImage();
                                              if (p == null) return;
                                              setLocal(() {
                                                pickedImg = p;
                                                imageBase64 = base64Encode(p.bytes);
                                              });
                                              _toast('Image attached: ${p.name}');
                                            },
                                      icon: const Icon(Icons.image_rounded, size: 18),
                                      label: const Text('Attach Image'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final p = await _pickPdf();
                                              if (p == null) return;
                                              setLocal(() {
                                                pickedPdf = p;
                                                pdfBase64 = base64Encode(p.bytes);
                                              });
                                              _toast('PDF attached: ${p.name}');
                                            },
                                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                                      label: const Text('Attach PDF'),
                                    ),
                                    if (hasImg)
                                      OutlinedButton.icon(
                                        onPressed: saving
                                            ? null
                                            : () {
                                                setLocal(() {
                                                  pickedImg = null;
                                                  imageBase64 = null;
                                                });
                                                _toast('Image removed');
                                              },
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                        label: const Text('Remove Image'),
                                      ),
                                    if (hasPdf)
                                      OutlinedButton.icon(
                                        onPressed: saving
                                            ? null
                                            : () {
                                                setLocal(() {
                                                  pickedPdf = null;
                                                  pdfBase64 = null;
                                                });
                                                _toast('PDF removed');
                                              },
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                        label: const Text('Remove PDF'),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                if (imgBytes != null) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: SizedBox(
                                      height: 170,
                                      width: double.infinity,
                                      child: Image.memory(imgBytes, fit: BoxFit.cover),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                if (hasPdf)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.picture_as_pdf_rounded, color: Colors.deepPurple),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            pickedPdf?.name ?? 'PDF attached',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: saving ? null : () => _openPdfFromBase64(pdfBase64),
                                          child: const Text('Open'),
                                        )
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final t = titleCtrl.text.trim();
                                  final d = descCtrl.text.trim();
                                  if (t.isEmpty || d.isEmpty) {
                                    _toast('Title and description are required');
                                    return;
                                  }

                                  setLocal(() => saving = true);
                                  try {
                                    if (isEdit) {
                                      await _updateNotice(
                                        id: id,
                                        title: t,
                                        description: d,
                                        pdfBase64: pdfBase64,
                                        imageBase64: imageBase64,
                                      );
                                      _toast('Updated');
                                    } else {
                                      await _createNotice(
                                        title: t,
                                        description: d,
                                        pdfBase64: pdfBase64,
                                        imageBase64: imageBase64,
                                      );
                                      _toast('Created');
                                    }

                                    if (mounted) Navigator.pop(ctx);
                                    await _fetchNotices(goPage: 1, search: appliedSearch);
                                  } catch (e) {
                                    _toast(e.toString());
                                  } finally {
                                    if (mounted) setLocal(() => saving = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(isEdit ? 'Save Changes' : 'Create Notice'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    titleCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _confirmDelete(Map<String, dynamic> n) async {
    final id = _safeInt(n['id']);
    final title = _safeStr(n['title']);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notice?'),
        content: Text('Are you sure you want to delete:\n$title'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _deleteNotice(id);
      _toast('Deleted');
      await _fetchNotices(goPage: 1, search: appliedSearch);
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _openDetails(Map<String, dynamic> n) {
    final title = _safeStr(n['title']);
    final desc = _safeStr(n['description']);
    final createdAt = _parseDate(n['created_at']);
    final pdf = _safeStr(n['pdf_base64']).trim();
    final img = _safeStr(n['image_base64']).trim();

    final imgBytes = _decodeBase64Any(img);
    final hasImg = imgBytes != null;
    final hasPdf = pdf.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ListView(
                controller: controller,
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
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.campaign_rounded, color: Color(0xFF2563EB)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Created: ${_prettyDate(createdAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Text(desc, style: const TextStyle(fontSize: 13, height: 1.35)),
                  const SizedBox(height: 14),

                  if (hasImg) ...[
                    const Text('Image', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 240,
                        child: Image.memory(imgBytes!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (hasPdf) ...[
                    const Text('PDF', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7FB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf_rounded, color: Colors.deepPurple),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('PDF attached', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          ElevatedButton(
                            onPressed: () => _openPdfFromBase64(pdf),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddEditDialog(existing: n),
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmDelete(n),
                          icon: const Icon(Icons.delete_rounded),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: Column(
          children: [
            _topHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchNotices(goPage: 1, search: appliedSearch),
                child: loading
                    ? _skeletonList()
                    : (error != null)
                        ? _errorView()
                        : (notices.isEmpty)
                            ? _emptyView()
                            : _noticeList(),
              ),
            ),
            _paginationBar(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color(0xFF2563EB),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Notice'),
      ),
    );
  }

  Widget _topHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2563EB),
            const Color(0xFF2563EB).withOpacity(0.85),
            const Color(0xFF22C55E).withOpacity(0.85),
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Master Notice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading
                    ? null
                    : () => _fetchNotices(goPage: 1, search: appliedSearch),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
              IconButton(
                tooltip: 'API',
                onPressed: () async {
                  final u = Uri.parse(apiBase);
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.link_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.22)),
                  ),
                  child: TextField(
                    controller: searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'Search title / description…',
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.75)),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Colors.white.withOpacity(0.9)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) =>
                        _fetchNotices(goPage: 1, search: searchCtrl.text),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () =>
                    _fetchNotices(goPage: 1, search: searchCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                child: const Text('Go',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {
                  searchCtrl.clear();
                  _fetchNotices(goPage: 1, search: '');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.65)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                child: const Text('Clear',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              _chip('Total',
                  totalRecords == 0 ? '${notices.length}' : '$totalRecords',
                  icon: Icons.inventory_2_rounded),
              const SizedBox(width: 10),
              _chip('Page', '$page', icon: Icons.layers_rounded),
              const Spacer(),
              if (appliedSearch.trim().isNotEmpty)
                _chip('Filter', appliedSearch, icon: Icons.filter_alt_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String a, String b, {required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withOpacity(0.95)),
          const SizedBox(width: 6),
          Text('$a: ',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 11)),
          Flexible(
            child: Text(
              b,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeList() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: notices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final n = notices[i];
        final id = _safeInt(n['id']);
        final title = _safeStr(n['title']);
        final desc = _safeStr(n['description']);
        final createdAt = _parseDate(n['created_at']);
        final pdf = _safeStr(n['pdf_base64']).trim();
        final img = _safeStr(n['image_base64']).trim();

        final imgBytes = _decodeBase64Any(img);
        final hasImg = imgBytes != null;
        final hasPdf = pdf.isNotEmpty;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openDetails(n),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                if (hasImg)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(18)),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: Image.memory(imgBytes!, fit: BoxFit.cover),
                    ),
                  )
                else
                  Container(
                    height: 90,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F7FB),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    child: Center(
                      child: Icon(Icons.image_not_supported_rounded,
                          color: Colors.grey.shade400),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '#$id',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            height: 1.25),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Text(
                            _prettyDate(createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (hasImg) _tag('IMG', Colors.green),
                          if (hasPdf) ...[
                            const SizedBox(width: 8),
                            _tag('PDF', Colors.deepPurple),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openDetails(n),
                            icon: const Icon(Icons.visibility_rounded, size: 18),
                            label: const Text('View'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          if (hasPdf)
                            ElevatedButton.icon(
                              onPressed: () => _openPdfFromBase64(pdf),
                              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                              label: const Text('Open PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _showAddEditDialog(existing: n),
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _confirmDelete(n),
                            icon: const Icon(Icons.delete_rounded, size: 18),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tag(String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _paginationBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: page > 1 && !loading
                ? () => _fetchNotices(goPage: page - 1, search: appliedSearch)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Prev'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(width: 10),
          Text('Page $page', style: const TextStyle(fontWeight: FontWeight.w900)),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: hasNext && !loading
                ? () => _fetchNotices(goPage: page + 1, search: appliedSearch)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.25)),
          ),
          child: Text(
            error ?? 'Unknown error',
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Icon(Icons.inbox_rounded, size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              const Text(
                'No notices found',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Try a different search or add a new notice.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------- Skeleton -----------------
  Widget _skeletonList() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => _skeletonCard(),
    );
  }

  Widget _skeletonCard() {
    return FadeTransition(
      opacity: _pulse,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _sk(180, 12),
                      const Spacer(),
                      _sk(44, 18, r: 999),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sk(double.infinity, 10),
                  const SizedBox(height: 8),
                  _sk(double.infinity, 10),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _sk(120, 10),
                      const Spacer(),
                      _sk(36, 16, r: 999),
                      const SizedBox(width: 8),
                      _sk(36, 16, r: 999),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _sk(double.infinity, 36, r: 14)),
                      const SizedBox(width: 10),
                      Expanded(child: _sk(double.infinity, 36, r: 14)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sk(double w, double h, {double r = 12}) {
    return Container(
      width: w == double.infinity ? double.infinity : w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}

class _PickedFile {
  final String name;
  final Uint8List bytes;
  final String mime;

  const _PickedFile({
    required this.name,
    required this.bytes,
    required this.mime,
  });
}

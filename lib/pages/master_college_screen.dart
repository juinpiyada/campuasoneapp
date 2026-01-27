import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MasterCollegeScreen extends StatefulWidget {
  const MasterCollegeScreen({super.key});

  @override
  State<MasterCollegeScreen> createState() => _MasterCollegeScreenState();
}

class _MasterCollegeScreenState extends State<MasterCollegeScreen> {
  static const String _base = 'https://poweranger-turbo.onrender.com';
  static const String _listUrl = '$_base/master-college/view-colleges';
  static const String _addUrl = '$_base/master-college/add-college';
  static String _editUrl(String id) => '$_base/master-college/edit-college/$id';
  static String _deleteUrl(String id) =>
      '$_base/master-college/delete-college/$id';

  // NEW: dropdown APIs
  static const String _userRoleUrl = '$_base/api/user-role';
  static const String _groupListUrl = '$_base/api/college-group/list';

  bool _loading = true;
  String? _error;
  List<College> _colleges = [];

  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _search = _searchCtrl.text.trim().toLowerCase());
    });
    _fetchColleges();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchColleges() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await http.get(Uri.parse(_listUrl));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = (data is Map && data['colleges'] is List)
            ? data['colleges'] as List
            : <dynamic>[];

        final list = raw
            .map((e) => College.fromJson(e as Map<String, dynamic>))
            .toList();

        list.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

        if (!mounted) return;
        setState(() {
          _colleges = list;
          _loading = false;
        });
      } else if (res.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _colleges = [];
          _loading = false;
        });
      } else {
        throw Exception('Failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<College> get _filtered {
    if (_search.isEmpty) return _colleges;

    bool hit(String? v) => (v ?? '').toLowerCase().contains(_search);

    return _colleges.where((c) {
      return hit(c.collegeId) ||
          hit(c.collegeName) ||
          hit(c.collegeCode) ||
          hit(c.collegeLocation) ||
          hit(c.collegeAddress) ||
          hit(c.collegeEmail) ||
          hit(c.collegePhone) ||
          hit(c.collegeAffiliatedTo) ||
          hit(c.collegeStatus) ||
          hit(c.collegeUrl) ||
          hit(c.collegeUserId) ||
          hit(c.collegeGroupId);
    }).toList();
  }

  void _snack(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _confirmDelete(College c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete college?'),
        content: Text(
          'This will permanently delete:\n\n${c.collegeName ?? '(no name)'} (${c.collegeId ?? '-'})',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (yes != true) return;

    try {
      final id = (c.collegeId ?? '').trim();
      if (id.isEmpty) {
        _snack('Missing collegeid', ok: false);
        return;
      }

      final res = await http.delete(Uri.parse(_deleteUrl(id)));
      if (res.statusCode == 200) {
        _snack('Deleted successfully');
        await _fetchColleges();
      } else if (res.statusCode == 404) {
        _snack('College not found', ok: false);
        await _fetchColleges();
      } else {
        _snack('Delete failed: ${res.statusCode}', ok: false);
      }
    } catch (e) {
      _snack('Delete error: $e', ok: false);
    }
  }

  // ✅ Bottom sheet made scrollable (no overflow)
  Future<void> _openCollegeSheet(College c) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.90,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) {
            return SingleChildScrollView(
              controller: scrollCtrl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.collegeName ?? '(No name)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _StatusChip(status: c.collegeStatus),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _kv('College ID', c.collegeId),
                    _kv('Code', c.collegeCode),
                    _kv('Location', c.collegeLocation),
                    _kv('Address', c.collegeAddress),
                    _kv('Affiliated To', c.collegeAffiliatedTo),
                    _kv('Email', c.collegeEmail),
                    _kv('Phone', c.collegePhone),
                    _kv('URL', c.collegeUrl),
                    _kv('User ID', c.collegeUserId),
                    _kv('Group ID', c.collegeGroupId),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.edit),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _openCollegeForm(editing: c);
                            },
                            label: const Text('Edit'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.error,
                              side: BorderSide(color: cs.error.withOpacity(.7)),
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _confirmDelete(c);
                            },
                            label: const Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _kv(String k, String? v) {
    final value = (v == null || v.trim().isEmpty) ? '—' : v.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ===================== NEW: dropdown loaders =====================

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final k in ['data', 'list', 'items', 'result', 'rows', 'userRoles', 'roles', 'groups', 'collegeGroups']) {
        final v = decoded[k];
        if (v is List) return v;
      }
    }
    return const [];
  }

  String _pickFirstString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  Future<List<_Option>> _loadUserOptions() async {
    final res = await http.get(Uri.parse(_userRoleUrl));
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(res.body);
    final list = _extractList(decoded);

    final out = <_Option>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e as Map);

      // try best-effort: userid / userId / uid etc.
      final id = _pickFirstString(m, [
        'userid',
        'userId',
        'user_id',
        'uid',
        'id',
        'master_user_id',
      ]);

      // label: username + role + userid if available
      final username = _pickFirstString(m, [
        'username',
        'user_name',
        'name',
        'fullName',
        'fullname',
      ]);
      final role = _pickFirstString(m, [
        'roleDescription',
        'roledescription',
        'role_description',
        'role',
        'rolename',
      ]);

      final parts = <String>[];
      if (username.isNotEmpty) parts.add(username);
      if (role.isNotEmpty) parts.add(role);
      if (id.isNotEmpty) parts.add(id);

      if (id.isNotEmpty) {
        out.add(_Option(id: id, label: parts.isEmpty ? id : parts.join(' • ')));
      }
    }

    // remove duplicates by id
    final seen = <String>{};
    final unique = <_Option>[];
    for (final o in out) {
      if (seen.add(o.id)) unique.add(o);
    }
    return unique;
  }

  Future<List<_Option>> _loadGroupOptions() async {
    final res = await http.get(Uri.parse(_groupListUrl));
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(res.body);
    final list = _extractList(decoded);

    final out = <_Option>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e as Map);

      final id = _pickFirstString(m, [
        'collegegroupid',
        'collegeGroupId',
        'groupid',
        'groupId',
        'id',
      ]);
      final name = _pickFirstString(m, [
        'collegegroupname',
        'collegeGroupName',
        'groupname',
        'groupName',
        'name',
      ]);

      if (id.isNotEmpty) {
        out.add(_Option(id: id, label: name.isEmpty ? id : '$name • $id'));
      }
    }

    final seen = <String>{};
    final unique = <_Option>[];
    for (final o in out) {
      if (seen.add(o.id)) unique.add(o);
    }
    return unique;
  }

  // ✅ UPDATED FORM UI (like your image) + Cancel button + dropdowns
  Future<void> _openCollegeForm({College? editing}) async {
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    // controllers
    final idCtrl = TextEditingController(text: editing?.collegeId ?? '');
    final nameCtrl = TextEditingController(text: editing?.collegeName ?? '');
    final codeCtrl = TextEditingController(text: editing?.collegeCode ?? '');
    final addressCtrl = TextEditingController(text: editing?.collegeAddress ?? '');
    final locationCtrl = TextEditingController(text: editing?.collegeLocation ?? '');
    final affCtrl = TextEditingController(text: editing?.collegeAffiliatedTo ?? '');
    final urlCtrl = TextEditingController(text: editing?.collegeUrl ?? '');
    final emailCtrl = TextEditingController(text: editing?.collegeEmail ?? '');
    final phoneCtrl = TextEditingController(text: editing?.collegePhone ?? '');

    // status
    String status = (editing?.collegeStatus ?? 'ACTIVE').toString().trim();
    status = status.isEmpty ? 'ACTIVE' : status.toUpperCase();
    if (status != 'ACTIVE' && status != 'INACTIVE') status = 'ACTIVE';

    // dropdown selections (pre-fill from editing)
    String? selectedUserId = (editing?.collegeUserId ?? '').trim();
    if (selectedUserId != null && selectedUserId.isEmpty) selectedUserId = null;

    String? selectedGroupId = (editing?.collegeGroupId ?? '').trim();
    if (selectedGroupId != null && selectedGroupId.isEmpty) selectedGroupId = null;

    // local dropdown data
    bool startedFetch = false;
    bool loadingUsers = true;
    bool loadingGroups = true;
    List<_Option> userOptions = const [];
    List<_Option> groupOptions = const [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF3F4F6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final t = Theme.of(ctx);
        final cs = t.colorScheme;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> ensureDropdownsLoaded() async {
              if (startedFetch) return;
              startedFetch = true;

              try {
                final u = await _loadUserOptions();
                setLocal(() {
                  userOptions = u;
                  loadingUsers = false;
                  // if editing value not in options, keep it but show as raw
                  if (selectedUserId != null &&
                      !userOptions.any((o) => o.id == selectedUserId)) {
                    userOptions = [
                      _Option(id: selectedUserId!, label: selectedUserId!),
                      ...userOptions,
                    ];
                  }
                });
              } catch (_) {
                setLocal(() => loadingUsers = false);
              }

              try {
                final g = await _loadGroupOptions();
                setLocal(() {
                  groupOptions = g;
                  loadingGroups = false;
                  if (selectedGroupId != null &&
                      !groupOptions.any((o) => o.id == selectedGroupId)) {
                    groupOptions = [
                      _Option(id: selectedGroupId!, label: selectedGroupId!),
                      ...groupOptions,
                    ];
                  }
                });
              } catch (_) {
                setLocal(() => loadingGroups = false);
              }
            }

            // trigger once
            ensureDropdownsLoaded();

            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;

              setLocal(() => saving = true);
              try {
                final payload = {
                  'collegeid': idCtrl.text.trim(),
                  'collegename': nameCtrl.text.trim(),
                  'collegecode': codeCtrl.text.trim(),
                  'collegeaddress': addressCtrl.text.trim(),
                  'collegelocation': locationCtrl.text.trim(),
                  'collegeaffialatedto': affCtrl.text.trim(),
                  'collegeuserid': (selectedUserId ?? '').trim(),
                  'collegegroupid': (selectedGroupId ?? '').trim(),
                  'collegeurl': urlCtrl.text.trim(),
                  'collegeemail': emailCtrl.text.trim(),
                  'collegestatus': status.trim(),
                  'collegephone': phoneCtrl.text.trim(),
                };

                http.Response res;

                if (editing == null) {
                  res = await http.post(
                    Uri.parse(_addUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );

                  if (res.statusCode == 201) {
                    if (mounted) _snack('College added');
                    if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                    await _fetchColleges();
                  } else if (res.statusCode == 400) {
                    if (mounted) _snack('Validation error: ${res.body}', ok: false);
                  } else {
                    if (mounted) _snack('Add failed: ${res.statusCode}', ok: false);
                  }
                } else {
                  final id = (editing.collegeId ?? '').trim();
                  if (id.isEmpty) {
                    if (mounted) _snack('Missing collegeid', ok: false);
                    return;
                  }

                  payload.remove('collegeid');

                  res = await http.put(
                    Uri.parse(_editUrl(id)),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );

                  if (res.statusCode == 200) {
                    if (mounted) _snack('College updated');
                    if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                    await _fetchColleges();
                  } else if (res.statusCode == 404) {
                    if (mounted) _snack('College not found', ok: false);
                    await _fetchColleges();
                  } else {
                    if (mounted) _snack('Update failed: ${res.statusCode}', ok: false);
                  }
                }
              } catch (e) {
                if (mounted) _snack('Error: $e', ok: false);
              } finally {
                setLocal(() => saving = false);
              }
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.92,
              minChildSize: 0.60,
              maxChildSize: 0.98,
              builder: (ctx, scrollCtrl) {
                return SingleChildScrollView(
                  controller: scrollCtrl,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 14,
                      right: 14,
                      bottom: 14 + MediaQuery.of(ctx).viewInsets.bottom,
                      top: 10,
                    ),
                    child: SafeArea(
                      top: false,
                      child: Stack(
                        children: [
                          // main card
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 20,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Form(
                              key: formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    editing == null ? 'Add Institute' : 'Edit Institute',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  LayoutBuilder(
                                    builder: (ctx, c) {
                                      final w = c.maxWidth;
                                      const gap = 14.0;

                                      // 3 columns like image (desktop), 2 on medium, 1 on mobile
                                      int cols = 3;
                                      if (w < 760) cols = 2;
                                      if (w < 520) cols = 1;

                                      final itemW = cols == 1
                                          ? w
                                          : (w - (gap * (cols - 1))) / cols;

                                      return Wrap(
                                        spacing: gap,
                                        runSpacing: gap,
                                        children: [
                                          _FormCardField(
                                            width: itemW,
                                            label: 'College ID',
                                            child: TextFormField(
                                              controller: idCtrl,
                                              enabled: editing == null,
                                              decoration: _formDec(),
                                              validator: (v) {
                                                if (editing != null) return null;
                                                if (v == null || v.trim().isEmpty) {
                                                  return 'College ID is required';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Name',
                                            child: TextFormField(
                                              controller: nameCtrl,
                                              decoration: _formDec(),
                                              validator: (v) {
                                                if (v == null || v.trim().isEmpty) {
                                                  return 'Name is required';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Code',
                                            child: TextFormField(
                                              controller: codeCtrl,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Address',
                                            child: TextFormField(
                                              controller: addressCtrl,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Location',
                                            child: TextFormField(
                                              controller: locationCtrl,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Affiliated To',
                                            child: TextFormField(
                                              controller: affCtrl,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'URL',
                                            child: TextFormField(
                                              controller: urlCtrl,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Email',
                                            child: TextFormField(
                                              controller: emailCtrl,
                                              keyboardType: TextInputType.emailAddress,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Phone',
                                            child: TextFormField(
                                              controller: phoneCtrl,
                                              keyboardType: TextInputType.phone,
                                              decoration: _formDec(),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Status',
                                            child: DropdownButtonFormField<String>(
                                              value: status,
                                              decoration: _formDec(hint: 'Select Status'),
                                              items: const [
                                                DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE')),
                                                DropdownMenuItem(value: 'INACTIVE', child: Text('INACTIVE')),
                                              ],
                                              onChanged: saving
                                                  ? null
                                                  : (v) => setLocal(() => status = (v ?? 'ACTIVE')),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'User ID',
                                            child: DropdownButtonFormField<String>(
                                              value: selectedUserId,
                                              decoration: _formDec(
                                                hint: loadingUsers ? 'Loading...' : 'Select User',
                                              ),
                                              items: (loadingUsers ? const <_Option>[] : userOptions)
                                                  .map((o) => DropdownMenuItem<String>(
                                                        value: o.id,
                                                        child: Text(
                                                          o.label,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ))
                                                  .toList(),
                                              onChanged: saving || loadingUsers
                                                  ? null
                                                  : (v) => setLocal(() => selectedUserId = v),
                                            ),
                                          ),
                                          _FormCardField(
                                            width: itemW,
                                            label: 'Group ID',
                                            child: DropdownButtonFormField<String>(
                                              value: selectedGroupId,
                                              decoration: _formDec(
                                                hint: loadingGroups ? 'Loading...' : 'Select Group',
                                              ),
                                              items: (loadingGroups ? const <_Option>[] : groupOptions)
                                                  .map((o) => DropdownMenuItem<String>(
                                                        value: o.id,
                                                        child: Text(
                                                          o.label,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ))
                                                  .toList(),
                                              onChanged: saving || loadingGroups
                                                  ? null
                                                  : (v) => setLocal(() => selectedGroupId = v),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 18),

                                  LayoutBuilder(
                                    builder: (ctx, c) {
                                      final isNarrow = c.maxWidth < 520;

                                      final addBtn = SizedBox(
                                        width: isNarrow ? double.infinity : 180,
                                        height: 46,
                                        child: FilledButton(
                                          onPressed: saving ? null : submit,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF2563EB),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: saving
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : Text(
                                                  editing == null ? 'Add Institute' : 'Save Changes',
                                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                                ),
                                        ),
                                      );

                                      final cancelBtn = SizedBox(
                                        width: isNarrow ? double.infinity : 120,
                                        height: 46,
                                        child: ElevatedButton(
                                          onPressed: saving
                                              ? null
                                              : () {
                                                  Navigator.pop(ctx);
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: cs.surfaceVariant,
                                            foregroundColor: Colors.grey.shade900,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text(
                                            'Cancel',
                                            style: TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      );

                                      if (isNarrow) {
                                        return Column(
                                          children: [
                                            addBtn,
                                            const SizedBox(height: 10),
                                            cancelBtn,
                                          ],
                                        );
                                      }

                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          addBtn,
                                          const SizedBox(width: 14),
                                          cancelBtn,
                                        ],
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),

                          // top-right X
                          Positioned(
                            right: 6,
                            top: 6,
                            child: IconButton(
                              tooltip: 'Close',
                              onPressed: saving ? null : () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    idCtrl.dispose();
    nameCtrl.dispose();
    codeCtrl.dispose();
    addressCtrl.dispose();
    locationCtrl.dispose();
    affCtrl.dispose();
    urlCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Theme(
      data: t.copyWith(
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cs.surfaceVariant.withOpacity(.35),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Master Colleges'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _fetchColleges,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openCollegeForm(),
          icon: const Icon(Icons.add),
          label: const Text('Add College'),
        ),
        body: RefreshIndicator(
          onRefresh: _fetchColleges,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Search colleges',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _searchCtrl.clear(),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Pill(icon: Icons.list_alt_outlined, text: 'Total: ${_colleges.length}'),
                  _Pill(icon: Icons.filter_alt_outlined, text: 'Showing: ${_filtered.length}'),
                ],
              ),
              const SizedBox(height: 12),

              if (_loading) ...[
                const _LoadingCard(),
                const SizedBox(height: 10),
                const _LoadingCard(),
              ] else if (_error != null) ...[
                _ErrorPanel(error: _error!, onRetry: _fetchColleges),
              ] else if (_filtered.isEmpty) ...[
                _EmptyPanel(
                  title: _colleges.isEmpty ? 'No colleges found' : 'No match found',
                  subtitle: _colleges.isEmpty
                      ? 'Tap “Add College” to create the first one.'
                      : 'Try a different keyword.',
                  onAdd: () => _openCollegeForm(),
                ),
              ] else ...[
                ..._filtered.map((c) => _CollegeCard(
                      college: c,
                      onTap: () => _openCollegeSheet(c),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* =============================== FORM UI HELPERS =============================== */

InputDecoration _formDec({String? hint}) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
    ),
  );
}

class _FormCardField extends StatelessWidget {
  final double width;
  final String label;
  final Widget child;

  const _FormCardField({
    required this.width,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Option {
  final String id;
  final String label;
  const _Option({required this.id, required this.label});
}

/* =============================== UI Widgets =============================== */

class _CollegeCard extends StatelessWidget {
  final College college;
  final VoidCallback onTap;

  const _CollegeCard({required this.college, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    String line2 = [
      if ((college.collegeCode ?? '').trim().isNotEmpty) 'Code: ${college.collegeCode}',
      if ((college.collegeLocation ?? '').trim().isNotEmpty) '📍 ${college.collegeLocation}',
    ].join('  •  ');

    String line3 = [
      if ((college.collegePhone ?? '').trim().isNotEmpty) '📞 ${college.collegePhone}',
      if ((college.collegeEmail ?? '').trim().isNotEmpty) '✉️ ${college.collegeEmail}',
    ].join('  •  ');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: cs.primaryContainer.withOpacity(.55),
                ),
                child: Icon(Icons.school_outlined, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            college.collegeName ?? '(No name)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _StatusChip(status: college.collegeStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${college.collegeId ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          t.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (line2.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        line2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (line3.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        line3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.touch_app_outlined,
                            size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tap for actions',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
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
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String? status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = (status ?? 'ACTIVE').trim().toUpperCase();
    final isActive = s == 'ACTIVE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: (isActive ? cs.tertiaryContainer : cs.surfaceVariant).withOpacity(.8),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: Text(
        s,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: isActive ? cs.onTertiaryContainer : cs.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.surfaceVariant.withOpacity(.35),
        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(child: Text('Loading colleges...')),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorPanel({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.error.withOpacity(.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Failed to load data',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(error, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  const _EmptyPanel({required this.title, required this.subtitle, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add College'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =============================== Data Model =============================== */

class College {
  final String? collegeId;
  final String? collegeName;
  final String? collegeCode;
  final String? collegeAddress;
  final String? collegeLocation;
  final String? collegeAffiliatedTo;
  final String? collegeUserId;
  final String? collegeGroupId;
  final String? collegeUrl;
  final String? collegeEmail;
  final String? collegeStatus;
  final String? collegePhone;
  final String? createdAt;
  final String? updatedAt;

  College({
    this.collegeId,
    this.collegeName,
    this.collegeCode,
    this.collegeAddress,
    this.collegeLocation,
    this.collegeAffiliatedTo,
    this.collegeUserId,
    this.collegeGroupId,
    this.collegeUrl,
    this.collegeEmail,
    this.collegeStatus,
    this.collegePhone,
    this.createdAt,
    this.updatedAt,
  });

  static String? _s(dynamic v) => (v == null) ? null : v.toString();

  factory College.fromJson(Map<String, dynamic> j) {
    return College(
      collegeId: _s(j['collegeid'] ?? j['collegeId']),
      collegeName: _s(j['collegename'] ?? j['collegeName']),
      collegeCode: _s(j['collegecode'] ?? j['collegeCode']),
      collegeAddress: _s(j['collegeaddress'] ?? j['collegeAddress']),
      collegeLocation: _s(j['collegelocation'] ?? j['collegeLocation']),
      collegeAffiliatedTo: _s(
        j['collegeaffialatedto'] ?? j['collegeaffiliatedto'] ?? j['collegeAffialatedTo'],
      ),
      collegeUserId: _s(j['collegeuserid'] ?? j['collegeUserId']),
      collegeGroupId: _s(j['collegegroupid'] ?? j['collegeGroupId']),
      collegeUrl: _s(j['collegeurl'] ?? j['collegeUrl']),
      collegeEmail: _s(j['collegeemail'] ?? j['collegeEmail']),
      collegeStatus: _s(j['collegestatus'] ?? j['collegeStatus']),
      collegePhone: _s(j['collegephone'] ?? j['collegePhone']),
      createdAt: _s(j['createdat'] ?? j['createdAt']),
      updatedAt: _s(j['updatedat'] ?? j['updatedAt']),
    );
  }
}
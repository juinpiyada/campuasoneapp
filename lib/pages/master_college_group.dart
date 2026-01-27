import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MasterCollegeGroupScreen extends StatefulWidget {
  const MasterCollegeGroupScreen({super.key});

  @override
  State<MasterCollegeGroupScreen> createState() => _MasterCollegeGroupScreenState();
}

class _MasterCollegeGroupScreenState extends State<MasterCollegeGroupScreen> {
  // ====== REAL BASE URLS (as you gave) ======
  static const String _base = 'https://poweranger-turbo.onrender.com';

  static const String _groupAddUrl = '$_base/api/college-group/add';
  static const String _groupListUrl = '$_base/api/college-group/list';
  static String _groupUpdateUrl(String id) => '$_base/api/college-group/update/$id';
  static String _groupDeleteUrl(String id) => '$_base/api/college-group/delete/$id';

  static const String _usersUrl = '$_base/api/user-role';
  static const String _rolesUrl = '$_base/api/master-role';

  // ====== DATA ======
  bool _loading = false;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];

  // ====== BASIC (STATIC) COUNTRY/CITY (you can replace with API anytime) ======
  final Map<String, List<String>> _countryCities = const {
    'India': ['Kolkata', 'Howrah', 'Durgapur', 'Asansol', 'Delhi', 'Mumbai', 'Pune', 'Chennai'],
    'Bangladesh': ['Dhaka', 'Chattogram', 'Khulna'],
    'USA': ['New York', 'San Francisco', 'Chicago'],
  };

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _fetchGroups(),
        _fetchUsers(),
        _fetchRoles(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------ helpers ------------------------
  dynamic pick(List<dynamic> vals) {
    for (final v in vals) {
      if (v != null) return v;
    }
    return null;
  }

  String s(dynamic v, [String d = '']) => (v == null) ? d : v.toString();

  List<dynamic> _extractList(dynamic body) {
    // Accept many shapes: {groups:[]}, {data:[]}, {rows:[]}, [] etc.
    if (body is List) return body;
    if (body is Map) {
      final candidates = [
        body['groups'],
        body['data'],
        body['rows'],
        body['result'],
        body['users'],
        body['roles'],
        body['items'],
      ];
      final got = pick(candidates);
      if (got is List) return got;
    }
    return const [];
  }

  Map<String, String> _jsonHeaders() => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  void _toast(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  // ------------------------ API calls ------------------------
  Future<void> _fetchGroups() async {
    try {
      final res = await http.get(Uri.parse(_groupListUrl), headers: _jsonHeaders());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final list = _extractList(body);
        _groups = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        if (mounted) setState(() {});
      } else {
        _toast('Failed to load groups (${res.statusCode})');
      }
    } catch (e) {
      _toast('Failed to load groups: $e');
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final res = await http.get(Uri.parse(_usersUrl), headers: _jsonHeaders());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final list = _extractList(body);
        _users = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        if (mounted) setState(() {});
      } else {
        _toast('Failed to load users (${res.statusCode})');
      }
    } catch (e) {
      _toast('Failed to load users: $e');
    }
  }

  Future<void> _fetchRoles() async {
    try {
      final res = await http.get(Uri.parse(_rolesUrl), headers: _jsonHeaders());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final list = _extractList(body);
        _roles = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        if (mounted) setState(() {});
      } else {
        _toast('Failed to load roles (${res.statusCode})');
      }
    } catch (e) {
      _toast('Failed to load roles: $e');
    }
  }

  Future<void> _addGroup(Map<String, dynamic> payload) async {
    final res = await http.post(
      Uri.parse(_groupAddUrl),
      headers: _jsonHeaders(),
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _toast('Group added successfully', ok: true);
      await _fetchGroups();
    } else {
      _toast('Add failed (${res.statusCode}): ${res.body}');
    }
  }

  Future<void> _updateGroup(String groupid, Map<String, dynamic> payload) async {
    final res = await http.put(
      Uri.parse(_groupUpdateUrl(groupid)),
      headers: _jsonHeaders(),
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _toast('Group updated successfully', ok: true);
      await _fetchGroups();
    } else {
      _toast('Update failed (${res.statusCode}): ${res.body}');
    }
  }

  Future<void> _deleteGroup(String groupid) async {
    final res = await http.delete(
      Uri.parse(_groupDeleteUrl(groupid)),
      headers: _jsonHeaders(),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _toast('Group deleted', ok: true);
      await _fetchGroups();
    } else {
      _toast('Delete failed (${res.statusCode}): ${res.body}');
    }
  }

  // ------------------------ UI ------------------------
  String _roleLabel(Map<String, dynamic> r) {
    // try many key names safely
    final desc = pick([
      r['roledesc'],
      r['role_desc'],
      r['role_description'],
      r['roleName'],
      r['name'],
      r['description'],
    ]);
    final id = pick([r['roleid'], r['role_id'], r['id']]);
    return s(desc, s(id, 'Role'));
  }

  String _roleValueToSend(Map<String, dynamic> r) {
    // for grouprole: send role desc if exists else role id
    final desc = pick([
      r['roledesc'],
      r['role_desc'],
      r['role_description'],
      r['roleName'],
      r['name'],
      r['description'],
    ]);
    final id = pick([r['roleid'], r['role_id'], r['id']]);
    return s(desc, s(id, ''));
  }

  String _userLabel(Map<String, dynamic> u) {
    final email = pick([u['email'], u['emailid'], u['user_email'], u['username'], u['userid'], u['user_id']]);
    final id = pick([u['userid'], u['user_id'], u['id'], u['email'], u['username']]);
    final e = s(email, '');
    final i = s(id, '');
    if (e.isNotEmpty && i.isNotEmpty) return '$e — $i';
    return e.isNotEmpty ? e : (i.isNotEmpty ? i : 'User');
  }

  String _userValueToSend(Map<String, dynamic> u) {
    // for group_user_id: prefer userid/email
    final v = pick([u['userid'], u['user_id'], u['email'], u['emailid'], u['username'], u['id']]);
    return s(v, '');
  }

  Future<void> _openGroupDialog({Map<String, dynamic>? initial}) async {
    final isEdit = initial != null;

    final formKey = GlobalKey<FormState>();

    final groupIdCtrl = TextEditingController(text: s(initial?['groupid']));
    final descCtrl = TextEditingController(text: s(initial?['groupdesc'] ?? initial?['groupname']));
    final corpCtrl = TextEditingController(text: s(initial?['groupcorporateaddress']));
    final pinCtrl = TextEditingController(text: s(initial?['grouppin']));
    final emailCtrl = TextEditingController(text: s(initial?['groupemailid']));

    String? selectedCountry = s(initial?['groupcountry']).isEmpty ? null : s(initial?['groupcountry']);
    String? selectedCity = s(initial?['groupcity']).isEmpty ? null : s(initial?['groupcity']);

    Map<String, dynamic>? selectedRole;
    final initRoleRaw = s(initial?['grouprole']);
    if (initRoleRaw.isNotEmpty) {
      selectedRole = _roles.firstWhere(
        (r) => _roleValueToSend(r).toLowerCase() == initRoleRaw.toLowerCase() || _roleLabel(r).toLowerCase() == initRoleRaw.toLowerCase(),
        orElse: () => {},
      );
      if (selectedRole.isEmpty) selectedRole = null;
    }

    Map<String, dynamic>? selectedUser;
    final initUserRaw = s(initial?['group_user_id']);
    if (initUserRaw.isNotEmpty) {
      selectedUser = _users.firstWhere(
        (u) => _userValueToSend(u).toLowerCase() == initUserRaw.toLowerCase() || _userLabel(u).toLowerCase().contains(initUserRaw.toLowerCase()),
        orElse: () => {},
      );
      if (selectedUser.isEmpty) selectedUser = null;
    }

    List<String> citiesFor(String? c) => (c == null) ? const [] : (_countryCities[c] ?? const []);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          backgroundColor: Colors.transparent,
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              final width = MediaQuery.of(context).size.width;
              final isWide = width >= 900;

              Widget fieldCard({required String label, required Widget child}) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE6E9EF)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(height: 10),
                      child,
                    ],
                  ),
                );
              }

              InputDecoration inputDeco(String hint) {
                return InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE6E9EF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE6E9EF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blue.shade600, width: 1.5),
                  ),
                );
              }

              Widget drop<T>({
                required T? value,
                required String hint,
                required List<DropdownMenuItem<T>> items,
                required void Function(T?) onChanged,
              }) {
                return DropdownButtonFormField<T>(
                  value: value,
                  decoration: inputDeco(hint),
                  items: items,
                  onChanged: onChanged,
                );
              }

              // layout: 3 columns like image (wide), else responsive wrap
              final colWidth = isWide ? 320.0 : (width >= 650 ? (width - 60) / 2 : (width - 60));

              Widget gridWrap(List<Widget> children) {
                return Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: children
                      .map((w) => SizedBox(width: colWidth, child: w))
                      .toList(),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Row(
                              children: [
                                const Spacer(),
                                Text(
                                  isEdit ? 'Update Group of Institute' : 'Add Group of Institute',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close, size: 24, color: Color(0xFF111827)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Form fields (same as image)
                            gridWrap([
                              fieldCard(
                                label: 'Group ID',
                                child: TextFormField(
                                  controller: groupIdCtrl,
                                  readOnly: isEdit, // keep groupid stable during update
                                  decoration: inputDeco('Group_002'),
                                  validator: (v) {
                                    if ((v ?? '').trim().isEmpty) return 'Group ID is required';
                                    return null;
                                  },
                                ),
                              ),
                              fieldCard(
                                label: 'Description',
                                child: TextFormField(
                                  controller: descCtrl,
                                  decoration: inputDeco(''),
                                  validator: (v) {
                                    if ((v ?? '').trim().isEmpty) return 'Description is required';
                                    return null;
                                  },
                                ),
                              ),
                              fieldCard(
                                label: 'Corporate Address',
                                child: TextFormField(
                                  controller: corpCtrl,
                                  decoration: inputDeco(''),
                                ),
                              ),
                              fieldCard(
                                label: 'PIN',
                                child: TextFormField(
                                  controller: pinCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: inputDeco(''),
                                ),
                              ),
                              fieldCard(
                                label: 'Country',
                                child: drop<String>(
                                  value: selectedCountry,
                                  hint: 'Select Country',
                                  items: _countryCities.keys
                                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: (v) {
                                    setStateDialog(() {
                                      selectedCountry = v;
                                      selectedCity = null;
                                    });
                                  },
                                ),
                              ),
                              fieldCard(
                                label: 'City',
                                child: drop<String>(
                                  value: selectedCity,
                                  hint: 'Select City',
                                  items: citiesFor(selectedCountry)
                                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: (v) => setStateDialog(() => selectedCity = v),
                                ),
                              ),
                              fieldCard(
                                label: 'Email ID',
                                child: TextFormField(
                                  controller: emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: inputDeco(''),
                                ),
                              ),
                              fieldCard(
                                label: 'Role',
                                child: drop<Map<String, dynamic>>(
                                  value: selectedRole,
                                  hint: 'Select Role',
                                  items: _roles
                                      .map((r) => DropdownMenuItem<Map<String, dynamic>>(
                                            value: r,
                                            child: Text(_roleLabel(r)),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setStateDialog(() => selectedRole = v),
                                ),
                              ),
                              fieldCard(
                                label: 'User ID',
                                child: drop<Map<String, dynamic>>(
                                  value: selectedUser,
                                  hint: 'Select User',
                                  items: _users
                                      .map((u) => DropdownMenuItem<Map<String, dynamic>>(
                                            value: u,
                                            child: Text(_userLabel(u), overflow: TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setStateDialog(() => selectedUser = v),
                                ),
                              ),
                            ]),

                            const SizedBox(height: 22),

                            // Buttons (Add + Cancel like image)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 140,
                                  height: 44,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 6,
                                    ),
                                    onPressed: () async {
                                      if (!(formKey.currentState?.validate() ?? false)) return;

                                      final payload = <String, dynamic>{
                                        'groupid': groupIdCtrl.text.trim(),
                                        'groupdesc': descCtrl.text.trim(),
                                        'groupcorporateaddress': corpCtrl.text.trim().isEmpty ? null : corpCtrl.text.trim(),
                                        'groupcity': selectedCity,
                                        'grouppin': pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim(),
                                        'groupcountry': selectedCountry,
                                        'groupemailid': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                        'grouprole': selectedRole == null ? null : _roleValueToSend(selectedRole!),
                                        'group_user_id': selectedUser == null ? null : _userValueToSend(selectedUser!),
                                      };

                                      Navigator.pop(context);

                                      setState(() => _loading = true);
                                      try {
                                        if (isEdit) {
                                          await _updateGroup(groupIdCtrl.text.trim(), payload);
                                        } else {
                                          await _addGroup(payload);
                                        }
                                      } finally {
                                        if (mounted) setState(() => _loading = false);
                                      }
                                    },
                                    child: Text(isEdit ? 'Update' : 'Add',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                SizedBox(
                                  width: 140,
                                  height: 44,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE5E7EB),
                                      foregroundColor: const Color(0xFF111827),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(String groupid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Do you want to delete "$groupid"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _loading = true);
      try {
        await _deleteGroup(groupid);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('College Group Manager'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              setState(() => _loading = true);
              try {
                await _boot();
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _loading ? null : () => _openGroupDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Group'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_groups.isEmpty && !_loading)
            const Center(child: Text('No groups found')),
          if (_groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 900;

                  if (!wide) {
                    // Mobile style cards
                    return ListView.builder(
                      itemCount: _groups.length,
                      itemBuilder: (ctx, i) {
                        final g = _groups[i];
                        final gid = s(g['groupid']);
                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            title: Text('$gid — ${s(g['groupdesc'] ?? g['groupname'])}'),
                            subtitle: Text(
                              'Country: ${s(g['groupcountry'])} | City: ${s(g['groupcity'])}\n'
                              'Role: ${s(g['grouprole'])} | User: ${s(g['group_user_id'])}',
                            ),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _openGroupDialog(initial: g),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _confirmDelete(gid),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }

                  // Desktop/table style
                  return SingleChildScrollView(
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Group ID')),
                            DataColumn(label: Text('Description')),
                            DataColumn(label: Text('Country')),
                            DataColumn(label: Text('City')),
                            DataColumn(label: Text('Role')),
                            DataColumn(label: Text('User ID')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: _groups.map((g) {
                            final gid = s(g['groupid']);
                            return DataRow(
                              cells: [
                                DataCell(Text(gid)),
                                DataCell(Text(s(g['groupdesc'] ?? g['groupname']))),
                                DataCell(Text(s(g['groupcountry']))),
                                DataCell(Text(s(g['groupcity']))),
                                DataCell(Text(s(g['grouprole']))),
                                DataCell(Text(s(g['group_user_id']))),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _openGroupDialog(initial: g),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _confirmDelete(gid),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
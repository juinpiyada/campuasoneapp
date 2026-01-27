// lib/master_user.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// ===============================================
/// CONFIG
/// ===============================================
const String baseUrl = 'https://powerangers-zeo.vercel.app/api'; // <- change to your API root
String get _usersUrl => '$baseUrl/users';

/// ===============================================
/// DATA MODEL
/// ===============================================
class MasterUser {
  final String userid;
  final String? userpwd;
  final String userroles;
  final String? usercreated;
  final String? userlastlogon;
  final bool useractive;
  final String? createdat;
  final String? updatedat;

  MasterUser({
    required this.userid,
    this.userpwd,
    required this.userroles,
    this.usercreated,
    this.userlastlogon,
    required this.useractive,
    this.createdat,
    this.updatedat,
  });

  factory MasterUser.fromJson(Map<String, dynamic> j) {
    return MasterUser(
      userid: j['userid']?.toString() ?? '',
      userpwd: j['userpwd']?.toString(),
      userroles: j['userroles']?.toString() ?? 'user',
      usercreated: j['usercreated']?.toString(),
      userlastlogon: j['userlastlogon']?.toString(),
      useractive: (j['useractive'] == true ||
          j['useractive']?.toString().toLowerCase() == 'true'),
      createdat: j['createdat']?.toString(),
      updatedat: j['updatedat']?.toString(),
    );
  }

  Map<String, dynamic> toCreatePayload() {
    return {
      'userid': userid,
      'userpwd': userpwd ?? '',
      'userroles': userroles,
      'usercreated': usercreated ?? DateTime.now().toIso8601String(),
      'userlastlogon': userlastlogon ?? DateTime.now().toIso8601String(),
      'useractive': useractive,
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'userpwd': userpwd ?? '',
      'userroles': userroles,
      'usercreated': usercreated ?? DateTime.now().toIso8601String(),
      'userlastlogon': userlastlogon ?? DateTime.now().toIso8601String(),
      'useractive': useractive,
    };
  }
}

/// ===============================================
/// SCREEN
/// ===============================================
class MasterUserScreen extends StatefulWidget {
  const MasterUserScreen({super.key});

  @override
  State<MasterUserScreen> createState() => _MasterUserScreenState();
}

class _MasterUserScreenState extends State<MasterUserScreen>
    with TickerProviderStateMixin {
  late final AnimationController _headerCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  late final AnimationController _listCtrl;
  late final Animation<double> _listFade;
  late final Animation<Offset> _listSlide;

  // FAB spin animation controller
  late final AnimationController _fabCtrl;

  bool _loading = false;
  List<MasterUser> _users = [];
  String _search = '';

  @override
  void initState() {
    super.initState();

    _headerCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(_headerFade);
    _headerCtrl.forward();

    _listCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _listFade = CurvedAnimation(parent: _listCtrl, curve: Curves.easeOutCubic);
    _listSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_listFade);

    // FAB rotation controller (one quick spin)
    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fetchUsers();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _listCtrl.dispose();
    _fabCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    try {
      final resp = await http.get(Uri.parse(_usersUrl));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final rawList = (data['users'] as List?) ?? [];
        final list = rawList.map((e) => MasterUser.fromJson(e)).toList();
        setState(() {
          _users = list;
        });
        _listCtrl.forward(from: 0);
      } else {
        _snack('Failed to fetch users: ${resp.statusCode}');
      }
    } catch (e) {
      _snack('Error fetching users: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addUser(MasterUser u) async {
    try {
      final resp = await http.post(
        Uri.parse(_usersUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(u.toCreatePayload()),
      );
      if (resp.statusCode == 201) {
        _snack('User added');
        await _fetchUsers();
      } else {
        _snack('Add failed: ${resp.body}');
      }
    } catch (e) {
      _snack('Add error: $e');
    }
  }

  Future<void> _updateUser(MasterUser u) async {
    try {
      final resp = await http.put(
        Uri.parse('$_usersUrl/${Uri.encodeComponent(u.userid)}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(u.toUpdatePayload()),
      );
      if (resp.statusCode == 200) {
        _snack('User updated');
        await _fetchUsers();
      } else {
        _snack('Update failed: ${resp.body}');
      }
    } catch (e) {
      _snack('Update error: $e');
    }
  }

  Future<void> _deleteUser(String userid) async {
    try {
      final resp =
          await http.delete(Uri.parse('$_usersUrl/${Uri.encodeComponent(userid)}'));
      if (resp.statusCode == 200) {
        _snack('User deleted');
        await _fetchUsers();
      } else {
        _snack('Delete failed: ${resp.body}');
      }
    } catch (e) {
      _snack('Delete error: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<MasterUser> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      return u.userid.toLowerCase().contains(q) ||
          u.userroles.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openUserSheet({MasterUser? existing}) async {
    final res = await showModalBottomSheet<MasterUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserFormSheet(existing: existing),
    );
    if (res == null) return;

    if (existing == null) {
      await _addUser(res);
    } else {
      await _updateUser(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB); // blue-600

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),

      // ===== FAB: icon-only, blue button, red icon, spins on tap =====
      floatingActionButton: FloatingActionButton(
        backgroundColor: primary,
        foregroundColor: Colors.redAccent, // make the icon red
        onPressed: () async {
          // one quick spin
          _fabCtrl.forward(from: 0);
          // small feel-good delay while spinning
          await Future.delayed(const Duration(milliseconds: 150));
          // open create-user sheet
          await _openUserSheet();
        },
        child: AnimatedBuilder(
          animation: _fabCtrl,
          builder: (context, child) {
            // rotate 360° (2*pi) based on controller value
            final angle = _fabCtrl.value * 6.283185307179586;
            return Transform.rotate(
              angle: angle,
              child: const Icon(Icons.person_add_alt_1_rounded),
            );
          },
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: SlideTransition(
                position: _headerSlide,
                child: FadeTransition(
                  opacity: _headerFade,
                  child: Row(
                    children: [
                      // Back
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(Icons.arrow_back_rounded,
                              color: Colors.grey.shade800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Master Users',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      // Search field
                      SizedBox(
                        width: 180,
                        child: _SearchBox(
                          hint: 'Search users...',
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Body
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchUsers,
                child: SlideTransition(
                  position: _listSlide,
                  child: FadeTransition(
                    opacity: _listFade,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'No users found',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 6, 20, 100),
                                itemBuilder: (_, i) {
                                  final u = _filtered[i];
                                  return _UserCard(
                                    user: u,
                                    onEdit: () => _openUserSheet(existing: u),
                                    onDelete: () => _confirmDelete(u.userid),
                                    onToggleActive: () => _updateUser(
                                      MasterUser(
                                        userid: u.userid,
                                        userpwd: u.userpwd ?? '',
                                        userroles: u.userroles,
                                        useractive: !u.useractive,
                                        usercreated: u.usercreated,
                                        userlastlogon: u.userlastlogon,
                                        createdat: u.createdat,
                                        updatedat: u.updatedat,
                                      ),
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemCount: _filtered.length,
                              ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String userid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Are you sure you want to delete "$userid"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteUser(userid);
    }
  }
}

/// ===============================================
/// SEARCH BOX
/// ===============================================
class _SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;

  const _SearchBox({required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          icon: Icon(Icons.search_rounded, color: Colors.grey.shade700),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// ===============================================
/// USER CARD
/// ===============================================
class _UserCard extends StatelessWidget {
  final MasterUser user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = user.useractive ? const Color(0xFF22C55E) : Colors.red;
    final activeText = user.useractive ? 'Active' : 'Inactive';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: Color(0xFF2563EB), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.userid,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Role: ${user.userroles}  •  ${user.userlastlogon == null ? '' : 'Last: ${user.userlastlogon}'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    activeText,
                    style: TextStyle(
                      fontSize: 11,
                      color: activeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: user.useractive ? 'Deactivate' : 'Activate',
            onPressed: onToggleActive,
            icon: Icon(
              user.useractive ? Icons.toggle_on : Icons.toggle_off,
              color: user.useractive ? const Color(0xFF22C55E) : Colors.grey,
              size: 28,
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, color: Colors.black87),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_forever_rounded,
                color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

/// ===============================================
/// ADD/EDIT BOTTOM SHEET
/// ===============================================
class _UserFormSheet extends StatefulWidget {
  final MasterUser? existing;
  const _UserFormSheet({this.existing});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _useridCtrl;
  late final TextEditingController _pwdCtrl;
  String _role = 'user';
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _useridCtrl = TextEditingController(text: widget.existing?.userid ?? '');
    _pwdCtrl = TextEditingController(text: '');
    _role = widget.existing?.userroles ?? 'user';
    _active = widget.existing?.useractive ?? true;
  }

  @override
  void dispose() {
    _useridCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F7FB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isEdit ? 'Edit User' : 'Add User',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // User ID
                        TextFormField(
                          controller: _useridCtrl,
                          enabled: !isEdit,
                          decoration: const InputDecoration(
                            labelText: 'User ID',
                            prefixIcon: Icon(Icons.badge_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return 'User ID is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        // Password
                        TextFormField(
                          controller: _pwdCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (!isEdit && (v ?? '').isEmpty) {
                              return 'Password is required for new user';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        // Role
                        DropdownButtonFormField<String>(
                          initialValue: _role,
                          items: const [
                            DropdownMenuItem(
                              value: 'user',
                              child: Text('User'),
                            ),
                            DropdownMenuItem(
                              value: 'student',
                              child: Text('Student'),
                            ),
                            DropdownMenuItem(
                              value: 'teacher',
                              child: Text('Teacher'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Admin'),
                            ),
                            DropdownMenuItem(
                              value: 'superadmin',
                              child: Text('Super Admin'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _role = v ?? 'user'),
                          decoration: const InputDecoration(
                            labelText: 'Role',
                            prefixIcon: Icon(Icons.manage_accounts_rounded),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Active
                        SwitchListTile(
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                          title: const Text('Active'),
                          subtitle:
                              const Text('Toggle whether this user is active'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  if (!_formKey.currentState!.validate()) {
                                    return;
                                  }
                                  final u = MasterUser(
                                    userid: _useridCtrl.text.trim(),
                                    userpwd: _pwdCtrl.text,
                                    userroles: _role,
                                    useractive: _active,
                                  );
                                  Navigator.pop(context, u);
                                },
                                child: Text(isEdit ? 'Update' : 'Create'),
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
          ),
        );
      },
    );
  }
}

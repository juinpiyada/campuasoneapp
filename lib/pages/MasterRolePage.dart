import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MasterRole {
  final String roleId;
  final String roleDesc;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MasterRole({
    required this.roleId,
    required this.roleDesc,
    this.createdAt,
    this.updatedAt,
  });

  factory MasterRole.fromJson(Map<String, dynamic> json) {
    return MasterRole(
      roleId: json['role_id']?.toString() ?? "",
      roleDesc: json['role_desc']?.toString() ?? "",
      createdAt:
          json['createdat'] != null ? DateTime.parse(json['createdat']) : null,
      updatedAt:
          json['updatedat'] != null ? DateTime.parse(json['updatedat']) : null,
    );
  }
}

class MasterRoleApi {
  static const String baseUrl =
      "https://poweranger-turbo.onrender.com/api/master-role";

  /// ------------------------- GET ALL ROLES -------------------------
  static Future<List<MasterRole>> getAllRoles() async {
    final url = Uri.parse(baseUrl);

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => MasterRole.fromJson(e)).toList();
    } else {
      throw Exception("Failed to load roles");
    }
  }

  /// ------------------------- ADD ROLE -------------------------
  static Future<bool> addRole(String roleId, String roleDesc) async {
    final url = Uri.parse(baseUrl);

    final body = {
      "role_ID": roleId,
      "role_DESC": roleDesc,
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    return response.statusCode == 201;
  }

  /// ------------------------- UPDATE ROLE -------------------------
  static Future<bool> updateRole(String roleId, String roleDesc) async {
    final url = Uri.parse("$baseUrl/$roleId");

    final body = {
      "role_DESC": roleDesc,
    };

    final response = await http.put(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    return response.statusCode == 200;
  }

  /// ------------------------- DELETE ROLE -------------------------
  static Future<bool> deleteRole(String roleId) async {
    final url = Uri.parse("$baseUrl/$roleId");

    final response = await http.delete(url);

    return response.statusCode == 200;
  }
}

class MasterRoleScreen extends StatefulWidget {
  const MasterRoleScreen({super.key});

  @override
  State<MasterRoleScreen> createState() => _MasterRoleScreenState();
}

class _MasterRoleScreenState extends State<MasterRoleScreen> {
  bool _loading = true;
  String? _error;
  List<MasterRole> _roles = [];
  List<MasterRole> _filteredRoles = [];

  final TextEditingController _searchController = TextEditingController();

  static const Color _primaryBlue = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    _fetchRoles();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _roles = await MasterRoleApi.getAllRoles();
      _filteredRoles = List.from(_roles);
    } catch (e) {
      _error = 'Failed to load roles: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredRoles = List.from(_roles);
      } else {
        _filteredRoles = _roles.where((r) {
          return r.roleId.toLowerCase().contains(q) ||
              r.roleDesc.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Future<void> _addRole() async {
    final result = await _showAddRoleDialog();
    if (result == null) return;

    final roleId = result['roleId']!.trim();
    final roleDesc = result['roleDesc']!.trim();

    if (roleId.isEmpty || roleDesc.isEmpty) return;

    setState(() => _loading = true);
    final success = await MasterRoleApi.addRole(roleId, roleDesc);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role added successfully')),
      );
      await _fetchRoles();
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add role')),
      );
    }
  }

  /// Beautiful “Add Role” dialog (like your screenshot)
  Future<Map<String, String>?> _showAddRoleDialog() async {
    final roleIdController = TextEditingController();
    final roleDescController = TextEditingController();
    const Color headingPurple = Color(0xFF4F46E5);

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: Container(
              width: 380,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title + close icon
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        'Add Role',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: headingPurple,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Role ID label
                  const Center(
                    child: Text(
                      'Role ID',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Role ID field
                  TextField(
                    controller: roleIdController,
                    decoration: InputDecoration(
                      hintText: 'Role ID',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _primaryBlue,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Role Description label
                  const Center(
                    child: Text(
                      'Role Description',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Role Description field
                  TextField(
                    controller: roleDescController,
                    decoration: InputDecoration(
                      hintText: 'Role Description',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _primaryBlue,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Add Role button
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        final id = roleIdController.text.trim();
                        final desc = roleDescController.text.trim();
                        if (id.isEmpty || desc.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Please enter both Role ID and Role Description'),
                            ),
                          );
                          return;
                        }
                        Navigator.of(context).pop({
                          'roleId': id,
                          'roleDesc': desc,
                        });
                      },
                      child: const Text(
                        'Add Role',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Close button
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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
    );
  }

  Widget _buildRoleCard(MasterRole role) {
    final String initials = (role.roleId.isNotEmpty
            ? role.roleId
            : (role.roleDesc.isNotEmpty ? role.roleDesc : '?'))
        .trim()
        .toUpperCase();

    final String avatarText =
        initials.length >= 2 ? initials.substring(0, 2) : initials;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar circle
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                avatarText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.roleDesc.isEmpty ? role.roleId : role.roleDesc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${role.roleId}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  if (role.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Created: ${role.createdAt}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (_filteredRoles.isEmpty) {
      return const Center(
        child: Text(
          'No roles found',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchRoles,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _filteredRoles.length,
        itemBuilder: (_, i) {
          final role = _filteredRoles[i];
          return _buildRoleCard(role);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        title: const Text(
          'Master Role Map',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _fetchRoles,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by Role ID or Description',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(
                    color: _primaryBlue,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE5EDFF),
        elevation: 4,
        onPressed: _addRole,
        child: const Icon(
          Icons.add_rounded,
          color: _primaryBlue,
        ),
      ),
    );
  }
}
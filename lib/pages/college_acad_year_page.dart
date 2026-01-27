// lib/pages/college_acad_year_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/* ========================= BACKEND ROUTES ========================= */
// Academic Year API
const String kAcadYearApi = "https://powerangers-zeo.vercel.app/api/master-acadyear";

// ✅ College dropdown MUST load from this link (as you asked)
const String kCollegesApi = "https://powerangers-zeo.vercel.app/master-college/view-colleges";

// (safe fallback – does NOT hamper anything if the above link ever returns empty)
const String kCollegesApiFallback = "https://powerangers-zeo.vercel.app/api/master-college/view-colleges";

// Dept API (kept as-is)
const String kDeptsApi = "https://powerangers-zeo.vercel.app/api/master-depts";

/* ========================= HELPERS ========================= */

String joinUrl(String base, String path) {
  if (base.isEmpty) return path;
  if (path.isEmpty) return base;
  final b = base.endsWith("/") ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith("/") ? path.substring(1) : path;
  return "$b/$p";
}

String pad2(int n) => n.toString().padLeft(2, "0");
String toISO(int y, int m, int d) => "$y-${pad2(m)}-${pad2(d)}";
String startISOFromYear(int y) => toISO(y, 7, 1); // Jul 1

String endISOFromStartISO(String startISO) {
  final y = int.tryParse(startISO.substring(0, 4));
  if (y == null) return "";
  return toISO(y + 1, 6, 30); // Jun 30 next year
}

// Normalize backend datetime -> local YYYY-MM-DD
String toLocalISODate(dynamic dateLike) {
  if (dateLike == null) return "";
  final s = dateLike.toString();
  final simple = RegExp(r"^\d{4}-\d{2}-\d{2}$");
  if (simple.hasMatch(s)) return s;

  final d = DateTime.tryParse(s);
  if (d == null) return s.length >= 10 ? s.substring(0, 10) : s;

  final local = d.toLocal();
  return "${local.year}-${pad2(local.month)}-${pad2(local.day)}";
}

String getNextAcadId(List<AcadYear> list) {
  int maxNum = 0;
  for (final r in list) {
    final id = (r.id ?? "").trim();
    final m = RegExp(r"^ACA_YEAR_(\d+)$").firstMatch(id);
    if (m != null) {
      final num = int.tryParse(m.group(1) ?? "");
      if (num != null && num > maxNum) maxNum = num;
    }
  }
  return "ACA_YEAR_${(maxNum + 1).toString().padLeft(3, "0")}";
}

String getNextDeptId(List<DeptOption> departments) {
  final nums = <int>[];
  for (final d in departments) {
    final id = (d.collegedeptid ?? "");
    if (RegExp(r"^DEPT_\d+$").hasMatch(id)) {
      final n = int.tryParse(id.replaceAll("DEPT_", ""));
      if (n != null) nums.add(n);
    }
  }
  final next = (nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b)) + 1;
  return "DEPT_${next.toString().padLeft(3, "0")}";
}

bool emailOkDotComInOrgNet(String email) {
  final re = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.(com|in|org|net)$');
  return re.hasMatch(email.trim());
}

/* ========================= MODELS ========================= */

class AcadYear {
  final Map<String, dynamic> raw;
  AcadYear(this.raw);

  String? get id => raw["id"]?.toString();
  String? get collegeid => raw["collegeid"]?.toString();
  String? get collegedeptid => raw["collegedeptid"]?.toString();
  String? get collegeacadyearstartdt => raw["collegeacadyearstartdt"]?.toString();
  String? get collegeacadyearenddt => raw["collegeacadyearenddt"]?.toString();
  String? get collegeacadyearstatus => raw["collegeacadyearstatus"]?.toString();
}

class CollegeOption {
  final String collegeid;
  final String collegename;
  CollegeOption({required this.collegeid, required this.collegename});
}

class DeptOption {
  final String? collegedeptid;
  final String collegedeptdesc;
  final String collegeid;

  final String colldeptCode;
  final String colldepthod;
  final String colldepteaail;
  final String colldeptphno;

  DeptOption({
    required this.collegedeptid,
    required this.collegedeptdesc,
    required this.collegeid,
    required this.colldeptCode,
    required this.colldepthod,
    required this.colldepteaail,
    required this.colldeptphno,
  });
}

/* ========================= PAGE ========================= */

class CollegeAcadYearPage extends StatefulWidget {
  const CollegeAcadYearPage({super.key});

  @override
  State<CollegeAcadYearPage> createState() => _CollegeAcadYearPageState();
}

class _CollegeAcadYearPageState extends State<CollegeAcadYearPage> {
  static const int pageSize = 4;
  static const int startBaseYear = 2008;

  static const Color kPrimary = Color(0xFF2563EB);
  static const Color kBg = Color(0xFFF7F7FB);

  bool loading = false;

  // data
  List<AcadYear> years = [];
  List<CollegeOption> colleges = [];
  List<DeptOption> departments = [];

  // search + pagination
  String query = "";
  int page = 1;

  // toast
  bool toastShow = false;
  String toastMsg = "";
  bool toastIsError = false;

  // computed
  List<Map<String, String>> startYearOptions = [];

  // ✅ Scroll controllers (for visible scrollbars)
  final ScrollController _tableHCtrl = ScrollController();
  final ScrollController _tableVCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _buildStartYearOptions();
    _fetchAll();
  }

  @override
  void dispose() {
    _tableHCtrl.dispose();
    _tableVCtrl.dispose();
    super.dispose();
  }

  void _buildStartYearOptions() {
    final now = DateTime.now();
    final lastYear = now.year + 5;
    final opts = <Map<String, String>>[];
    for (int y = startBaseYear; y <= lastYear; y++) {
      final start = startISOFromYear(y);
      final label = "$y-${y + 1} (Jul 1 → Jun 30)";
      opts.add({"value": start, "label": label});
    }
    setState(() => startYearOptions = opts);
  }

  void _showToast({required String message, bool isError = false}) {
    setState(() {
      toastShow = true;
      toastMsg = message;
      toastIsError = isError;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => toastShow = false);
    });
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchYears(),
      _fetchCollegesOptional(),
      _fetchDeptsOptional(),
    ]);
  }

  Future<void> _fetchYears() async {
    setState(() => loading = true);
    try {
      final res = await http.get(Uri.parse(kAcadYearApi));
      final data = jsonDecode(res.body);

      List<dynamic> raw = [];
      if (data is List) raw = data;
      if (data is Map && data["data"] is List) raw = List<dynamic>.from(data["data"]);
      if (data is Map && data["years"] is List) raw = List<dynamic>.from(data["years"]);

      setState(() {
        years = raw
            .whereType<Map>()
            .map((m) => AcadYear(Map<String, dynamic>.from(m)))
            .toList();
      });
    } catch (_) {
      setState(() => years = []);
      _showToast(message: "Failed to fetch records.", isError: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ✅ robust parser for college list (handles many response shapes)
  List<CollegeOption> _parseCollegeList(dynamic data) {
    dynamic raw = data;

    // possible wrappers
    if (raw is Map && raw["colleges"] is List) raw = raw["colleges"];
    if (raw is Map && raw["data"] is List) raw = raw["data"];
    if (raw is Map && raw["rows"] is List) raw = raw["rows"];
    if (raw is Map && raw["result"] is List) raw = raw["result"];

    final out = <CollegeOption>[];
    if (raw is List) {
      for (final x in raw) {
        if (x is! Map) continue;
        final m = Map<String, dynamic>.from(x);

        final id = (m["collegeid"] ??
                m["college_id"] ??
                m["collegeId"] ??
                m["id"] ??
                m["cid"])
            ?.toString()
            .trim();

        final name = (m["collegename"] ??
                m["college_name"] ??
                m["collegeName"] ??
                m["name"] ??
                m["label"])
            ?.toString()
            .trim();

        if (id == null || id.isEmpty) continue;
        out.add(CollegeOption(collegeid: id, collegename: (name == null || name.isEmpty) ? id : name));
      }
    }
    return out;
  }

  Future<List<CollegeOption>> _loadCollegesFrom(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final data = jsonDecode(res.body);
      return _parseCollegeList(data);
    } catch (_) {
      return [];
    }
  }

  Future<void> _fetchCollegesOptional() async {
    // ✅ first: your requested endpoint
    final list1 = await _loadCollegesFrom(kCollegesApi);

    // ✅ fallback (does NOT hamper anything)
    final list = list1.isNotEmpty ? list1 : await _loadCollegesFrom(kCollegesApiFallback);

    if (!mounted) return;
    setState(() => colleges = list);
  }

  Future<void> _fetchDeptsOptional() async {
    try {
      final res = await http.get(Uri.parse(kDeptsApi));
      final data = jsonDecode(res.body);

      List<dynamic> arr = [];
      if (data is List) arr = data;
      if (data is Map && data["departments"] is List) arr = List<dynamic>.from(data["departments"]);
      if (data is Map && data["data"] is List) arr = List<dynamic>.from(data["data"]);

      final list = <DeptOption>[];
      for (final x in arr) {
        if (x is! Map) continue;
        final m = Map<String, dynamic>.from(x);

        final deptId = (m["collegedeptid"] ?? m["dept_id"] ?? m["college_dept_id"])?.toString() ?? "";
        final deptDesc = (m["collegedeptdesc"] ?? m["dept_desc"] ?? m["department_name"])?.toString() ?? "";
        final collegeId = (m["collegeid"] ?? m["college_id"] ?? m["parent_college_id"])?.toString() ?? "";

        if (deptId.isEmpty || deptDesc.isEmpty) continue;

        list.add(
          DeptOption(
            collegedeptid: deptId,
            collegedeptdesc: deptDesc,
            collegeid: collegeId,
            colldeptCode: (m["colldept_code"] ?? m["dept_code"] ?? "")?.toString() ?? "",
            colldepthod: (m["colldepthod"] ?? m["hod"] ?? "")?.toString() ?? "",
            colldepteaail: (m["colldepteaail"] ?? m["email"] ?? "")?.toString() ?? "",
            colldeptphno: (m["colldeptphno"] ?? m["phone"] ?? "")?.toString() ?? "",
          ),
        );
      }

      setState(() => departments = list);
    } catch (_) {
      setState(() => departments = []);
    }
  }

  List<AcadYear> get filteredYears {
    final s = query.trim().toLowerCase();
    if (s.isEmpty) return years;
    return years.where((item) {
      final fields = [
        item.id,
        item.collegeid,
        item.collegedeptid,
        item.collegeacadyearstartdt,
        item.collegeacadyearenddt,
        item.collegeacadyearstatus,
      ].map((v) => (v ?? "").toLowerCase());
      return fields.any((txt) => txt.contains(s));
    }).toList();
  }

  int get totalPages {
    final tp = (filteredYears.length / pageSize).ceil();
    return tp < 1 ? 1 : tp;
  }

  List<AcadYear> get pageItems {
    final start = (page - 1) * pageSize;
    final end = start + pageSize;
    if (start >= filteredYears.length) return [];
    return filteredYears.sublist(start, end > filteredYears.length ? filteredYears.length : end);
  }

  String collegeNameFor(String? id) {
    if (id == null) return "";
    final c = colleges.where((x) => x.collegeid == id).toList();
    return c.isNotEmpty ? c.first.collegename : id;
  }

  String deptDescFor(String? deptId) {
    if (deptId == null) return "";
    final d = departments.where((x) => x.collegedeptid == deptId).toList();
    return d.isNotEmpty ? d.first.collegedeptdesc : deptId;
  }

  Future<void> _openAdd() async {
    final nextId = getNextAcadId(years);
    final nextDept = getNextDeptId(departments);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AcadYearFormDialog(
        mode: FormMode.add,
        initial: {"id": nextId, "collegedeptid": nextDept},
        colleges: colleges,
        departments: departments,
        startYearOptions: startYearOptions,
        nextDeptId: nextDept,
      ),
    );

    if (saved == true) {
      await _fetchAll();
      _showToast(message: "Academic year saved!");
    }
  }

  Future<void> _openEdit(AcadYear item) async {
    final nextDept = getNextDeptId(departments);
    final dept = departments.where((d) => d.collegedeptid == (item.collegedeptid ?? "")).toList();
    final d0 = dept.isNotEmpty ? dept.first : null;

    final initial = Map<String, dynamic>.from(item.raw);
    initial["collegeid"] = (item.collegeid ?? "").toString();
    initial["collegedeptid"] = (item.collegedeptid ?? "").toString();
    initial["collegedeptdesc"] = (d0?.collegedeptdesc ?? initial["collegedeptdesc"] ?? "").toString();
    initial["colldept_code"] = (d0?.colldeptCode ?? initial["colldept_code"] ?? "").toString();
    initial["colldepthod"] = (d0?.colldepthod ?? initial["colldepthod"] ?? "").toString();
    initial["colldepteaail"] = (d0?.colldepteaail ?? initial["colldepteaail"] ?? "").toString();
    initial["colldeptphno"] = (d0?.colldeptphno ?? initial["colldeptphno"] ?? "").toString();
    initial["collegeacadyearstartdt"] = toLocalISODate(item.collegeacadyearstartdt);
    initial["collegeacadyearenddt"] = toLocalISODate(item.collegeacadyearenddt);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AcadYearFormDialog(
        mode: FormMode.edit,
        initial: initial,
        colleges: colleges,
        departments: departments,
        startYearOptions: startYearOptions,
        nextDeptId: nextDept,
      ),
    );

    if (saved == true) {
      await _fetchAll();
      _showToast(message: "Academic year updated!");
    }
  }

  Future<void> _openDelete(AcadYear item) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ConfirmDeleteDialog(id: item.id ?? ""),
    );
    if (ok != true) return;

    try {
      final url = joinUrl(kAcadYearApi, "delete/${Uri.encodeComponent(item.id ?? "")}");
      final res = await http.delete(Uri.parse(url));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _fetchYears();
        _showToast(message: "Academic year deleted!");
      } else {
        _showToast(message: "Failed to delete.", isError: true);
      }
    } catch (_) {
      _showToast(message: "Failed to delete.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (page > totalPages) page = totalPages;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          "ACADEMIC TERM / YEAR",
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                // Toolbar (Search + POST)
                Row(
                  children: [
                    Expanded(
                      child: _SearchBox(
                        value: query,
                        onChanged: (v) => setState(() {
                          query = v;
                          page = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _openAdd,
                      icon: const Icon(Icons.add),
                      label: const Text("POST"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Table Card
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE6E9F2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        children: [
                          Expanded(
                            // ✅ Scrollbars added here (horizontal + vertical)
                            child: Scrollbar(
                              controller: _tableHCtrl,
                              thumbVisibility: true,
                              thickness: 6,
                              radius: const Radius.circular(999),
                              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _tableHCtrl,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: 980,
                                  child: Scrollbar(
                                    controller: _tableVCtrl,
                                    thumbVisibility: true,
                                    thickness: 6,
                                    radius: const Radius.circular(999),
                                    notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                                    child: SingleChildScrollView(
                                      controller: _tableVCtrl,
                                      child: DataTable(
                                        headingRowHeight: 46,
                                        dataRowMinHeight: 46,
                                        dataRowMaxHeight: 62,
                                        headingTextStyle: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF111827),
                                        ),
                                        columns: const [
                                          DataColumn(label: Text("ID")),
                                          DataColumn(label: Text("College")),
                                          DataColumn(label: Text("Department")),
                                          DataColumn(label: Text("Start")),
                                          DataColumn(label: Text("End")),
                                          DataColumn(label: Text("Status")),
                                          DataColumn(label: Text("Actions")),
                                        ],
                                        rows: loading
                                            ? const [
                                                DataRow(cells: [
                                                  DataCell(Text("Loading...")),
                                                  DataCell(Text("")),
                                                  DataCell(Text("")),
                                                  DataCell(Text("")),
                                                  DataCell(Text("")),
                                                  DataCell(Text("")),
                                                  DataCell(Text("")),
                                                ])
                                              ]
                                            : pageItems.isEmpty
                                                ? const [
                                                    DataRow(cells: [
                                                      DataCell(Text("No records found.")),
                                                      DataCell(Text("")),
                                                      DataCell(Text("")),
                                                      DataCell(Text("")),
                                                      DataCell(Text("")),
                                                      DataCell(Text("")),
                                                      DataCell(Text("")),
                                                    ])
                                                  ]
                                                : pageItems.map((item) {
                                                    return DataRow(
                                                      cells: [
                                                        DataCell(Text(item.id ?? "")),
                                                        DataCell(Text(collegeNameFor(item.collegeid))),
                                                        DataCell(Text(deptDescFor(item.collegedeptid))),
                                                        DataCell(Text(toLocalISODate(item.collegeacadyearstartdt))),
                                                        DataCell(Text(toLocalISODate(item.collegeacadyearenddt))),
                                                        DataCell(Text(item.collegeacadyearstatus ?? "")),
                                                        DataCell(Row(
                                                          children: [
                                                            _IconPillButton(
                                                              tooltip: "PUT (Edit)",
                                                              icon: Icons.edit,
                                                              label: "PUT",
                                                              onTap: () => _openEdit(item),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            _IconPillButton(
                                                              tooltip: "DELETE",
                                                              icon: Icons.delete,
                                                              label: "DELETE",
                                                              danger: true,
                                                              onTap: () => _openDelete(item),
                                                            ),
                                                          ],
                                                        )),
                                                      ],
                                                    );
                                                  }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Pagination
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Showing page $page of $totalPages pages",
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                              IconButton(
                                onPressed: page <= 1 ? null : () => setState(() => page = (page - 1).clamp(1, totalPages)),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: kPrimary.withOpacity(0.18)),
                                ),
                                child: Text("$page", style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              IconButton(
                                onPressed: page >= totalPages ? null : () => setState(() => page = (page + 1).clamp(1, totalPages)),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Toast overlay
          if (toastShow)
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: (toastIsError ? Colors.red : Colors.green).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: (toastIsError ? Colors.red : Colors.green).withOpacity(0.25)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Text(toastIsError ? "⚠️" : "✅", style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          toastMsg,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: toastIsError ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => toastShow = false),
                        icon: const Icon(Icons.close),
                      )
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ========================= SMALL UI HELPERS ========================= */

class _IconPillButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final String? label;

  const _IconPillButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.danger = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFDC2626) : const Color(0xFF2563EB);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(
                  label!,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* ========================= SEARCH BOX ========================= */

class _SearchBox extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SearchBox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: "Search",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E9F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.6),
        ),
        isDense: true,
      ),
    );
  }
}

/* ========================= DELETE CONFIRM ========================= */

class ConfirmDeleteDialog extends StatelessWidget {
  final String id;
  const ConfirmDeleteDialog({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Delete Academic Year?",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Align(alignment: Alignment.centerLeft, child: Text("Are you sure you want to delete:")),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.18)),
              ),
              child: Text(id.isEmpty ? "-" : id, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text("Yes, Delete", style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE6E9F2)),
                    ),
                    child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w800)),
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

/* ========================= ADD / EDIT FORM DIALOG ========================= */

enum FormMode { add, edit }

class AcadYearFormDialog extends StatefulWidget {
  final FormMode mode;
  final Map<String, dynamic> initial;

  final List<CollegeOption> colleges;
  final List<DeptOption> departments;
  final List<Map<String, String>> startYearOptions;
  final String nextDeptId;

  const AcadYearFormDialog({
    super.key,
    required this.mode,
    required this.initial,
    required this.colleges,
    required this.departments,
    required this.startYearOptions,
    required this.nextDeptId,
  });

  @override
  State<AcadYearFormDialog> createState() => _AcadYearFormDialogState();
}

class _AcadYearFormDialogState extends State<AcadYearFormDialog> {
  static const Color kPrimary = Color(0xFF2563EB);
  static const Color kBorder = Color(0xFFE6E9F2);

  final _formKey = GlobalKey<FormState>();

  late Map<String, dynamic> form;
  bool saving = false;
  String error = "";

  late TextEditingController idCtrl;
  late TextEditingController deptIdCtrl;
  late TextEditingController deptDescCtrl;
  late TextEditingController deptCodeCtrl;
  late TextEditingController hodCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController phoneCtrl;

  @override
  void initState() {
    super.initState();

    form = {
      "id": "",
      "collegeid": "",
      "collegedeptid": "",
      "collegeacadyearstartdt": "",
      "collegeacadyearenddt": "",
      "collegeacadyearstatus": "",
      "createdat": "",
      "updatedat": "",
      "colldept_code": "",
      "collegedeptdesc": "",
      "colldepthod": "",
      "colldepteaail": "",
      "colldeptphno": "",
      ...widget.initial,
    };

    idCtrl = TextEditingController(text: (form["id"] ?? "").toString());

    final startDeptId = (form["collegedeptid"] ?? widget.nextDeptId).toString();
    deptIdCtrl = TextEditingController(text: startDeptId);

    deptDescCtrl = TextEditingController(text: (form["collegedeptdesc"] ?? "").toString());
    deptCodeCtrl = TextEditingController(text: (form["colldept_code"] ?? "").toString());
    hodCtrl = TextEditingController(text: (form["colldepthod"] ?? "").toString());
    emailCtrl = TextEditingController(text: (form["colldepteaail"] ?? "").toString());
    phoneCtrl = TextEditingController(text: (form["colldeptphno"] ?? "").toString());

    if (widget.mode == FormMode.edit) {
      final deptId = (form["collegedeptid"] ?? "").toString();
      if (deptId.isNotEmpty) {
        final d = widget.departments.where((x) => x.collegedeptid == deptId).toList();
        if (d.isNotEmpty) {
          final one = d.first;
          if (deptDescCtrl.text.isEmpty) deptDescCtrl.text = one.collegedeptdesc;
          if (deptCodeCtrl.text.isEmpty) deptCodeCtrl.text = one.colldeptCode;
          if (hodCtrl.text.isEmpty) hodCtrl.text = one.colldepthod;
          if (emailCtrl.text.isEmpty) emailCtrl.text = one.colldepteaail;
          if (phoneCtrl.text.isEmpty) phoneCtrl.text = one.colldeptphno;
        }
      }
    }
  }

  @override
  void dispose() {
    idCtrl.dispose();
    deptIdCtrl.dispose();
    deptDescCtrl.dispose();
    deptCodeCtrl.dispose();
    hodCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  List<DeptOption> get filteredDepartments {
    final collegeId = (form["collegeid"] ?? "").toString();
    if (collegeId.isEmpty) return widget.departments;

    final hasKey = widget.departments.any((d) => d.collegeid.isNotEmpty);
    if (!hasKey) return widget.departments;

    return widget.departments.where((d) => d.collegeid == collegeId).toList();
  }

  void fillFromExistingDesc(String desc) {
    final d = filteredDepartments.where((x) => x.collegedeptdesc.toLowerCase() == desc.toLowerCase()).toList();
    if (d.isNotEmpty) {
      final match = d.first;
      setState(() {
        deptIdCtrl.text = match.collegedeptid ?? widget.nextDeptId;
        deptCodeCtrl.text = match.colldeptCode;
        hodCtrl.text = match.colldepthod;
        emailCtrl.text = match.colldepteaail;
        phoneCtrl.text = match.colldeptphno;
        form["collegedeptid"] = match.collegedeptid ?? widget.nextDeptId;
      });
    } else {
      setState(() {
        deptIdCtrl.text = widget.nextDeptId; // will be auto-created on submit
        deptCodeCtrl.text = deptCodeCtrl.text;
        hodCtrl.text = hodCtrl.text;
        emailCtrl.text = emailCtrl.text;
        phoneCtrl.text = phoneCtrl.text;
        form["collegedeptid"] = widget.nextDeptId;
      });
    }
  }

  void handleStartSelect(String startISO) {
    final end = startISO.isEmpty ? "" : endISOFromStartISO(startISO);
    setState(() {
      form["collegeacadyearstartdt"] = startISO;
      form["collegeacadyearenddt"] = end;
    });
  }

  String validateDept() {
    final collegeId = (form["collegeid"] ?? "").toString();
    final deptId = deptIdCtrl.text.trim();
    final deptCode = deptCodeCtrl.text.trim();
    final deptDesc = deptDescCtrl.text.trim();
    final ph = phoneCtrl.text.trim();
    final em = emailCtrl.text.trim();

    if (deptId.isEmpty || collegeId.isEmpty || deptCode.isEmpty || deptDesc.isEmpty) {
      return "Please fill Department ID, College, Dept Code, and Description.";
    }
    if (ph.isNotEmpty && !RegExp(r"^\d{10}$").hasMatch(ph)) {
      return "Department phone must be exactly 10 digits.";
    }
    if (em.isNotEmpty && !emailOkDotComInOrgNet(em)) {
      return "Department email must end with .com or .in.";
    }
    return "";
  }

  // ✅ FIX for your FK error:
  // If collegedeptid does NOT exist in dept table, create it first.
  Future<void> _ensureDepartmentExists() async {
    final deptId = deptIdCtrl.text.trim();
    if (deptId.isEmpty) throw Exception("Department ID missing.");

    final existsInLoaded =
        widget.departments.any((d) => (d.collegedeptid ?? "").trim() == deptId);

    if (existsInLoaded) return;

    // Try to create department in backend
    final deptPayload = <String, dynamic>{
      "collegedeptid": deptId,
      "collegeid": (form["collegeid"] ?? "").toString().trim(),
      "collegedeptdesc": deptDescCtrl.text.trim(),
      "colldept_code": deptCodeCtrl.text.trim(),
      "colldepthod": hodCtrl.text.trim(),
      "colldepteaail": emailCtrl.text.trim(),
      "colldeptphno": phoneCtrl.text.trim(),
      "createdat": DateTime.now().toUtc().toIso8601String(),
      "updatedat": DateTime.now().toUtc().toIso8601String(),
    };

    final url = joinUrl(kDeptsApi, "add"); // <-- most common pattern in your APIs
    final res = await http.post(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(deptPayload),
    );

    // If your backend uses a different route, you’ll get 404 here; then change "add" accordingly.
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        "Department create failed (${res.statusCode}). "
        "Create this department first in Department module OR fix Dept API route. "
        "Body: ${res.body}",
      );
    }
  }

  Future<void> submit() async {
    setState(() {
      error = "";
      saving = true;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() => saving = false);
      return;
    }

    final deptErr = validateDept();
    if (deptErr.isNotEmpty) {
      setState(() {
        error = deptErr;
        saving = false;
      });
      return;
    }

    try {
      // ✅ IMPORTANT: fix FK before academic year insert/update
      await _ensureDepartmentExists();

      final payload = <String, dynamic>{
        "id": idCtrl.text.trim(),
        "collegeid": (form["collegeid"] ?? "").toString(),
        "collegedeptid": deptIdCtrl.text.trim(),
        "collegeacadyearstartdt": (form["collegeacadyearstartdt"] ?? "").toString(),
        "collegeacadyearenddt": (form["collegeacadyearenddt"] ?? "").toString(),
        "collegeacadyearstatus": (form["collegeacadyearstatus"] ?? "").toString(),

        // dept fields (backend can ignore)
        "colldept_code": deptCodeCtrl.text.trim(),
        "collegedeptdesc": deptDescCtrl.text.trim(),
        "colldepthod": hodCtrl.text.trim(),
        "colldepteaail": emailCtrl.text.trim(),
        "colldeptphno": phoneCtrl.text.trim(),
      };

      if (widget.mode == FormMode.edit) {
        final url = joinUrl(kAcadYearApi, "update/${Uri.encodeComponent(payload["id"])}");
        final res = await http.put(
          Uri.parse(url),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception("Update failed: ${res.statusCode} ${res.body}");
        }
      } else {
        payload["createdat"] = DateTime.now().toUtc().toIso8601String();
        payload["updatedat"] = DateTime.now().toUtc().toIso8601String();

        final url = joinUrl(kAcadYearApi, "add");
        final res = await http.post(
          Uri.parse(url),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception("Add failed: ${res.statusCode} ${res.body}");
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  InputDecoration _inputDeco({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.8),
      ),
    );
  }

  Widget _fieldCard({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF374151))),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111827)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == FormMode.edit ? "Edit Academic Year" : "Add Academic Year";

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 14),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      onPressed: saving ? null : () => Navigator.pop(context, false),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            LayoutBuilder(
                              builder: (context, c) {
                                final w = c.maxWidth;
                                final cols = w >= 900 ? 3 : (w >= 640 ? 2 : 1);
                                const gap = 14.0;
                                final itemW = (w - (cols - 1) * gap) / cols;

                                Widget cell(Widget child) => SizedBox(width: itemW, child: child);

                                final curStart = (form["collegeacadyearstartdt"] ?? "").toString();
                                final hasCurStart = curStart.isNotEmpty &&
                                    widget.startYearOptions.any((o) => o["value"] == curStart);

                                final startItems = <DropdownMenuItem<String>>[];
                                if (curStart.isNotEmpty && !hasCurStart) {
                                  startItems.add(DropdownMenuItem<String>(
                                    value: curStart,
                                    child: Text("$curStart (loaded)"),
                                  ));
                                }
                                startItems.add(const DropdownMenuItem<String>(
                                  value: "",
                                  child: Text("Select start"),
                                ));
                                for (final opt in widget.startYearOptions) {
                                  startItems.add(DropdownMenuItem<String>(
                                    value: opt["value"]!,
                                    child: Text(opt["label"] ?? opt["value"]!),
                                  ));
                                }

                                final grid = <Widget>[
                                  cell(_fieldCard(
                                    label: "ID",
                                    child: TextFormField(
                                      controller: idCtrl,
                                      readOnly: true,
                                      decoration: _inputDeco(),
                                    ),
                                  )),

                                  // College dropdown
                                  cell(_fieldCard(
                                    label: "College",
                                    child: Builder(builder: (_) {
                                      final curCollege = (form["collegeid"] ?? "").toString();
                                      final hasCurCollege = curCollege.isNotEmpty &&
                                          widget.colleges.any((c) => c.collegeid == curCollege);

                                      final items = <DropdownMenuItem<String>>[
                                        const DropdownMenuItem<String>(value: "", child: Text("Select College")),
                                        if (curCollege.isNotEmpty && !hasCurCollege)
                                          DropdownMenuItem<String>(
                                            value: curCollege,
                                            child: Text("$curCollege (loaded)"),
                                          ),
                                        ...widget.colleges.map(
                                          (c) => DropdownMenuItem(
                                            value: c.collegeid,
                                            child: Text("${c.collegename} (${c.collegeid})"),
                                          ),
                                        ),
                                      ];

                                      return DropdownButtonFormField<String>(
                                        initialValue: curCollege.isEmpty ? "" : curCollege,
                                        decoration: _inputDeco(hint: "Select College"),
                                        items: items,
                                        onChanged: (v) {
                                          final val = (v ?? "");
                                          setState(() => form["collegeid"] = val);

                                          final typedDesc = deptDescCtrl.text.trim();
                                          if (typedDesc.isNotEmpty) fillFromExistingDesc(typedDesc);
                                        },
                                        validator: (v) => (v ?? "").isEmpty ? "Select College" : null,
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                        isExpanded: true,
                                      );
                                    }),
                                  )),

                                  cell(_fieldCard(
                                    label: "Start Date(Jul 1)",
                                    child: DropdownButtonFormField<String>(
                                      initialValue: curStart.isEmpty ? "" : curStart,
                                      decoration: _inputDeco(hint: "Select start"),
                                      items: startItems,
                                      onChanged: (v) => handleStartSelect((v ?? "")),
                                      validator: (v) => (v ?? "").isEmpty ? "Select start" : null,
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                      isExpanded: true,
                                    ),
                                  )),

                                  cell(_fieldCard(
                                    label: "End Date(Jun 30 next year)",
                                    child: TextFormField(
                                      readOnly: true,
                                      decoration: _inputDeco(),
                                      controller: TextEditingController(
                                        text: (form["collegeacadyearenddt"] ?? "").toString(),
                                      ),
                                      validator: (_) => (form["collegeacadyearenddt"] ?? "").toString().isEmpty ? "Required" : null,
                                    ),
                                  )),

                                  cell(_fieldCard(
                                    label: "Status",
                                    child: DropdownButtonFormField<String>(
                                      initialValue: (form["collegeacadyearstatus"] ?? "").toString().isEmpty
                                          ? ""
                                          : (form["collegeacadyearstatus"] ?? "").toString(),
                                      decoration: _inputDeco(hint: "Select Status"),
                                      items: const [
                                        DropdownMenuItem(value: "", child: Text("Select Status")),
                                        DropdownMenuItem(value: "Active", child: Text("Active")),
                                        DropdownMenuItem(value: "Disabled", child: Text("Disabled")),
                                      ],
                                      onChanged: (v) => setState(() => form["collegeacadyearstatus"] = (v ?? "")),
                                      validator: (v) => (v ?? "").isEmpty ? "Select Status" : null,
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                      isExpanded: true,
                                    ),
                                  )),
                                  if (cols >= 3) cell(const SizedBox()),

                                  SizedBox(width: w, child: _sectionHeader("Department / Program Details")),

                                  cell(_fieldCard(
                                    label: "Department ID",
                                    child: TextFormField(
                                      controller: deptIdCtrl,
                                      readOnly: true,
                                      decoration: _inputDeco(),
                                    ),
                                  )),
                                  cell(_fieldCard(
                                    label: "Dept Description",
                                    child: TextFormField(
                                      controller: deptDescCtrl,
                                      decoration: _inputDeco(),
                                      onChanged: (v) => fillFromExistingDesc(v.trim()),
                                      validator: (v) => (v ?? "").trim().isEmpty ? "Required" : null,
                                    ),
                                  )),
                                  cell(_fieldCard(
                                    label: "Dept Code",
                                    child: TextFormField(
                                      controller: deptCodeCtrl,
                                      decoration: _inputDeco(),
                                      validator: (v) => (v ?? "").trim().isEmpty ? "Required" : null,
                                    ),
                                  )),

                                  cell(_fieldCard(
                                    label: "HOD",
                                    child: TextFormField(controller: hodCtrl, decoration: _inputDeco()),
                                  )),
                                  cell(_fieldCard(
                                    label: "Email",
                                    child: TextFormField(
                                      controller: emailCtrl,
                                      decoration: _inputDeco(hint: "name@example.com"),
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) {
                                        final t = (v ?? "").trim();
                                        if (t.isEmpty) return null;
                                        if (!emailOkDotComInOrgNet(t)) return "Email must end with .com or .in.";
                                        return null;
                                      },
                                    ),
                                  )),
                                  cell(_fieldCard(
                                    label: "Phone No",
                                    child: TextFormField(
                                      controller: phoneCtrl,
                                      decoration: _inputDeco(),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) {
                                        final digits = v.replaceAll(RegExp(r"\D"), "");
                                        final cut = digits.length > 10 ? digits.substring(0, 10) : digits;
                                        if (cut != v) {
                                          phoneCtrl.text = cut;
                                          phoneCtrl.selection = TextSelection.fromPosition(TextPosition(offset: cut.length));
                                        }
                                      },
                                      validator: (v) {
                                        final t = (v ?? "").trim();
                                        if (t.isEmpty) return null;
                                        if (!RegExp(r"^\d{10}$").hasMatch(t)) return "Phone must be exactly 10 digits.";
                                        return null;
                                      },
                                    ),
                                  )),
                                ];

                                return Wrap(spacing: gap, runSpacing: 14, children: grid);
                              },
                            ),

                            const SizedBox(height: 16),

                            if (error.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.red.withOpacity(0.22)),
                                ),
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 170,
                                  height: 44,
                                  child: ElevatedButton(
                                    onPressed: saving ? null : submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                    child: saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : Text(
                                            widget.mode == FormMode.edit ? "Save Changes" : "Add",
                                            style: const TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 170,
                                  height: 44,
                                  child: ElevatedButton(
                                    onPressed: saving ? null : () => Navigator.pop(context, false),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE5E7EB),
                                      foregroundColor: const Color(0xFF111827),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w900)),
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
            ),
          ),
        ),
      ),
    );
  }
}

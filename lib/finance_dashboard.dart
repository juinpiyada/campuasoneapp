// lib/finance_dashboard.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';

class FinanceDashboardScreen extends StatefulWidget {
  final String username;
  final String roleDescription;

  const FinanceDashboardScreen({
    super.key,
    required this.username,
    required this.roleDescription,
  });

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen>
    with TickerProviderStateMixin {
  // Main page animations
  late final AnimationController _controller;
  late final Animation<double> _fadeHeader;
  late final Animation<double> _fadeCards;
  late final Animation<Offset> _slideHeader;
  late final Animation<Offset> _slideCards;

  // Menu animation
  late final AnimationController _menuController;
  late final Animation<Offset> _menuSlide;
  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();

    // -------- MAIN PAGE ANIMATION --------
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeHeader = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    _fadeCards = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    _slideHeader = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(_fadeHeader);

    _slideCards = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_fadeCards);

    _controller.forward();

    // -------- MENU ANIMATION --------
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _menuSlide = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _menuController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _menuController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _menuController.forward();
      } else {
        _menuController.reverse();
      }
    });
  }

  // ✅ Logout: clear saved session + go to LoginPage
  Future<void> _logout() async {
    if (_isMenuOpen) _toggleMenu();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth');
    await prefs.remove('sessionUser');
    await prefs.remove('dashboard_hide_charts');
    await prefs.remove('group_mode');
    await prefs.remove('is_group_admin');
    await prefs.remove('child_user_role');

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _openFromMenu(Widget page) {
    if (_isMenuOpen) _toggleMenu();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    });
  }

  void _toastComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Coming soon: $label'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Icon(Icons.more_horiz_rounded,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: Stack(
          children: [
            // ================= MAIN CONTENT =================
            Column(
              children: [
                // ---------- HEADER ----------
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: SlideTransition(
                    position: _slideHeader,
                    child: FadeTransition(
                      opacity: _fadeHeader,
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _toggleMenu,
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
                              child: AnimatedIcon(
                                icon: AnimatedIcons.menu_close,
                                progress: _menuController,
                                size: 22,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF2563EB),
                                  Color(0xFF22C55E),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'F1',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, Finance',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  widget.username,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _logout,
                            icon: const Icon(Icons.logout_rounded),
                            tooltip: 'Logout',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------- ROLE TAG ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FadeTransition(
                      opacity: _fadeHeader,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 16,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.roleDescription,
                              style: const TextStyle(
                                fontSize: 11,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ============== BODY (SCROLLABLE) ==============
                Expanded(
                  child: SlideTransition(
                    position: _slideCards,
                    child: FadeTransition(
                      opacity: _fadeCards,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Finance Overview',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ---- 2x2 STAT GRID ----
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.account_balance_wallet_rounded,
                                    title: 'Today’s Collection',
                                    value: '₹ 1,25,000',
                                    subtitle: 'Cash: 35% · UPI: 65%',
                                    color: const Color(0xFF22C55E),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.pending_actions_rounded,
                                    title: 'Pending Dues',
                                    value: '₹ 8,40,000',
                                    subtitle: 'Next 7 days: ₹ 2.1L',
                                    color: const Color(0xFFF97316),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.receipt_long_rounded,
                                    title: 'Invoices (This Month)',
                                    value: '36',
                                    subtitle: 'Generated & shared',
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.verified_rounded,
                                    title: 'Receipts Verified',
                                    value: '28',
                                    subtitle: 'Awaiting: 5',
                                    color: const Color(0xFF7C3AED),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            const Text(
                              'Quick Actions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _QuickActionChip(
                                  icon: Icons.payments_rounded,
                                  label: 'Collect Fees',
                                  color: const Color(0xFF22C55E),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Collect Fees'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.receipt_long_rounded,
                                  label: 'Generate Invoice',
                                  color: const Color(0xFF2563EB),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Generate Invoice'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.person_search_rounded,
                                  label: 'Student Ledger',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Student Ledger'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.summarize_rounded,
                                  label: 'Reports',
                                  color: const Color(0xFF7C3AED),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Reports'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.currency_rupee_rounded,
                                  label: 'Dues Tracker',
                                  color: const Color(0xFFF97316),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Dues Tracker'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.reply_all_rounded,
                                  label: 'Refunds',
                                  color: const Color(0xFFEF4444),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Refunds'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.approval_rounded,
                                  label: 'Approvals',
                                  color: const Color(0xFF6366F1),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Approvals'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.download_rounded,
                                  label: 'Export',
                                  color: const Color(0xFF334155),
                                  onTap: () => _toastComingSoon('Export'),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            Text(
                              'Recent Activity',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            const SizedBox(height: 10),

                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: const Column(
                                children: [
                                  _ActivityRow(
                                    icon: Icons.payments_rounded,
                                    title: 'Fees received',
                                    subtitle: 'UPI · ₹ 12,500 · 8 min ago',
                                  ),
                                  Divider(height: 16),
                                  _ActivityRow(
                                    icon: Icons.receipt_long_rounded,
                                    title: 'Invoice generated',
                                    subtitle:
                                        'Semester fee · INV-2025-128 · 35 min ago',
                                  ),
                                  Divider(height: 16),
                                  _ActivityRow(
                                    icon: Icons.currency_rupee_rounded,
                                    title: 'Due reminder sent',
                                    subtitle: 'Batch B · 18 students · 1 hour ago',
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ================= HAMBURGER SLIDE MENU =================
            if (_isMenuOpen) ...[
              GestureDetector(
                onTap: _toggleMenu,
                child: Container(color: Colors.black.withOpacity(0.25)),
              ),
              SlideTransition(
                position: _menuSlide,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.72,
                    height: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_rounded,
                              size: 22,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Finance Menu',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _toggleMenu,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        ListTile(
                          leading: const Icon(Icons.home_rounded),
                          title: const Text('Dashboard',
                              style: TextStyle(fontSize: 14)),
                          onTap: _toggleMenu,
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.payments_rounded),
                          title: const Text('Collections',
                              style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Collections'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.receipt_long_rounded),
                          title:
                              const Text('Invoices', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Invoices'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.pending_actions_rounded),
                          title: const Text('Dues', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Dues'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.summarize_rounded),
                          title:
                              const Text('Reports', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Reports'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings_rounded),
                          title:
                              const Text('Settings', style: TextStyle(fontSize: 14)),
                          onTap: () => _toastComingSoon('Settings'),
                          contentPadding: EdgeInsets.zero,
                        ),

                        const Spacer(),

                        ListTile(
                          leading: const Icon(
                            Icons.logout_rounded,
                            color: Colors.redAccent,
                          ),
                          title: const Text(
                            'Logout',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                          onTap: _logout,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Coming soon: $label'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(milliseconds: 900),
              ),
            );
          },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: Colors.grey.shade800),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Placeholder screens so this file compiles immediately.
/// Replace with real pages later.
class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Center(
        child: Text(
          '$title screen (connect your real page here)',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

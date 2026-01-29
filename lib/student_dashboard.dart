import 'package:flutter/material.dart';
import 'login_page.dart';

class StudentDashboardScreen extends StatefulWidget {
  final String username;
  final String roleDescription;

  const StudentDashboardScreen({
    super.key,
    required this.username,
    required this.roleDescription,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
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

  void _logout() {
    // You can clear session data if any, using SharedPreferences or similar.
    if (_isMenuOpen) _toggleMenu();

    // Navigate to login page and remove all previous routes from the stack
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // -------- Navigation helper (closes menu then pushes page) --------
  void _openFromMenu(Widget page) {
    if (_isMenuOpen) _toggleMenu();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    });
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
              Icon(Icons.more_horiz_rounded, color: Colors.grey.shade400, size: 20),
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

  void _toastComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Coming soon: $label'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
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
                          // Hamburger menu button
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
                                  Color(0xFFF97316),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'S1',
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
                                  'Welcome, Student',
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
                              'Overview',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // ---- SMALL ROUNDED CARDS IN 2x2 GRID ----
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.fact_check_rounded,
                                    title: 'Attendance (This Month)',
                                    value: '92%',
                                    subtitle: 'Present: 22 · Absent: 2',
                                    color: const Color(0xFF22C55E),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.menu_book_rounded,
                                    title: 'Subjects',
                                    value: '6',
                                    subtitle: 'Current semester',
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.schedule_rounded,
                                    title: 'Today\'s Classes',
                                    value: '4',
                                    subtitle: 'Next: 11:30 AM',
                                    color: const Color(0xFF7C3AED),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.payments_rounded,
                                    title: 'Fees Due',
                                    value: '₹ 3,500',
                                    subtitle: 'Due in 10 days',
                                    color: const Color(0xFFF97316),
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
                                  icon: Icons.person_rounded,
                                  label: 'My Profile',
                                  color: const Color(0xFF2563EB),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'My Profile'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.calendar_month_rounded,
                                  label: 'Routine',
                                  color: const Color(0xFF7C3AED),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Routine'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.fact_check_rounded,
                                  label: 'Attendance',
                                  color: const Color(0xFF16A34A),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Attendance'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.receipt_long_rounded,
                                  label: 'Fee Invoices',
                                  color: const Color(0xFFF97316),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Fee Invoices'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.assessment_rounded,
                                  label: 'Results',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Results'),
                                  ),
                                ),
                                _QuickActionChip(
                                  icon: Icons.campaign_rounded,
                                  label: 'Notices',
                                  color: const Color(0xFF6366F1),
                                  onTap: () => _openFromMenu(
                                    const _PlaceholderPage(title: 'Notices'),
                                  ),
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
                                    icon: Icons.campaign_rounded,
                                    title: 'New notice published',
                                    subtitle: 'Internal exam schedule · 10 min ago',
                                  ),
                                  Divider(height: 16),
                                  _ActivityRow(
                                    icon: Icons.menu_book_rounded,
                                    title: 'Assignment added',
                                    subtitle: 'DBMS · Due in 3 days',
                                  ),
                                  Divider(height: 16),
                                  _ActivityRow(
                                    icon: Icons.payments_rounded,
                                    title: 'Fee invoice generated',
                                    subtitle: 'Semester fee · 1 hour ago',
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
              // Tap outside to close
              GestureDetector(
                onTap: _toggleMenu,
                child: Container(color: Colors.black.withOpacity(0.25)),
              ),
              SlideTransition(
                position: _menuSlide,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.7,
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
                              Icons.school_rounded,
                              size: 22,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Student Menu',
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
                          title: const Text('Dashboard', style: TextStyle(fontSize: 14)),
                          onTap: _toggleMenu,
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_rounded),
                          title: const Text('My Profile', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'My Profile'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.fact_check_rounded),
                          title: const Text('Attendance', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Attendance'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.calendar_month_rounded),
                          title: const Text('Routine', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Routine'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.receipt_long_rounded),
                          title: const Text('Fees', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Fees'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.assessment_rounded),
                          title: const Text('Results', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Results'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.campaign_rounded),
                          title: const Text('Notices', style: TextStyle(fontSize: 14)),
                          onTap: () => _openFromMenu(
                            const _PlaceholderPage(title: 'Notices'),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings_rounded),
                          title: const Text('Settings', style: TextStyle(fontSize: 14)),
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

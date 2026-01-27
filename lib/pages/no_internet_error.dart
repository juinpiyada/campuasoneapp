// lib/no_internet_error.dart
import 'package:flutter/material.dart';

class NoInternetErrorPage extends StatelessWidget {
  final VoidCallback? onRetry;
  final String title;
  final String message;

  const NoInternetErrorPage({
    super.key,
    this.onRetry,
    this.title = "No Internet Connection",
    this.message =
        "Looks like you’re offline. Please check your Wi-Fi or mobile data and try again.",
  });

  @override
  Widget build(BuildContext context) {
    // Tailwind-like tokens
    const bg = Color(0xFFF8FAFC); // slate-50
    const cardBorder = Color(0xFFE2E8F0); // slate-200
    const text = Color(0xFF0F172A); // slate-900
    const muted = Color(0xFF64748B); // slate-500
    const primary = Color(0xFF2563EB); // blue-600
    const primaryHover = Color(0xFF1D4ED8); // blue-700

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // "Card" container (Tailwind-style)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cardBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // GIF
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            color: const Color(0xFFF1F5F9), // slate-100
                            padding: const EdgeInsets.all(10),
                            child: Image.asset(
                              "lib/img/nointernet.gif",
                              height: 220,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stack) {
                                return Container(
                                  height: 220,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.wifi_off_rounded,
                                    size: 64,
                                    color: muted,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Title
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: text,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Message
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Buttons row
                        Row(
                          children: [
                            Expanded(
                              child: _TailwindButton(
                                label: "Retry",
                                icon: Icons.refresh_rounded,
                                background: primary,
                                backgroundPressed: primaryHover,
                                foreground: Colors.white,
                                onPressed: onRetry ??
                                    () {
                                      Navigator.of(context).maybePop();
                                    },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TailwindOutlineButton(
                                label: "Go Back",
                                icon: Icons.arrow_back_rounded,
                                border: cardBorder,
                                foreground: text,
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Small tips (Tailwind "badge" style)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: const [
                            _TipChip(
                              icon: Icons.wifi_rounded,
                              text: "Check Wi-Fi",
                            ),
                            _TipChip(
                              icon: Icons.signal_cellular_alt_rounded,
                              text: "Mobile Data",
                            ),
                            _TipChip(
                              icon: Icons.airplanemode_inactive_rounded,
                              text: "Airplane Mode Off",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Footer note
                  const Text(
                    "If the issue continues, restart your router or try again after a few minutes.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8), // slate-400
                      height: 1.3,
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
}

/* ---------------- Tailwind-style Widgets ---------------- */

class _TailwindButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color backgroundPressed;
  final Color foreground;
  final VoidCallback onPressed;

  const _TailwindButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.backgroundPressed,
    required this.foreground,
    required this.onPressed,
  });

  @override
  State<_TailwindButton> createState() => _TailwindButtonState();
}

class _TailwindButtonState extends State<_TailwindButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 46,
        decoration: BoxDecoration(
          color: _pressed ? widget.backgroundPressed : widget.background,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: widget.foreground),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TailwindOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color border;
  final Color foreground;
  final VoidCallback onPressed;

  const _TailwindOutlineButton({
    required this.label,
    required this.icon,
    required this.border,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: foreground),
        label: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: border, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // slate-100
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)), // slate-200
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF475569)), // slate-600
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

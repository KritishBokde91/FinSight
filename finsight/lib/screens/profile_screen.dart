import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '...';
  String _email = '...';
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await AuthService.getDisplayName();
    final userId = await AuthService.getUserId();
    final email = await AuthService.getEmail();
    if (mounted) {
      setState(() {
        _name = name ?? 'User';
        _userId = userId ?? '';
        _email = email ?? '';
      });
    }
    // Try to load full profile from API
    if (userId != null) {
      try {
        final user = await AuthService.getProfile(userId);
        if (mounted && user != null) {
          setState(() {
            _name = user['display_name'] ?? _name;
            _email = user['email'] ?? _email;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Logout',
          style: GoogleFonts.outfit(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Logout',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.logout();
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // ── Header ──
              Row(
                children: [
                  Text(
                    'Profile',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 30),

              // ── Avatar ──
              Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.gold.withAlpha(40),
                          AppTheme.cyan.withAlpha(25),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.gold.withAlpha(60),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.gold.withAlpha(25),
                          blurRadius: 24,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                        style: GoogleFonts.outfit(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold,
                        ),
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8)),

              const SizedBox(height: 16),

              Text(
                _name,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 100.ms),

              const SizedBox(height: 4),

              Text(
                _email,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textMuted,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 150.ms),

              const SizedBox(height: 36),

              // ── Menu Items ──
              _buildMenuItem(
                icon: Icons.person_outline_rounded,
                title: 'User ID',
                subtitle: _userId.isNotEmpty
                    ? '${_userId.substring(0, 8)}...'
                    : 'N/A',
                delay: 200,
              ),
              _buildMenuItem(
                icon: Icons.analytics_outlined,
                title: 'ML Model',
                subtitle: 'XGBoost — 99.93% accuracy',
                delay: 250,
              ),
              _buildMenuItem(
                icon: Icons.storage_outlined,
                title: 'Backend',
                subtitle: 'Supabase + FastAPI',
                delay: 300,
              ),
              _buildMenuItem(
                icon: Icons.auto_awesome_outlined,
                title: 'AI Assistant',
                subtitle: 'Vicuna 13B + Web Crawling',
                delay: 350,
              ),
              _buildMenuItem(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                subtitle: 'FinSight v3.0',
                delay: 400,
              ),

              const SizedBox(height: 24),

              // ── Logout Button ──
              GestureDetector(
                onTap: _logout,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.error.withAlpha(40)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: AppTheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Logout',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 500.ms),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    int delay = 0,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.gold.withAlpha(12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.gold, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textMuted.withAlpha(80),
            size: 20,
          ),
        ],
      ),
    ).animate().fadeIn(
      duration: 400.ms,
      delay: Duration(milliseconds: delay),
    );
  }
}

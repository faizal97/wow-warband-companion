import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// Shows an update dialog if a newer version is available.
class UpdateDialog {
  static Future<void> checkAndShow(BuildContext context) async {
    final update = await UpdateService.checkForUpdate();
    if (update == null) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _UpdateDialogContent(update: update),
    );
  }

}

enum _UpdateState { prompt, downloading, error }

class _UpdateDialogContent extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateDialogContent({required this.update});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent>
    with TickerProviderStateMixin {
  _UpdateState _state = _UpdateState.prompt;
  double _progress = 0;
  String? _errorMessage;

  static const _accent = Color(0xFF3FC7EB);
  static const _accentDeep = Color(0xFF1A8AAF);
  static const _errorColor = Color(0xFFFF4D4D);

  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;

  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Color get _activeColor => _state == _UpdateState.error ? _errorColor : _accent;

  Future<void> _startDownload() async {
    if (widget.update.downloadUrl == null) return;

    if (kIsWeb) {
      launchUrl(
        Uri.parse(widget.update.downloadUrl!),
        mode: LaunchMode.externalApplication,
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
    });

    try {
      await UpdateService.downloadAndInstall(
        widget.update.downloadUrl!,
        (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state != _UpdateState.downloading,
      child: Center(
        child: AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnim.value,
            child: Opacity(opacity: _fadeAnim.value, child: child),
          ),
          child: _buildDialog(),
        ),
      ),
    );
  }

  Widget _buildDialog() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = _pulseAnim.value;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 36),
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1C1C2C),
                AppTheme.surface,
                Color(0xFF121218),
              ],
              stops: [0.0, 0.4, 1.0],
            ),
            border: Border.all(
              color: _activeColor.withValues(alpha: 0.12 + glow * 0.12),
              width: 1,
            ),
            boxShadow: [
              // Arcane outer glow
              BoxShadow(
                color: _activeColor.withValues(alpha: 0.06 + glow * 0.08),
                blurRadius: 32,
                spreadRadius: 4,
              ),
              // Tight accent rim
              BoxShadow(
                color: _activeColor.withValues(alpha: 0.03 + glow * 0.05),
                blurRadius: 12,
                spreadRadius: 1,
              ),
              // Depth shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDecorativeLine(),
              const SizedBox(height: 16),
              _buildIcon(),
              const SizedBox(height: 16),
              _buildTitle(),
              const SizedBox(height: 6),
              _buildVersionBadge(),
              const SizedBox(height: 4),
              _buildDecorativeLine(),
              const SizedBox(height: 12),
              _buildBody(),
              const SizedBox(height: 20),
              _buildActions(),
              const SizedBox(height: 4),
              _buildDecorativeLine(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Decorative diamond separator ──────────────────────────────────

  Widget _buildDecorativeLine() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _activeColor.withValues(alpha: 0.25),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) => Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _activeColor.withValues(alpha: 0.2 + _pulseAnim.value * 0.3),
                  border: Border.all(
                    color: _activeColor.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _activeColor.withValues(alpha: _pulseAnim.value * 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _activeColor.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Icon with radial glow ────────────────────────────────────────

  Widget _buildIcon() {
    final IconData icon;
    switch (_state) {
      case _UpdateState.prompt:
        icon = Icons.system_update_rounded;
      case _UpdateState.downloading:
        icon = Icons.downloading_rounded;
      case _UpdateState.error:
        icon = Icons.error_outline_rounded;
    }

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        final p = _pulseAnim.value;
        return Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _activeColor.withValues(alpha: p * 0.12),
                _activeColor.withValues(alpha: p * 0.04),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
              radius: 0.9,
            ),
          ),
          child: Center(
            child: Transform.scale(
              scale: 1.0 + p * 0.04,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _activeColor.withValues(alpha: 0.06),
                  border: Border.all(
                    color: _activeColor.withValues(alpha: 0.2 + p * 0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _activeColor.withValues(alpha: p * 0.2),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    color: _activeColor,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Title ────────────────────────────────────────────────────────

  Widget _buildTitle() {
    final String title;
    switch (_state) {
      case _UpdateState.prompt:
        title = 'UPDATE AVAILABLE';
      case _UpdateState.downloading:
        title = 'DOWNLOADING';
      case _UpdateState.error:
        title = 'DOWNLOAD FAILED';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        title,
        key: ValueKey(title),
        style: GoogleFonts.rajdhani(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  // ─── Version badge ────────────────────────────────────────────────

  Widget _buildVersionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: _accent.withValues(alpha: 0.06),
        border: Border.all(
          color: _accent.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v${widget.update.currentVersion}',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 12,
              color: _accent.withValues(alpha: 0.6),
            ),
          ),
          Text(
            'v${widget.update.latestVersion}',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Body (prompt / casting bar / error) ──────────────────────────

  Widget _buildBody() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (_state) {
          _UpdateState.prompt => _buildPromptBody(),
          _UpdateState.downloading => _buildCastingBar(),
          _UpdateState.error => _buildErrorBody(),
        },
      ),
    );
  }

  Widget _buildPromptBody() {
    return Text(
      key: const ValueKey('prompt'),
      'A new version is available with improvements and bug fixes.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 13,
        color: AppTheme.textSecondary,
        height: 1.5,
      ),
    );
  }

  Widget _buildErrorBody() {
    return Column(
      key: const ValueKey('error'),
      children: [
        Text(
          _errorMessage ?? 'Something went wrong.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: _errorColor.withValues(alpha: 0.8),
            height: 1.5,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ─── WoW casting bar ──────────────────────────────────────────────

  Widget _buildCastingBar() {
    final percent = (_progress * 100).toInt();

    return Column(
      key: const ValueKey('casting'),
      children: [
        // Casting bar container
        Container(
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF080810),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _accent.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              // Inset depth
              const BoxShadow(
                color: Colors.black,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                // Inner shadow overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.4),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),

                // Progress fill
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _progress.clamp(0.005, 1.0),
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                _accentDeep,
                                _accent,
                                Color(0xFF5DD8F7),
                              ],
                              stops: [0.0, 0.6, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.3 + _pulseAnim.value * 0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          // Top highlight stripe
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Shimmer sweep
                if (_progress > 0.01)
                  AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, _) {
                      return ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _progress.clamp(0.0, 1.0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final shimmerWidth = constraints.maxWidth * 0.4;
                                final totalTravel = constraints.maxWidth + shimmerWidth;
                                return Transform.translate(
                                  offset: Offset(
                                    _shimmerController.value * totalTravel - shimmerWidth,
                                    0,
                                  ),
                                  child: Container(
                                    width: shimmerWidth,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          Colors.white.withValues(alpha: 0.12),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // Percentage text
                Center(
                  child: Text(
                    '$percent%',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Preparing update...',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────

  Widget _buildActions() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (_state) {
        _UpdateState.prompt => _buildPromptActions(),
        _UpdateState.downloading => const SizedBox.shrink(key: ValueKey('dl')),
        _UpdateState.error => _buildErrorActions(),
      },
    );
  }

  Widget _buildPromptActions() {
    return Column(
      key: const ValueKey('prompt_actions'),
      children: [
        SizedBox(
          width: double.infinity,
          height: 44,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.15 + _pulseAnim.value * 0.1),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: ElevatedButton(
              onPressed: _startDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                'INSTALL UPDATE',
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Later',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorActions() {
    return Column(
      key: const ValueKey('error_actions'),
      children: [
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: () => setState(() => _state = _UpdateState.prompt),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _accent.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'TRY AGAIN',
              style: GoogleFonts.rajdhani(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: _accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Dismiss',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

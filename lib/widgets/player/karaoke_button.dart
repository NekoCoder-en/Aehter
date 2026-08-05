import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_colors.dart';

class KaraokeButton extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;

  const KaraokeButton({
    Key? key,
    required this.isActive,
    required this.onTap,
  }) : super(key: key);

  @override
  State<KaraokeButton> createState() => _KaraokeButtonState();
}

class _KaraokeButtonState extends State<KaraokeButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(KaraokeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.animateTo(0.0, duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.isActive)
                  Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withOpacity(0.3),
                      ),
                    ),
                  ),
                AnimatedRotation(
                  turns: widget.isActive ? -0.06 : 0.0, // Inclinado aprox -22 grados
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: FaIcon(
                    widget.isActive ? FontAwesomeIcons.microphoneLines : FontAwesomeIcons.microphone,
                    color: widget.isActive ? AppColors.primary : Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

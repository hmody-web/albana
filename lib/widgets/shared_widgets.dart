import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────
//  PREMIUM APP BAR
// ─────────────────────────────────────────────

class PremiumAppBar extends StatelessWidget {
  final String title;
  final bool isDark;
  const PremiumAppBar({super.key, required this.title, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      toolbarHeight: 68,
      automaticallyImplyLeading: false,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withOpacity(0.6)
                  : Colors.white.withOpacity(0.75),
              border: Border(
                bottom: BorderSide(
                  color: gold.withOpacity(0.18),
                  width: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
      title: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE8B84B), Color(0xFF8A5E00)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: gold.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: gold,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  GOLD DIVIDER
// ─────────────────────────────────────────────

class GoldDivider extends StatelessWidget {
  const GoldDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Color(0xFFD4A017), Colors.transparent],
          ),
        ),
      );
}

// ─────────────────────────────────────────────
//  SECTION TITLE
// ─────────────────────────────────────────────

class SectionTitle extends StatelessWidget {
  final String text;
  final bool isDark;
  const SectionTitle(this.text, {super.key, required this.isDark});
  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFD4A017),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      );
}

// ─────────────────────────────────────────────
//  APP TAG
// ─────────────────────────────────────────────

class AppTag extends StatelessWidget {
  final String label;
  final IconData icon;
  const AppTag({super.key, required this.label, required this.icon});
  static const gold = Color(0xFFD4A017);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: gold),
            const SizedBox(width: 3),
            Text(label,
                style: const TextStyle(
                    color: gold, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────
//  SETTINGS CARD
// ─────────────────────────────────────────────

class AppSettingsCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const AppSettingsCard({super.key, required this.child, required this.isDark});
  static const gold = Color(0xFFD4A017);
  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────
//  HERO WATERMARK PATTERN
// ─────────────────────────────────────────────

class HeroWatermarkPattern extends StatelessWidget {
  final bool isDark;
  const HeroWatermarkPattern({super.key, required this.isDark});

  static const double _scale = 0.66;
  static const double _offsetX = 0.0;
  static const double _speed = 30.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: isDark ? 0.4 : 0.7,
        child: TiledImagePainter(
          assetPath: 'assets/images/bg.png',
          scale: _scale,
          offsetX: _offsetX,
          speed: _speed,
          color: isDark ? Colors.white : const Color(0xFF8A5E00),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TILED IMAGE PAINTER
// ─────────────────────────────────────────────

class TiledImagePainter extends StatefulWidget {
  final String assetPath;
  final double scale;
  final double offsetX;
  final double speed;
  final Color color;

  const TiledImagePainter({
    super.key,
    required this.assetPath,
    required this.scale,
    required this.offsetX,
    required this.speed,
    required this.color,
  });

  @override
  State<TiledImagePainter> createState() => _TiledImagePainterState();
}

class _TiledImagePainterState extends State<TiledImagePainter>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;
  late Ticker _ticker;
  double _offsetY = 0.0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1000000.0;
      _last = elapsed;
      if (mounted) setState(() => _offsetY -= widget.speed * dt);
    })
      ..start();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load(widget.assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) return const SizedBox.expand();
    return CustomPaint(
      painter: WatermarkPainter(
        image: _image!,
        scale: widget.scale,
        offsetX: widget.offsetX,
        offsetY: _offsetY,
        color: widget.color,
      ),
      child: const SizedBox.expand(),
    );
  }
}

// ─────────────────────────────────────────────
//  WATERMARK PAINTER
// ─────────────────────────────────────────────

class WatermarkPainter extends CustomPainter {
  final ui.Image image;
  final double scale;
  final double offsetX;
  final double offsetY;
  final Color color;

  WatermarkPainter({
    required this.image,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    final tileW = image.width * scale;
    final tileH = image.height * scale;
    final startX = (offsetX % tileW) - tileW;
    final startY = offsetY % tileH;
    for (double y = startY - tileH * 2; y < size.height + tileH; y += tileH) {
      for (double x = startX - tileW; x < size.width + tileW; x += tileW) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(x, y, tileW, tileH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(WatermarkPainter old) => true;
}
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Unified in-app notice shown near the top of the screen.
/// It intentionally avoids exposing raw exception/server details to users.
class AppNotice {
  AppNotice._();

  static OverlayEntry? _activeEntry;
  static Timer? _timer;

  static String sanitize(String message) {
    var text = message.trim();
    if (text.isEmpty) return 'حدث خطأ. حاول مرة أخرى.';

    // Never expose technical exception / Firebase / HTTP details in UI notices.
    text = text
        .replaceAll(RegExp(r'\[firebase_auth/[^\]]+\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'Firebase[^\n]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'HTTP\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'Exception:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'خطأ:\s*.*$', caseSensitive: false), 'حدث خطأ. حاول مرة أخرى.')
        .replaceAll(RegExp(r':\s*\$?e\b.*$', caseSensitive: false), '')
        .trim();

    // Generic, clean failure wording.
    if (text.contains('فشل تسجيل الدخول') || text.contains('تعذر تسجيل الدخول')) {
      return 'تعذر تسجيل الدخول. حاول مرة أخرى.';
    }
    if (text.startsWith('تعذر حذف الحساب') || text.startsWith('فشل حذف')) {
      return 'تعذر إتمام الحذف. حاول مرة أخرى.';
    }
    if (text.startsWith('فشل إرسال التعليق') || text.startsWith('خطأ')) {
      return 'تعذر إرسال التعليق. حاول مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ. حاول مرة أخرى.' : text;
  }

  static bool _looksSuccessful(String text) {
    return text.contains('تم ') ||
        text.contains('بنجاح') ||
        text.contains('✓') ||
        text.contains('نجاح');
  }

  static bool _looksWarning(String text) {
    return text.contains('يرجى') ||
        text.contains('يجب') ||
        text.contains('غير موجود') ||
        text.contains('غير مفعلة') ||
        text.contains('سجل دخول');
  }

  static void show(
    BuildContext context,
    String message, {
    bool? success,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final clean = sanitize(message);
    final isSuccess = success ?? _looksSuccessful(clean);
    final isWarning = !isSuccess && _looksWarning(clean);

    _timer?.cancel();
    _activeEntry?.remove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        final isDark = Theme.of(overlayContext).brightness == Brightness.dark;
        final top = media.padding.top + 10;
        final maxWidth = media.size.width < 520 ? media.size.width - 28 : 420.0;

        final icon = isSuccess
            ? Icons.check_circle_rounded
            : isWarning
                ? Icons.info_rounded
                : Icons.error_rounded;
        final accent = isSuccess
            ? const Color(0xFF3FC380)
            : isWarning
                ? const Color(0xFFD4A017)
                : const Color(0xFFFF6B6B);

        return Positioned(
          top: top,
          right: 14,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              tween: Tween(begin: 0, end: 1),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Transform.translate(
                offset: Offset(28 * (1 - value), 0),
                child: Opacity(opacity: value, child: child),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF171717) : Colors.white)
                            .withOpacity(0.88),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: accent.withOpacity(0.35)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.35 : 0.14),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.rtl,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.13),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: accent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              clean,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF211A0D),
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
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
          ),
        );
      },
    );

    _activeEntry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () {
      if (_activeEntry == entry) {
        entry.remove();
        _activeEntry = null;
      }
    });
  }

  static String? _extractText(Widget? widget) {
    if (widget == null) return null;
    if (widget is Text) return widget.data;
    if (widget is Directionality) return _extractText(widget.child);
    if (widget is Container && widget.child != null) return _extractText(widget.child!);
    if (widget is Padding) return _extractText(widget.child);
    if (widget is Center) return _extractText(widget.child);
    if (widget is Align && widget.child != null) return _extractText(widget.child!);
    if (widget is Row) {
      for (final child in widget.children) {
        final value = _extractText(child);
        if (value != null && value.trim().isNotEmpty) return value;
      }
    }
    if (widget is Column) {
      for (final child in widget.children) {
        final value = _extractText(child);
        if (value != null && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Compatibility bridge used while migrating old SnackBar calls.
  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    final message = _extractText(snackBar.content) ?? 'تم تنفيذ العملية.';
    show(context, message);
  }
}

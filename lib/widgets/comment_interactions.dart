import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../services/user_safety_service.dart';

const Color _commentGold = Color(0xFFD4A017);

/// سحب التعليق إلى اليمين للرد، بدون حذف أو إخفاء العنصر.
class CommentSwipeReply extends StatefulWidget {
  final Widget child;
  final VoidCallback? onReply;
  final bool enabled;
  final bool isDark;
  final ValueChanged<bool>? onSwipeStateChanged;
  final String safetyUserName;
  final String safetyUserAvatar;
  final String safetyUserEmail;
  final String safetySourceType;
  final int safetySourceId;
  final int safetyCommentId;
  final String safetyCommentText;

  const CommentSwipeReply({
    super.key,
    required this.child,
    required this.onReply,
    required this.isDark,
    this.enabled = true,
    this.onSwipeStateChanged,
    this.safetyUserName='', this.safetyUserAvatar='', this.safetyUserEmail='', this.safetySourceType='profile', this.safetySourceId=0, this.safetyCommentId=0, this.safetyCommentText='',
  });

  @override
  State<CommentSwipeReply> createState() => _CommentSwipeReplyState();
}

class _CommentSwipeReplyState extends State<CommentSwipeReply> {
  static const double _maxOffset = 86;
  static const double _triggerOffset = 52;

  double _offset = 0;
  bool _dragging = false;
  bool _hapticDone = false;
  bool _pressed = false;

  void _start(DragStartDetails details) {
    if (!widget.enabled || widget.onReply == null) return;
    widget.onSwipeStateChanged?.call(true);
    setState(() {
      _dragging = true;
      _hapticDone = false;
    });
  }

  void _update(DragUpdateDetails details) {
    if (!widget.enabled || widget.onReply == null) return;

    // نسمح فقط بالسحب الفيزيائي إلى اليمين.
    final next = (_offset + details.delta.dx).clamp(0.0, _maxOffset).toDouble();
    if (next == _offset) return;

    if (!_hapticDone && next >= _triggerOffset) {
      _hapticDone = true;
      HapticFeedback.selectionClick();
    }

    setState(() => _offset = next);
  }

  void _finish() {
    if (!widget.enabled || widget.onReply == null) {
      widget.onSwipeStateChanged?.call(false);
      return;
    }
    final shouldReply = _offset >= _triggerOffset;

    widget.onSwipeStateChanged?.call(false);
    setState(() {
      _dragging = false;
      _offset = 0;
      _hapticDone = false;
    });

    if (shouldReply) {
      HapticFeedback.lightImpact();
      Future<void>.delayed(const Duration(milliseconds: 90), () {
        if (mounted) widget.onReply?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    UserSafetyService.ensureLoaded();
    final progress = (_offset / _triggerOffset).clamp(0.0, 1.0);
    final hintColor = widget.isDark ? Colors.white70 : Colors.black54;

    final sheetLikeBg = widget.isDark
        ? const Color.fromARGB(83, 24, 24, 24)
        : Colors.white;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: UserSafetyService.blockedEmails,
      child: ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.75 + (0.25 * progress),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 23, 121, 212).withOpacity(widget.isDark ? 0.15 : 0.11),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color.fromARGB(255, 23, 121, 212).withOpacity(0.20)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply_rounded, color: const Color.fromARGB(255, 49, 142, 230), size: 18 + (2 * progress)),
                          const SizedBox(width: 5),
                          Text(
                            progress >= 1 ? ' رد' : 'رد',
                            style: TextStyle(
                              color: progress >= 1 ? const Color.fromARGB(255, 46, 141, 230) : hintColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
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
          AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            decoration: BoxDecoration(
              color: _dragging ? sheetLikeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    _dragging ? (widget.isDark ? 0.22 : 0.08) : 0.0,
                  ),
                  blurRadius: 10.0,
                  spreadRadius: 0.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) { if (mounted) setState(() => _pressed = true); },
              onTapUp: (_) { if (mounted) setState(() => _pressed = false); },
              onTapCancel: () { if (mounted) setState(() => _pressed = false); },
              onHorizontalDragStart: _start,
              onHorizontalDragUpdate: _update,
              onHorizontalDragEnd: (_) => _finish(),
              onHorizontalDragCancel: _finish,
              onLongPressStart: widget.safetyUserEmail.trim().isEmpty ? null : (_) async {
                if (mounted) setState(() => _pressed = true);
                await HapticFeedback.lightImpact();
              },
              onLongPressEnd: widget.safetyUserEmail.trim().isEmpty ? null : (_) {
                if (mounted) setState(() => _pressed = false);
                UserSafetyService.showActions(context,isDark:widget.isDark,name:widget.safetyUserName,email:widget.safetyUserEmail,avatar:widget.safetyUserAvatar,sourceType:widget.safetySourceType,sourceId:widget.safetySourceId,commentId:widget.safetyCommentId,commentText:widget.safetyCommentText);
              },
              child: AnimatedScale(
                duration: const Duration(milliseconds: 110),
                scale: _pressed ? 0.985 : 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  decoration: BoxDecoration(
                    color: _pressed ? _commentGold.withOpacity(widget.isDark ? .075 : .055) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
      builder: (_, blocked, child) {
        final email = widget.safetyUserEmail.trim().toLowerCase();
        if (email.isNotEmpty && blocked.contains(email)) return const SizedBox.shrink();
        return child!;
      },
    );
  }
}

/// صف موحد: إظهار/إخفاء الردود | رد
/// بترتيب RTL تكون "رد" على اليسار مثل المطلوب.
class CommentThreadActions extends StatelessWidget {
  final bool expanded;
  final int repliesCount;
  final VoidCallback onToggle;
  final VoidCallback? onReply;
  final bool isDark;
  final double translateY;

  const CommentThreadActions({
    super.key,
    required this.expanded,
    required this.repliesCount,
    required this.onToggle,
    required this.onReply,
    required this.isDark,
    this.translateY = 3,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor = isDark ? const Color(0xFF9A9B9D) : const Color(0xFF717274);

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  Icon(
                    expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: actionColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    expanded ? 'إخفاء الردود' : 'إظهار الردود ($repliesCount)',
                    style: TextStyle(
                      color: actionColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: actionColor.withOpacity(0.35),
          ),
          InkWell(
            onTap: onReply,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'رد',
                style: TextStyle(
                  color: actionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentProfileStats {
  final DateTime? joinedAt;
  final int comments;
  final int likes;
  final bool partial;

  const _CommentProfileStats({
    required this.joinedAt,
    required this.comments,
    required this.likes,
    required this.partial,
  });
}

class _ProfileCacheEntry {
  final DateTime savedAt;
  final _CommentProfileStats data;

  const _ProfileCacheEntry(this.savedAt, this.data);
}

final Map<String, _ProfileCacheEntry> _profileCache = <String, _ProfileCacheEntry>{};

Future<void> showCommentUserProfile({
  required BuildContext context,
  required bool isDark,
  required String userName,
  required String userAvatar,
  required String userEmail,
  DateTime? fallbackJoinedAt,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.48),
    builder: (_) => _CommentUserProfileSheet(
      isDark: isDark,
      userName: userName,
      userAvatar: userAvatar,
      userEmail: userEmail,
      fallbackJoinedAt: fallbackJoinedAt,
    ),
  );
}

class _CommentUserProfileSheet extends StatefulWidget {
  final bool isDark;
  final String userName;
  final String userAvatar;
  final String userEmail;
  final DateTime? fallbackJoinedAt;

  const _CommentUserProfileSheet({
    required this.isDark,
    required this.userName,
    required this.userAvatar,
    required this.userEmail,
    required this.fallbackJoinedAt,
  });

  @override
  State<_CommentUserProfileSheet> createState() => _CommentUserProfileSheetState();
}

class _CommentUserProfileSheetState extends State<_CommentUserProfileSheet> {
  late Future<_CommentProfileStats> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadStats();
  }

  String get _normalizedEmail => widget.userEmail.trim().toLowerCase();

  DateTime? _parseServerDate(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return null;
    try {
      final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
      final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(normalized);
      return DateTime.parse(hasZone ? normalized : '${normalized}Z').toLocal();
    } catch (_) {
      return DateTime.tryParse(raw)?.toLocal();
    }
  }

  List<int> _idsFromPayload(dynamic decoded, List<String> keys) {
    dynamic rows = decoded;
    if (decoded is Map) {
      for (final key in keys) {
        if (decoded[key] is List) {
          rows = decoded[key];
          break;
        }
      }
    }
    if (rows is! List) return const <int>[];
    return rows
        .whereType<Map>()
        .map((row) => int.tryParse('${row['id'] ?? 0}') ?? 0)
        .where((id) => id > 0)
        .toList();
  }

  List<Map<String, dynamic>> _rowsFromPayload(dynamic decoded) {
    dynamic rows = decoded;
    if (decoded is Map && decoded['comments'] is List) rows = decoded['comments'];
    if (rows is! List) return const <Map<String, dynamic>>[];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<_CommentProfileStats> _loadStats() async {
    final email = _normalizedEmail;
    if (email.isEmpty) {
      return _CommentProfileStats(
        joinedAt: widget.fallbackJoinedAt,
        comments: 0,
        likes: 0,
        partial: true,
      );
    }

    final cached = _profileCache[email];
    if (cached != null && DateTime.now().difference(cached.savedAt) < const Duration(minutes: 5)) {
      return cached.data;
    }

    DateTime? joinedAt = widget.fallbackJoinedAt;
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      final candidates = <String>{
        (current.email ?? '').trim().toLowerCase(),
        current.uid.trim().toLowerCase(),
      }..removeWhere((e) => e.isEmpty);
      if (candidates.contains(email)) {
        joinedAt = current.metadata.creationTime ?? joinedAt;
      }
    }

    int commentsCount = 0;
    int likesCount = 0;
    bool partial = false;

    try {
      final responses = await Future.wait([
        http.get(Uri.parse('https://majidalbana.com/admin/posts/load_posts.php')).timeout(const Duration(seconds: 12)),
        http.get(Uri.parse('https://majidalbana.com/admin/pdf-posts/load_pdf_posts.php')).timeout(const Duration(seconds: 12)),
      ]);

      final postsPayload = jsonDecode(utf8.decode(responses[0].bodyBytes));
      final pdfPayload = jsonDecode(utf8.decode(responses[1].bodyBytes));
      final allPostIds = _idsFromPayload(postsPayload, const ['posts', 'data']);
      final allPdfIds = _idsFromPayload(pdfPayload, const ['posts', 'files', 'data']);

      // حد أمان للطلبات؛ عادةً العدد الفعلي أقل من ذلك.
      const maxItemsPerType = 40;
      final postIds = allPostIds.take(maxItemsPerType).toList();
      final pdfIds = allPdfIds.take(maxItemsPerType).toList();
      partial = allPostIds.length > maxItemsPerType || allPdfIds.length > maxItemsPerType;

      Future<void> scanPost(int postId) async {
        try {
          final result = await Future.wait([
            http.get(Uri.parse('https://majidalbana.com/admin/comments/load_comments.php?post_id=$postId')).timeout(const Duration(seconds: 9)),
            http.get(Uri.parse('https://majidalbana.com/admin/posts/get_likes.php').replace(queryParameters: {
              'post_id': '$postId',
              'user_email': widget.userEmail.trim(),
            })).timeout(const Duration(seconds: 9)),
          ]);

          if (result[0].statusCode == 200) {
            final rows = _rowsFromPayload(jsonDecode(utf8.decode(result[0].bodyBytes)));
            for (final row in rows) {
              if ('${row['user_email'] ?? ''}'.trim().toLowerCase() != email) continue;
              commentsCount++;
              final date = _parseServerDate(row['created_at']);
              if (date != null && (joinedAt == null || date.isBefore(joinedAt!))) joinedAt = date;
            }
          }

          if (result[1].statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(result[1].bodyBytes));
            if (decoded is Map && decoded['liked'] == true) likesCount++;
          }
        } catch (_) {
          partial = true;
        }
      }

      Future<void> scanPdf(int pdfId) async {
        try {
          final response = await http
              .get(Uri.parse('https://majidalbana.com/admin/pdf-comments/load_pdf_comments.php?pdf_id=$pdfId'))
              .timeout(const Duration(seconds: 9));
          if (response.statusCode != 200) {
            partial = true;
            return;
          }
          final rows = _rowsFromPayload(jsonDecode(utf8.decode(response.bodyBytes)));
          for (final row in rows) {
            if ('${row['user_email'] ?? ''}'.trim().toLowerCase() != email) continue;
            commentsCount++;
            final date = _parseServerDate(row['created_at']);
            if (date != null && (joinedAt == null || date.isBefore(joinedAt!))) joinedAt = date;
          }
        } catch (_) {
          partial = true;
        }
      }

      // دفعات صغيرة حتى لا نضغط السيرفر بعشرات الطلبات دفعة واحدة.
      const chunkSize = 6;
      for (var i = 0; i < postIds.length; i += chunkSize) {
        final chunk = postIds.skip(i).take(chunkSize);
        await Future.wait(chunk.map(scanPost));
      }
      for (var i = 0; i < pdfIds.length; i += chunkSize) {
        final chunk = pdfIds.skip(i).take(chunkSize);
        await Future.wait(chunk.map(scanPdf));
      }
    } catch (_) {
      partial = true;
    }

    final data = _CommentProfileStats(
      joinedAt: joinedAt,
      comments: commentsCount,
      likes: likesCount,
      partial: partial,
    );
    _profileCache[email] = _ProfileCacheEntry(DateTime.now(), data);
    return data;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'غير متوفر';
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _avatar() {
    final avatar = widget.userAvatar.trim();
    final name = widget.userName.trim().isEmpty ? 'مستخدم' : widget.userName.trim();
    final initial = name.runes.isEmpty ? '؟' : String.fromCharCode(name.runes.first);

    return Container(
      width: 82,
      height: 82,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE6A1), Color(0xFFD4A017), Color(0xFF8B5F00)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(color: _commentGold.withOpacity(0.24), blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: widget.isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFBF2),
          child: avatar.isNotEmpty
              ? Image.network(
                  avatar,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(initial, style: const TextStyle(color: _commentGold, fontSize: 29, fontWeight: FontWeight.w900)),
                  ),
                )
              : Center(
                  child: Text(initial, style: const TextStyle(color: _commentGold, fontSize: 29, fontWeight: FontWeight.w900)),
                ),
        ),
      ),
    );
  }

  Widget _statCard({required IconData icon, required String value, required String label}) {
    final textPrimary = widget.isDark ? Colors.white : const Color(0xFF211A10);
    final sub = widget.isDark ? Colors.white54 : Colors.black45;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white.withOpacity(0.045) : const Color(0xFFF8F4EB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _commentGold.withOpacity(0.13)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _commentGold, size: 20),
            const SizedBox(height: 5),
            Text(value, style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: sub, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF151515) : Colors.white;
    final textPrimary = widget.isDark ? Colors.white : const Color(0xFF211A10);
    final textSub = widget.isDark ? Colors.white60 : Colors.black54;
    final name = widget.userName.trim().isEmpty ? 'مستخدم' : widget.userName.trim();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.fromLTRB(18, 10, 18, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: _commentGold.withOpacity(0.20))),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(widget.isDark ? 0.55 : 0.18), blurRadius: 34, offset: const Offset(0, -10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: textSub.withOpacity(0.25), borderRadius: BorderRadius.circular(99)),
            ),
            const SizedBox(height: 18),
            _avatar(),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textPrimary, fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'عضو في مجتمع د. ماجد البنا',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FutureBuilder<_CommentProfileStats>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Container(
                    height: 122,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: _commentGold, strokeWidth: 2.5),
                    ),
                  );
                }

                final data = snapshot.data ?? _CommentProfileStats(
                  joinedAt: widget.fallbackJoinedAt,
                  comments: 0,
                  likes: 0,
                  partial: true,
                );
                final total = data.comments + data.likes;

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: _commentGold.withOpacity(widget.isDark ? 0.09 : 0.07),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: _commentGold, size: 19),
                          const SizedBox(width: 8),
                          Text('تاريخ الانضمام', style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              _formatDate(data.joinedAt),
                              textAlign: TextAlign.left,
                              style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _statCard(icon: Icons.chat_bubble_outline_rounded, value: '${data.comments}', label: 'تعليقات'),
                        const SizedBox(width: 8),
                        _statCard(icon: Icons.favorite_border_rounded, value: '${data.likes}', label: 'إعجابات'),
                        const SizedBox(width: 8),
                        _statCard(icon: Icons.auto_awesome_rounded, value: '$total', label: 'المساهمات'),
                      ],
                    ),
                    if (data.partial) ...[
                      const SizedBox(height: 9),
                      Text(
                        'الإحصائية تعتمد على النشاط المتاح حالياً.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textSub.withOpacity(0.75), fontSize: 9.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (!UserSafetyService.isMe(widget.userEmail) && widget.userEmail.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(children:[
                Expanded(child:OutlinedButton.icon(style:OutlinedButton.styleFrom(foregroundColor:_commentGold,side:BorderSide(color:_commentGold.withOpacity(.38)),backgroundColor:_commentGold.withOpacity(widget.isDark ? .07 : .045),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),padding:const EdgeInsets.symmetric(vertical:12)),onPressed:()=>UserSafetyService.showReport(context,isDark:widget.isDark,name:name,email:widget.userEmail,avatar:widget.userAvatar),icon:const Icon(Icons.flag_outlined,size:18),label:const Text('إبلاغ',style:TextStyle(fontWeight:FontWeight.w800)))),
                const SizedBox(width:10),
                Expanded(child:OutlinedButton.icon(style:OutlinedButton.styleFrom(foregroundColor:const Color(0xFFE14D4D),side:BorderSide(color:const Color(0xFFE14D4D).withOpacity(.38)),backgroundColor:const Color(0xFFE14D4D).withOpacity(widget.isDark ? .08 : .05),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),padding:const EdgeInsets.symmetric(vertical:12)),onPressed:()=>UserSafetyService.showBlockConfirm(context,isDark:widget.isDark,name:name,email:widget.userEmail,avatar:widget.userAvatar),icon:const Icon(Icons.block_rounded,size:18),label:const Text('حظر',style:TextStyle(fontWeight:FontWeight.w900)))),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}


/// شارة "رد على @الاسم" الموحدة لتصميم التعليقات.
class CommentReplyContextChip extends StatelessWidget {
  final String name;
  final bool isDark;

  const CommentReplyContextChip({
    super.key,
    required this.name,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF7997BE);
    final safeName = name.trim().isEmpty ? 'المستخدم' : name.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: blue.withOpacity(isDark ? 0.16 : 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.subdirectory_arrow_left_rounded,
              color: blue,
              size: 14,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'رد على',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: blue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '@$safeName',
              textDirection: TextDirection.rtl,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: blue,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// وميض خفيف للتعليق/الرد المفتوح من الإشعار، بدون إطار أو تغيير أبعاد العنصر.
class CommentNotificationFlash extends StatefulWidget {
  final bool active;
  final Widget child;

  const CommentNotificationFlash({
    super.key,
    required this.active,
    required this.child,
  });

  @override
  State<CommentNotificationFlash> createState() => _CommentNotificationFlashState();
}

class _CommentNotificationFlashState extends State<CommentNotificationFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (widget.active) _play();
  }

  @override
  void didUpdateWidget(covariant CommentNotificationFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _play();
  }

  void _play() {
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  final t = Curves.easeInOutCubic.transform(_controller.value);
                  return FractionalTranslation(
                    translation: Offset(1.35 - (2.7 * t), 0),
                    child: FractionallySizedBox(
                      widthFactor: 0.48,
                      alignment: Alignment.centerRight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              Colors.transparent,
                              _commentGold.withOpacity(0.07),
                              _commentGold.withOpacity(0.22),
                              _commentGold.withOpacity(0.07),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.18, 0.5, 0.82, 1],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

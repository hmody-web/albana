import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/shared_widgets.dart';

class PublicationsPage extends StatefulWidget {
  final bool isDark;
  const PublicationsPage({super.key, required this.isDark});

  @override
  State<PublicationsPage> createState() => _PublicationsPageState();
}

class _PublicationsPageState extends State<PublicationsPage> {
  static const gold = Color(0xFFD4A017);

  static const String _postsApi =
      'https://majidalbana.com/admin/posts/load_posts.php';

  late Future<List<_PublicationPost>> _postsFuture;

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
  }

  Future<List<_PublicationPost>> _loadPosts() async {
    final response = await http.get(Uri.parse(_postsApi));

    if (response.statusCode != 200) {
      throw Exception('فشل تحميل المنشورات');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (decoded is! List) {
      throw Exception('صيغة بيانات المنشورات غير صحيحة');
    }

    return decoded
        .whereType<Map>()
        .map((item) => _PublicationPost.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _refreshPosts() async {
    setState(() {
      _postsFuture = _loadPosts();
    });
    await _postsFuture;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F4EE);
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1A1000);
    final subColor = widget.isDark ? Colors.white60 : Colors.black54;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        PremiumAppBar(title: 'المنشورات', isDark: widget.isDark),
        SliverFillRemaining(
          hasScrollBody: true,
          child: Container(
            color: bgColor,
            child: FutureBuilder<List<_PublicationPost>>(
              future: _postsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                if (snapshot.hasError) {
                  return _StateMessage(
                    isDark: widget.isDark,
                    icon: Icons.wifi_off_rounded,
                    title: 'تعذر تحميل المنشورات',
                    message: 'تحقق من الاتصال أو رابط السيرفر ثم حاول مجدداً.',
                    buttonText: 'إعادة المحاولة',
                    onPressed: _refreshPosts,
                  );
                }

                final posts = snapshot.data ?? [];

                if (posts.isEmpty) {
                  return _StateMessage(
                    isDark: widget.isDark,
                    icon: Icons.article_outlined,
                    title: 'لا توجد منشورات',
                    message: 'عند إضافة منشور من لوحة التحكم سيظهر هنا مباشرة.',
                    buttonText: 'تحديث',
                    onPressed: _refreshPosts,
                  );
                }

                return RefreshIndicator(
                  color: gold,
                  onRefresh: _refreshPosts,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      return _PostCard(
                        post: posts[index],
                        isDark: widget.isDark,
                      );
                    },
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

class _PublicationPost {
  final int id;
  final String image;
  final String content;
  final String createdAt;

  const _PublicationPost({
    required this.id,
    required this.image,
    required this.content,
    required this.createdAt,
  });

  factory _PublicationPost.fromJson(Map<String, dynamic> json) {
    return _PublicationPost(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      image: '${json['image'] ?? ''}',
      content: _cleanText('${json['content'] ?? ''}'),
      createdAt: '${json['created_at'] ?? ''}',
    );
  }

  static String _cleanText(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  String get imageUrl {
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    return 'https://majidalbana.com/uploads/$image';
  }
}

class _PostCard extends StatefulWidget {
  final _PublicationPost post;
  final bool isDark;

  const _PostCard({
    required this.post,
    required this.isDark,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  static const gold = Color(0xFFD4A017);
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;
    final dividerColor =
        isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.07);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.image.trim().isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 210,
                child: Image.network(
                  p.imageUrl,
                  fit: BoxFit.cover,
                  headers: const {
                    'Accept': 'image/*',
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: isDark ? const Color(0xFF222222) : const Color(0xFFEFE7D8),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: gold,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) {
                    return Container(
                      height: 210,
                      color: isDark ? const Color(0xFF222222) : const Color(0xFFEFE7D8),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: textSub,
                        size: 42,
                      ),
                    );
                  },
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Text(
                p.content.isEmpty ? 'منشور بدون وصف' : p.content,
                maxLines: _expanded ? null : 4,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14.5,
                  height: 1.75,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_rounded, size: 15, color: textSub),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p.createdAt.isEmpty ? 'منشور حديث' : p.createdAt,
                      style: TextStyle(color: textSub, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, thickness: 0.5, color: dividerColor),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: gold.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: gold.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.article_rounded, size: 15, color: gold),
                        const SizedBox(width: 6),
                        Text(
                          'منشور',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border.all(color: gold.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _expanded ? 'عرض أقل' : 'اقرأ المزيد',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.arrow_back_ios_rounded,
                            size: _expanded ? 17 : 12,
                            color: textPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String message;
  final String buttonText;
  final Future<void> Function() onPressed;

  const _StateMessage({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonText,
    required this.onPressed,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: gold, size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textSub,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: gold,
                side: const BorderSide(color: gold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

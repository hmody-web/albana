import 'package:flutter/material.dart';
import '../widgets/shared_widgets.dart';

class FilesPage extends StatelessWidget {
  final bool isDark;
  const FilesPage({super.key, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black45;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;

    final files = [
      {'name': 'مخططات الأعمدة - مشروع A', 'type': 'PDF', 'size': '٢.٤ MB'},
      {'name': 'تصميم الجسر الرئيسي', 'type': 'DWG', 'size': '٥.١ MB'},
      {'name': 'تقرير فحص التربة', 'type': 'PDF', 'size': '١.٨ MB'},
      {'name': 'نموذج SAP2000 - برج A', 'type': 'SDB', 'size': '٨.٣ MB'},
      {'name': 'كراسة شروط المشروع', 'type': 'DOCX', 'size': '٠.٩ MB'},
    ];

    const typeColors = {
      'PDF': Color(0xFFE53935),
      'DWG': Color(0xFF1E88E5),
      'SDB': Color(0xFF8E24AA),
      'DOCX': Color(0xFF43A047),
    };

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        PremiumAppBar(title: 'الملفات', isDark: isDark),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final f = files[i];
                final color = typeColors[f['type']] ?? gold;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: gold.withOpacity(0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: color.withOpacity(0.2), width: 1),
                        ),
                        child: Center(
                          child: Text(
                            f['type']!,
                            style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f['name']!,
                                style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(Icons.data_usage_rounded,
                                    size: 11, color: textSub),
                                const SizedBox(width: 3),
                                Text(f['size']!,
                                    style: TextStyle(
                                        color: textSub, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: gold.withOpacity(0.1),
                          border: Border.all(
                              color: gold.withOpacity(0.2), width: 1),
                        ),
                        child: const Icon(Icons.download_rounded,
                            color: gold, size: 18),
                      ),
                    ],
                  ),
                );
              },
              childCount: files.length,
            ),
          ),
        ),
      ],
    );
  }
}
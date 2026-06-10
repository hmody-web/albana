import 'package:flutter/material.dart';
import '../widgets/shared_widgets.dart';

class CoursesPage extends StatelessWidget {
  final bool isDark;
  const CoursesPage({super.key, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;

    final courses = [
      {
        'title': 'تصميم الأعمدة والجدران الحاملة',
        'sub': 'دورة متقدمة في الهندسة الإنشائية',
        'duration': '8 ساعات',
        'level': 'متقدم',
        'color': '0xFFE53935',
      },
      {
        'title': 'أساسيات تصميم الخرسانة المسلحة',
        'sub': 'للمهندسين المبتدئين والمتوسطين',
        'duration': '12 ساعة',
        'level': 'مبتدئ',
        'color': '0xFF43A047',
      },
      {
        'title': 'تصميم الجسور والأنفاق',
        'sub': 'دورة شاملة في الهياكل الضخمة',
        'duration': '10 ساعات',
        'level': 'متقدم',
        'color': '0xFF1E88E5',
      },
      {
        'title': 'برنامج SAP2000 التطبيقي',
        'sub': 'تطبيقات عملية متكاملة',
        'duration': '6 ساعات',
        'level': 'متوسط',
        'color': '0xFF8E24AA',
      },
    ];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        PremiumAppBar(title: 'الدورات التدريبية', isDark: isDark),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final c = courses[i];
                final accentColor = Color(int.parse(c['color']!));
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: gold.withOpacity(0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
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
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentColor,
                                accentColor.withOpacity(0.4)
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: accentColor.withOpacity(0.12),
                                ),
                                child: Icon(
                                  Icons.play_circle_outline_rounded,
                                  color: accentColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c['title']!,
                                        style: TextStyle(
                                            color: textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14)),
                                    const SizedBox(height: 5),
                                    Text(c['sub']!,
                                        style: TextStyle(
                                            color: textSub, fontSize: 12)),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        AppTag(
                                            label: c['duration']!,
                                            icon: Icons.access_time_rounded),
                                        const SizedBox(width: 8),
                                        AppTag(
                                            label: c['level']!,
                                            icon: Icons.bar_chart_rounded),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: gold.withOpacity(0.1),
                                ),
                                child: const Icon(Icons.arrow_back_ios_rounded,
                                    color: gold, size: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: courses.length,
            ),
          ),
        ),
      ],
    );
  }
}
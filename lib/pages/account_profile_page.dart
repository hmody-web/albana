import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/app_auth_service.dart';
import '../services/apple_profile_service.dart';

class AccountProfilePage extends StatefulWidget {
  final bool isDark;
  final User user;
  const AccountProfilePage({super.key, required this.isDark, required this.user});
  @override State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  static const gold = Color(0xFFD4A017);
  late Future<Map<String,dynamic>> _future;
  StreamSubscription<User?>? _profileSubscription;
  @override void initState(){super.initState();_future=_load();_profileSubscription=FirebaseAuth.instance.userChanges().listen((_){if(mounted)setState((){});});}
  @override void dispose(){_profileSubscription?.cancel();super.dispose();}

  Future<Map<String,dynamic>> _load() async {
    final identity=AppAuthService.userIdentity(widget.user).trim().toLowerCase();
    int comments=0, likes=0; bool registered=false;
    try {
      final regEmail=(widget.user.email ?? identity).trim().toLowerCase();
      final r=await http.get(Uri.parse('https://majidalbana.com/admin/registrations/registrations_api.php?action=status&account_email=${Uri.encodeComponent(regEmail)}')).timeout(const Duration(seconds:10));
      if(r.statusCode==200){final d=jsonDecode(utf8.decode(r.bodyBytes)); if(d is Map) registered=d['registered']==true || '${d['registered']}'=='1' || d['registration'] is Map;}
    } catch(_){}
    try {
      final posts=await http.get(Uri.parse('https://majidalbana.com/admin/posts/load_posts.php')).timeout(const Duration(seconds:10));
      final d=jsonDecode(utf8.decode(posts.bodyBytes)); dynamic rows=d; if(d is Map) rows=d['posts']??d['data'];
      if(rows is List){for(final p in rows.take(40)){if(p is! Map) continue; final id=int.tryParse('${p['id']??0}')??0; if(id<=0) continue;
        try {final rs=await Future.wait([
          http.get(Uri.parse('https://majidalbana.com/admin/comments/load_comments.php?post_id=$id')).timeout(const Duration(seconds:6)),
          http.get(Uri.parse('https://majidalbana.com/admin/posts/get_likes.php?post_id=$id&user_email=${Uri.encodeComponent(identity)}')).timeout(const Duration(seconds:6)),
        ]); final cd=jsonDecode(utf8.decode(rs[0].bodyBytes)); dynamic cr=cd; if(cd is Map) cr=cd['comments']??cd['data']; if(cr is List){for(final c in cr){if(c is Map && '${c['user_email']??''}'.trim().toLowerCase()==identity) comments++;}}
        final ld=jsonDecode(utf8.decode(rs[1].bodyBytes)); if(ld is Map && ld['liked']==true) likes++;} catch(_){}
      }}
    } catch(_){}
    return {'comments':comments,'likes':likes,'registered':registered};
  }

  String _date(DateTime? d)=> d==null?'غير متوفر':'${d.year}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';
  @override Widget build(BuildContext context){
    final u=FirebaseAuth.instance.currentUser??widget.user; final apple=AppAuthService.isAppleUser(u); final bg=widget.isDark?const Color(0xFF090909):const Color(0xFFF7F4EE); final fg=widget.isDark?Colors.white:const Color(0xFF1A1000);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(backgroundColor:bg, appBar:AppBar(backgroundColor:bg,elevation:0,title:Text('الملف الشخصي',style:TextStyle(color:fg,fontWeight:FontWeight.w900)),iconTheme:IconThemeData(color:fg)), body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){final d=s.data??const{}; return ListView(padding:const EdgeInsets.all(18),children:[
      Center(child:CircleAvatar(radius:46,backgroundColor:gold.withOpacity(.15),backgroundImage:(u.photoURL??'').isNotEmpty?NetworkImage(u.photoURL!):null,child:(u.photoURL??'').isEmpty?Text(String.fromCharCode(AppAuthService.displayNameFor(u).runes.first),style:const TextStyle(fontSize:34,color:gold,fontWeight:FontWeight.w900)):null)),
      const SizedBox(height:12),Center(child:Text(AppAuthService.displayNameFor(u),style:TextStyle(color:fg,fontSize:22,fontWeight:FontWeight.w900))),const SizedBox(height:18),
      _card(fg,[
        _row(Icons.email_rounded,'البريد الإلكتروني',u.email??AppAuthService.userIdentity(u),fg),
        _row(apple?Icons.apple:Icons.g_mobiledata_rounded,'طريقة تسجيل الدخول',apple?'Apple':'Google',fg),
        _row(Icons.calendar_month_rounded,'تاريخ الانضمام',_date(u.metadata.creationTime),fg),
        _row(Icons.verified_user_rounded,'حالة الدورة',s.connectionState==ConnectionState.waiting?'جاري التحقق...':(d['registered']==true?'مسجل في الدورة التدريبية':'غير مسجل في الدورة التدريبية'),fg),
      ]), const SizedBox(height:14),
      _card(fg,[
        _row(Icons.chat_bubble_rounded,'التعليقات والمساهمات','${d['comments']??0}',fg),
        _row(Icons.favorite_rounded,'الإعجابات','${d['likes']??0}',fg),
      ]), const SizedBox(height:14),
      SizedBox(width:double.infinity,height:52,child:FilledButton.icon(
        onPressed:() async { final ok=await AppleProfileService.ensureProfile(context,FirebaseAuth.instance.currentUser??u,forceEdit:true); if(ok&&mounted){setState((){_future=_load();});}},
        icon:const Icon(Icons.edit_rounded),label:const Text('تعديل الملف الشخصي'),
        style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)))
      ))
    ]);}))); }
  Widget _card(Color fg,List<Widget> children)=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:widget.isDark?const Color(0xFF151515):Colors.white,borderRadius:BorderRadius.circular(22),border:Border.all(color:gold.withOpacity(.18))),child:Column(children:children));
  Widget _row(IconData icon,String title,String value,Color fg)=>Padding(padding:const EdgeInsets.symmetric(vertical:9),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:gold,size:21),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:TextStyle(color:fg.withOpacity(.58),fontSize:12,fontWeight:FontWeight.w700)),const SizedBox(height:3),Text(value,style:TextStyle(color:fg,fontSize:14,fontWeight:FontWeight.w800))]))]));
}

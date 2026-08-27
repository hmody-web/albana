import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_auth_service.dart';
import 'app_notice.dart';

class UserSafetyService {
  static const _endpoint='https://majidalbana.com/admin/reports/client.php';
  static final ValueNotifier<Set<String>> blockedEmails=ValueNotifier(<String>{});
  static bool _loading=false;
  static String _owner='';

  static String currentIdentity(){final u=FirebaseAuth.instance.currentUser;return u==null?'':AppAuthService.userIdentity(u).trim().toLowerCase();}
  static bool isMe(String email){final e=email.trim().toLowerCase();return e.isNotEmpty&&e==currentIdentity();}
  static bool isBlocked(String email)=>blockedEmails.value.contains(email.trim().toLowerCase());

  static Future<Map<String,dynamic>> _decode(http.Response r) async {
    final d=jsonDecode(utf8.decode(r.bodyBytes));
    if(r.statusCode>=400||d is! Map||d['success']!=true)throw Exception(d is Map?'${d['message']??'تعذر إكمال العملية'}':'تعذر إكمال العملية');
    return Map<String,dynamic>.from(d);
  }

  static Future<void> ensureLoaded({bool force=false}) async {
    final me=currentIdentity();if(me.isEmpty||_loading)return;
    if(!force&&_owner==me)return;
    _loading=true;
    try{final r=await http.get(Uri.parse(_endpoint).replace(queryParameters:{'action':'list_blocks','reporter_email':me})).timeout(const Duration(seconds:8));final d=await _decode(r);_owner=me;final rows=d['blocked'];final set=<String>{};if(rows is List){for(final x in rows){final e=(x is Map?'${x['email']??''}':'${x??''}').trim().toLowerCase();if(e.isNotEmpty)set.add(e);}}blockedEmails.value=set;}catch(_){ }finally{_loading=false;}
  }

  static Future<Map<String,dynamic>> _send(Map<String,String> fields) async {
    final u=FirebaseAuth.instance.currentUser;if(u!=null){fields.putIfAbsent('reporter_name',()=>u.displayName??'');fields.putIfAbsent('reporter_avatar',()=>u.photoURL??'');}
    return _decode(await http.post(Uri.parse(_endpoint),body:fields).timeout(const Duration(seconds:12)));
  }

  static Future<List<Map<String,dynamic>>> blockedUsers() async {
    final me=currentIdentity();if(me.isEmpty)return [];
    final r=await http.get(Uri.parse(_endpoint).replace(queryParameters:{'action':'list_blocks','reporter_email':me})).timeout(const Duration(seconds:10));
    final d=await _decode(r);final rows=d['blocked'];if(rows is! List)return [];
    return rows.map((e)=>e is Map?Map<String,dynamic>.from(e):<String,dynamic>{'email':'$e'}).toList();
  }

  static Future<List<Map<String,dynamic>>> myActivity() async {
    final me=currentIdentity();if(me.isEmpty)return [];
    final r=await http.get(Uri.parse(_endpoint).replace(queryParameters:{'action':'my_activity','reporter_email':me})).timeout(const Duration(seconds:10));
    final d=await _decode(r);final rows=d['items'];if(rows is! List)return [];
    return rows.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }

  static Future<void> unblock(String email) async {
    final me=currentIdentity();if(me.isEmpty)return;
    await _send({'action':'unblock','reporter_email':me,'target_email':email.trim().toLowerCase()});
    final next={...blockedEmails.value}..remove(email.trim().toLowerCase());blockedEmails.value=next;
  }

  static Future<void> block({required String name,required String email,required String avatar,String sourceType='profile',int sourceId=0,int commentId=0,String commentText=''}) async {
    final me=currentIdentity();if(me.isEmpty||email.trim().isEmpty)return;
    await _send({'action':'block','reporter_email':me,'target_email':email.trim().toLowerCase(),'target_name':name,'target_avatar':avatar,'source_type':sourceType,'source_id':'$sourceId','comment_id':'$commentId','comment_text':commentText});
    blockedEmails.value={...blockedEmails.value,email.trim().toLowerCase()};
  }

  static Future<void> report({required String reason,required String name,required String email,required String avatar,String sourceType='profile',int sourceId=0,int commentId=0,String commentText='',bool alsoBlock=false}) async {
    final me=currentIdentity();if(me.isEmpty)return;
    await _send({'action':alsoBlock?'report_block':'report','reporter_email':me,'target_email':email.trim().toLowerCase(),'target_name':name,'target_avatar':avatar,'reason':reason.trim(),'source_type':sourceType,'source_id':'$sourceId','comment_id':'$commentId','comment_text':commentText});
    if(alsoBlock)blockedEmails.value={...blockedEmails.value,email.trim().toLowerCase()};
  }

  static Color _sheetBg(bool isDark)=>isDark?const Color(0xFF151515):const Color(0xFFFFFCF7);
  static Color _text(bool isDark)=>isDark?Colors.white:const Color(0xFF211A0D);
  static Widget _handle()=>Container(width:42,height:4,decoration:BoxDecoration(color:Colors.grey.withOpacity(.32),borderRadius:BorderRadius.circular(20)));

  static Future<void> showActions(BuildContext context,{required bool isDark,required String name,required String email,required String avatar,String sourceType='profile',int sourceId=0,int commentId=0,String commentText=''}) async {
    if(isMe(email)||email.trim().isEmpty)return;await ensureLoaded();if(!context.mounted)return;
    await showModalBottomSheet(context:context,backgroundColor:Colors.transparent,isScrollControlled:true,builder:(ctx)=>Directionality(textDirection:TextDirection.rtl,child:Container(padding:EdgeInsets.fromLTRB(16,10,16,18 + MediaQuery.of(ctx).padding.bottom),decoration:BoxDecoration(color:_sheetBg(isDark),borderRadius:const BorderRadius.vertical(top:Radius.circular(28))),child:Column(mainAxisSize:MainAxisSize.min,children:[_handle(),const SizedBox(height:12),_actionTile(isDark,Icons.flag_outlined,'إبلاغ',const Color(0xFFD4A017),(){Navigator.pop(ctx);Future.delayed(const Duration(milliseconds:120),()=>showReport(context,isDark:isDark,name:name,email:email,avatar:avatar,sourceType:sourceType,sourceId:sourceId,commentId:commentId,commentText:commentText));}),const SizedBox(height:8),_actionTile(isDark,Icons.block_rounded,'حظر',const Color(0xFFE14D4D),(){Navigator.pop(ctx);Future.delayed(const Duration(milliseconds:120),()=>showBlockConfirm(context,isDark:isDark,name:name,email:email,avatar:avatar,sourceType:sourceType,sourceId:sourceId,commentId:commentId,commentText:commentText));})]))));
  }

  static Widget _actionTile(bool isDark,IconData icon,String label,Color accent,VoidCallback onTap)=>Material(color:Colors.transparent,child:InkWell(borderRadius:BorderRadius.circular(18),onTap:onTap,child:Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:13),decoration:BoxDecoration(color:accent.withOpacity(isDark ? .08 : .06),borderRadius:BorderRadius.circular(18),border:Border.all(color:accent.withOpacity(.18))),child:Row(children:[Container(width:38,height:38,decoration:BoxDecoration(color:accent.withOpacity(.12),borderRadius:BorderRadius.circular(12)),child:Icon(icon,color:accent,size:20)),const SizedBox(width:12),Text(label,style:TextStyle(color:_text(isDark),fontSize:14,fontWeight:FontWeight.w800)),const Spacer(),Icon(Icons.chevron_left_rounded,color:_text(isDark).withOpacity(.35))]))));

  static Future<void> showBlockConfirm(BuildContext context,{required bool isDark,required String name,required String email,required String avatar,String sourceType='profile',int sourceId=0,int commentId=0,String commentText=''}) async {
    final display=name.trim().isEmpty?'هذا المستخدم':name.trim();
    final ok=await showModalBottomSheet<bool>(context:context,backgroundColor:Colors.transparent,isScrollControlled:true,builder:(ctx)=>Directionality(textDirection:TextDirection.rtl,child:SafeArea(top:false,child:Container(padding:const EdgeInsets.fromLTRB(18,10,18,20),decoration:BoxDecoration(color:_sheetBg(isDark),borderRadius:const BorderRadius.vertical(top:Radius.circular(28))),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[Align(child:_handle()),const SizedBox(height:18),Row(children:[Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFFE14D4D).withOpacity(.12),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.block_rounded,color:Color(0xFFE14D4D))),const SizedBox(width:12),Expanded(child:Text('حظر $display',style:TextStyle(color:_text(isDark),fontSize:17,fontWeight:FontWeight.w900)))]),const SizedBox(height:12),Text('هل تريد حقاً حظر $display؟ ستختفي جميع تعليقاته لديك فقط ويمكنك إلغاء الحظر لاحقاً من الإعدادات.',style:TextStyle(color:_text(isDark).withOpacity(.72),fontSize:13,height:1.6,fontWeight:FontWeight.w600)),const SizedBox(height:18),Row(children:[Expanded(child:_sheetButton(isDark,'لا',null,()=>Navigator.pop(ctx,false))),const SizedBox(width:10),Expanded(child:_sheetButton(isDark,'نعم',const Color(0xFFE14D4D),()=>Navigator.pop(ctx,true)))])])))));
    if(ok!=true)return;
    try{await block(name:name,email:email,avatar:avatar,sourceType:sourceType,sourceId:sourceId,commentId:commentId,commentText:commentText);if(context.mounted)AppNotice.show(context,'تم حظر المستخدم وإخفاء تعليقاته لديك',success:true);}catch(_){if(context.mounted)AppNotice.show(context,'تعذر حظر المستخدم',success:false);}
  }

  static Widget _sheetButton(bool isDark,String label,Color? accent,VoidCallback tap)=>SizedBox(height:46,child:Material(color:accent??(isDark?const Color(0xFF202020):const Color(0xFFF2EEE5)),borderRadius:BorderRadius.circular(15),child:InkWell(borderRadius:BorderRadius.circular(15),onTap:tap,child:Center(child:Text(label,style:TextStyle(color:accent==null?_text(isDark):Colors.white,fontWeight:FontWeight.w900,fontSize:13))))));

  static Future<void> showReport(BuildContext context,{required bool isDark,required String name,required String email,required String avatar,String sourceType='profile',int sourceId=0,int commentId=0,String commentText=''}) async {
    String reason='';final display=name.trim().isEmpty?'المستخدم':name.trim();
    final result=await showModalBottomSheet<String>(context:context,backgroundColor:Colors.transparent,isScrollControlled:true,builder:(ctx){final kb=MediaQuery.of(ctx).viewInsets.bottom;return Directionality(textDirection:TextDirection.rtl,child:Padding(padding:EdgeInsets.only(bottom:kb),child:Container(padding:const EdgeInsets.fromLTRB(18,10,18,20),decoration:BoxDecoration(color:_sheetBg(isDark),borderRadius:const BorderRadius.vertical(top:Radius.circular(28))),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[Align(child:_handle()),const SizedBox(height:16),Text('الإبلاغ عن $display',style:TextStyle(color:_text(isDark),fontSize:16,fontWeight:FontWeight.w900)),const SizedBox(height:4),Text('سبب الإبلاغ',style:TextStyle(color:_text(isDark).withOpacity(.58),fontSize:11.5,fontWeight:FontWeight.w700)),const SizedBox(height:9),TextField(minLines:3,maxLines:5,maxLength:500,onChanged:(v)=>reason=v,style:TextStyle(color:_text(isDark),fontSize:13.5,fontWeight:FontWeight.w600),cursorColor:const Color(0xFFD4A017),decoration:InputDecoration(counterText:'',hintText:'اكتب سبب الإبلاغ باختصار...',hintStyle:TextStyle(color:_text(isDark).withOpacity(.35),fontSize:12.5),filled:true,fillColor:isDark?const Color(0xFF0E0E0E):const Color(0xFFF7F2E9),contentPadding:const EdgeInsets.all(14),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide(color:const Color(0xFFD4A017).withOpacity(.18))),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:Color(0xFFD4A017),width:1.2)))),const SizedBox(height:14),Row(children:[Expanded(child:_sheetButton(isDark,'إلغاء',null,()=>Navigator.pop(ctx,'cancel'))),const SizedBox(width:8),Expanded(child:_sheetButton(isDark,'إرسال',const Color(0xFFD4A017),()=>Navigator.pop(ctx,'send'))),const SizedBox(width:8),Expanded(child:_sheetButton(isDark,'إرسال وحظر',const Color(0xFFE14D4D),()=>Navigator.pop(ctx,'send_block')))])]))));});
    if(result!='send'&&result!='send_block')return;final clean=reason.trim();if(clean.isEmpty){if(context.mounted)AppNotice.show(context,'اكتب سبب الإبلاغ أولاً');return;}
    try{await report(reason:clean,name:name,email:email,avatar:avatar,sourceType:sourceType,sourceId:sourceId,commentId:commentId,commentText:commentText,alsoBlock:result=='send_block');if(context.mounted)AppNotice.show(context,result=='send_block'?'تم إرسال البلاغ وحظر المستخدم':'تم إرسال البلاغ',success:true);}catch(_){if(context.mounted)AppNotice.show(context,'تعذر إرسال البلاغ',success:false);}
  }
}

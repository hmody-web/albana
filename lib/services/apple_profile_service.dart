import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';


class AppleProfileService {
  AppleProfileService._();

  static const _uploadUrl = 'https://majidalbana.com/admin/account/apple_profile.php';
  static const _gold = Color(0xFFD4A017);

  static bool isComplete(User user) {
    final name = (user.displayName ?? '').trim();
    final photo = (user.photoURL ?? '').trim();
    return name.isNotEmpty && name != 'مستخدم' && photo.isNotEmpty;
  }

  static Future<bool> ensureProfile(BuildContext context, User user, {bool forceEdit = false, bool requireConfirmation = false}) async {
    await user.reload();
    final current = FirebaseAuth.instance.currentUser ?? user;
    if (!forceEdit && isComplete(current)) return true;
    if (!context.mounted) return false;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AppleProfilePage(user: current, forceEdit: forceEdit, requireConfirmation: requireConfirmation),
      ),
    );
    return saved == true;
  }
}

class _AppleProfilePage extends StatefulWidget {
  final User user;
  final bool forceEdit;
  final bool requireConfirmation;
  const _AppleProfilePage({required this.user, required this.forceEdit, required this.requireConfirmation});

  @override
  State<_AppleProfilePage> createState() => _AppleProfilePageState();
}

class _AppleProfilePageState extends State<_AppleProfilePage> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  File? _image;
  bool _saving = false;
  String? _error;

  bool get _firstSetup => widget.requireConfirmation || !AppleProfileService.isComplete(widget.user);
  bool get _hasRemotePhoto => (widget.user.photoURL ?? '').trim().isNotEmpty;
  bool get _canSave => _nameController.text.trim().length >= 2 && (_image != null || _hasRemotePhoto);

  @override
  void initState() {
    super.initState();
    final oldName = (widget.user.displayName ?? '').trim();
    if (oldName.isNotEmpty && oldName != 'مستخدم') _nameController.text = oldName;
    _nameController.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _nameController.removeListener(_refresh);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        IOSUiSettings(
          title: 'ضبط الصورة',
          doneButtonTitle: 'تم',
          cancelButtonTitle: 'إلغاء',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.circle,
        ),
        AndroidUiSettings(
          toolbarTitle: 'ضبط الصورة',
          lockAspectRatio: true,
          hideBottomControls: false,
          cropStyle: CropStyle.circle,
        ),
      ],
    );
    if (cropped == null) return;
    setState(() { _image = File(cropped.path); _error = null; });
  }

  Future<bool> _confirm() async {
    final name = _nameController.text.trim();
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Text('تأكيد الملف الشخصي', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: AppleProfileService._gold.withOpacity(.12),
                backgroundImage: _image != null
                    ? FileImage(_image!)
                    : (_hasRemotePhoto ? NetworkImage(widget.user.photoURL!) as ImageProvider : null),
                child: (_image == null && !_hasRemotePhoto)
                    ? const Icon(Icons.person_rounded, size: 44, color: AppleProfileService._gold)
                    : null,
              ),
              const SizedBox(height: 14),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('هل هذا اسمك وهذه صورتك؟', textAlign: TextAlign.center),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تعديل')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، تأكيد')),
          ],
        ),
      ),
    ) ?? false;
  }

  Future<String> _uploadPhoto(File file) async {
    final request = http.MultipartRequest('POST', Uri.parse(AppleProfileService._uploadUrl));
    request.fields['uid'] = widget.user.uid;
    request.files.add(await http.MultipartFile.fromPath('avatar', file.path));
    final streamed = await request.send().timeout(const Duration(seconds: 35));
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> data = {};
    try { data = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
    final url = '${data['url'] ?? ''}'.trim();
    if (response.statusCode != 200 || data['success'] != true || url.isEmpty) {
      throw Exception('upload_failed');
    }
    return url;
  }

  Future<void> _syncHistoricalComments(User user, String name, String photoUrl) async {
    final response = await http.post(
      Uri.parse(AppleProfileService._uploadUrl),
      body: {
        'uid': user.uid,
        'user_identity': ((user.email ?? '').trim().isNotEmpty ? user.email!.trim() : 'apple.${user.uid}@users.majidalbana.local'),
        'display_name': name,
        'avatar_url': photoUrl,
      },
    ).timeout(const Duration(seconds: 20));

    Map<String, dynamic> data = {};
    try { data = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception('profile_sync_failed');
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_canSave || _saving) return;
    if (!await _confirm()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser ?? widget.user;
      String photoUrl = (user.photoURL ?? '').trim();
      if (_image != null) photoUrl = await _uploadPhoto(_image!);
      final newName = _nameController.text.trim();
      await user.updateDisplayName(newName);
      if (photoUrl.isNotEmpty) await user.updatePhotoURL(photoUrl);
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser ?? user;
      await _syncHistoricalComments(refreshedUser, newName, photoUrl);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'تعذر حفظ الملف الشخصي. حاول مرة أخرى.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF090909) : const Color(0xFFF8F5EE);
    final card = dark ? const Color(0xFF171717) : Colors.white;
    return PopScope(
      canPop: !_firstSetup && !_saving,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            automaticallyImplyLeading: !_firstSetup,
            title: Text(widget.forceEdit ? 'تعديل الملف الشخصي' : 'تأكيد الملف الشخصي'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppleProfileService._gold.withOpacity(.18)),
                  ),
                  child: Column(
                    children: [
                      const Text('اختر الاسم والصورة التي ستظهر للآخرين', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 22),
                      GestureDetector(
                        onTap: _saving ? null : _choosePhoto,
                        child: Stack(
                          alignment: Alignment.bottomLeft,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [Color(0xFFFFDF7D), AppleProfileService._gold])),
                              child: CircleAvatar(
                                radius: 58,
                                backgroundColor: dark ? const Color(0xFF222222) : const Color(0xFFF3EFE5),
                                backgroundImage: _image != null
                                    ? FileImage(_image!)
                                    : (_hasRemotePhoto ? NetworkImage(widget.user.photoURL!) as ImageProvider : null),
                                child: (_image == null && !_hasRemotePhoto)
                                    ? const Icon(Icons.add_a_photo_rounded, size: 38, color: AppleProfileService._gold)
                                    : null,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: const BoxDecoration(color: AppleProfileService._gold, shape: BoxShape.circle),
                              child: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(onPressed: _saving ? null : _choosePhoto,
                        icon: const Icon(Icons.crop_rounded), label: const Text('اختيار وضبط الصورة')),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        enabled: !_saving,
                        maxLength: 40,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'اسم المستخدم',
                          hintText: 'اكتب الاسم الذي تريد ظهوره',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: _canSave && !_saving ? _save : null,
                          icon: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: Text(_saving ? 'جاري الحفظ...' : 'حفظ البيانات'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppleProfileService._gold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

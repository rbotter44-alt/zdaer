ملف المشروع صار يحتوي تعديلات PC:

1) تم دمج assets/tele.json و assets/subtitle_activation بالكامل.
2) تم تعديل lib/main.dart حتى يفتح المصادر على Windows عبر Navigator بدل Android Activity.
3) تم تعطيل NativeSecurityGuard على غير Android حتى لا يكسر تشغيل Windows.
4) تم إضافة lib/universal_media_player.dart كمشغل Flutter/Desktop بديل لمسار ExoPlayer على PC.
5) تم تعديل مصادر anime/arab/egy/light_on حتى تستخدم المشغل الجديد على Windows، وتبقي مسار Android القديم كما هو.
6) تم توسيع background_download_bridge.dart حتى يعمل على Windows بتنزيل مباشر و HLS غير مشفر داخل Dart بدل Android Service.

لإنشاء exe:
- افتح CMD داخل مجلد المشروع.
- شغل:
  build_windows_release.bat

أو يدويًا:
  flutter config --enable-windows-desktop
  flutter create --platforms=windows .
  flutter pub get
  flutter build windows --release

مجلد الإخراج عادة:
  build\windows\x64\runner\Release

مهم:
- لا ترسل ملف exe وحده. أرسل مجلد Release كاملًا لأنه يحتوي DLL و data.
- لو كان HLS مشفر AES-128، downloader المكتوب لـ Windows سيظهر failed لأن فك تشفير HLS يحتاج إضافة مرحلة مفاتيح. التشغيل نفسه عبر media_kit قد يعمل لأن المشغل يتعامل مع HLS مباشرة.

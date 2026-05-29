# نشر Light On PWA على GitHub Pages

هذه النسخة مبنية على `fix39_clean_back_no_exit` ومجهزة للنشر على GitHub Pages عبر GitHub Actions.

## مهم قبل الرفع

تم حذف ملفات توقيع أندرويد الحساسة من هذه النسخة:

- `android/app/lighton-release.jks`
- `android/key.properties`
- `android/local.properties`

لا ترفع هذه الملفات إلى GitHub العام.

## خطوات الرفع

1. افتح GitHub وأنشئ Repository جديد مثل:
   `lighton-pwa`

2. فك هذا ZIP داخل مجلد.

3. افتح PowerShell داخل المجلد وشغل:

```powershell
git init
git branch -M main
git add .
git commit -m "Deploy Light On PWA"
git remote add origin https://github.com/YOUR_USER/lighton-pwa.git
git push -u origin main
```

بدّل `YOUR_USER` باسم حسابك.

4. من GitHub افتح:

`Settings -> Pages`

وخلي Source على:

`GitHub Actions`

5. افتح تبويب:

`Actions`

وانتظر workflow باسم:

`Deploy Flutter Web to GitHub Pages`

إلى أن يصير أخضر.

6. رابط الموقع سيكون غالبًا:

```text
https://YOUR_USER.github.io/lighton-pwa/
```

إذا كان اسم المستودع:

```text
YOUR_USER.github.io
```

فالرابط سيكون:

```text
https://YOUR_USER.github.io/
```

## ماذا يفعل workflow؟

- يثبت Flutter stable.
- يشغل `flutter pub get`.
- يحسب `base-href` تلقائيًا حسب اسم المستودع.
- يبني نسخة web release.
- ينشر `build/web` على GitHub Pages.


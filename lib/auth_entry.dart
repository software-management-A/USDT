<!doctype html>
<html lang="ur" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sarmaya Plus v11 — Sign Up File Generator</title>
<style>
:root{font-family:system-ui,"Noto Naskh Arabic",sans-serif;color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f4f7f4;color:#142c23;padding:22px 14px}main{max-width:540px;margin:auto;background:white;border:1px solid #dae7dc;border-radius:18px;padding:24px 18px;box-shadow:0 7px 22px #1638290d}h1{font-size:23px;margin:0 0 12px;color:#123f2b}p{font-size:15px;line-height:1.85}label{display:block;margin:18px 0 8px;font-weight:600}button{font:inherit;cursor:pointer;border:0;border-radius:12px;background:#123f2b;color:white;width:100%;padding:14px;margin:9px 0;font-size:15px;font-weight:650}button:disabled{opacity:.45;cursor:not-allowed}.outline{background:#f1f6f2;color:#123f2b;border:1px solid #99bba8}input{display:block;max-width:100%;width:100%;border:1px solid #bccbbf;border-radius:8px;padding:9px}#status{padding:13px;min-height:50px;line-height:1.7;font-size:14px;border-radius:10px;background:#f0f5f0;margin:12px 0;overflow-wrap:anywhere}.good{color:#12623a}.bad{color:#a12626}small{line-height:1.65;color:#61766a;display:block}code{direction:ltr;unicode-bidi:embed}
</style>
</head>
<body>
<main>
<h1>Sarmaya Plus v11 — Sign Up Fix</h1>
<p>یہ فائل آپ کے اصل <code>lib/auth_entry.dart</code> کو مکمل رکھتے ہوئے Login اسکرین پر Sign Up بٹن شامل کرتی ہے۔ کسی Firebase یا Signing Secret کی ضرورت نہیں۔</p>
<p><strong>پہلا طریقہ:</strong> نیچے بٹن دبائیں، GitHub کی اصل فائل پڑھی جائے گی اور مکمل نئی Dart فائل تیار ہوگی۔</p>
<button id="github">GitHub سے مکمل نئی فائل تیار کریں</button>
<p><strong>دوسرا طریقہ:</strong> اگر GitHub سے فائل پڑھنے میں رکاوٹ آئے تو موبائل کے Download فولڈر سے اپنی اصل <code>auth_entry.dart</code> منتخب کریں۔</p>
<label for="input">اصل auth_entry.dart منتخب کریں</label>
<input type="file" id="input" accept=".dart,text/plain">
<div id="status" role="status" aria-live="polite">ابھی کوئی فائل منتخب نہیں ہوئی۔</div>
<button id="download" disabled>نئی auth_entry.dart ڈاؤن لوڈ کریں</button>
<small>ڈاؤن لوڈ ہونے والی فائل کا نام <code>auth_entry.dart</code> ہوگا۔ GitHub کے <code>lib</code> فولڈر میں پرانی فائل Replace/Commit کریں۔ پھر GitHub Actions سے نئی APK بنائیں۔ Backend پر رجسٹریشن کی اجازت اور Email Verification الگ سے ضروری ہیں۔</small>
</main>
<script>
(() => {
 'use strict';
 const input=document.getElementById('input');
 const status=document.getElementById('status');
 const download=document.getElementById('download');
 const github=document.getElementById('github');
 const githubSource='https://raw.githubusercontent.com/software-management-A/USDT/main/lib/auth_entry.dart';
 let ready=null;
 const old=`                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Personal owner-only edition • New public registrations are disabled.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ),`;
 const updated=`                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy ? null : () => setState(() {
                      signup = !signup;
                      message = null;
                      password.clear();
                      confirm.clear();
                    }),
                    child: Text(signup
                        ? 'Already registered? Login / لاگ اِن'
                        : 'New user? Sign Up / نیا اکاؤنٹ بنائیں'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'New accounts require email verification and server-side registration. Financial access is not approved automatically.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),`;
 function setStatus(msg,good){status.textContent=msg;status.className=good===true?'good':good===false?'bad':'';}
 function prepare(raw){
   const text=raw.replace(/\r\n/g,'\n');
   if(!text.includes('class _AccountPageState') || !text.includes('FirebaseAuth.instance.createUserWithEmailAndPassword('))throw new Error('یہ اصل Sarmaya Plus auth_entry.dart نہیں لگ رہی۔');
   if(text.includes('New user? Sign Up / نیا اکاؤنٹ بنائیں'))throw new Error('اس فائل میں Sign Up کا بٹن پہلے سے موجود ہے۔');
   if(text.split(old).length!==2)throw new Error('فائل کا ورژن بدل چکا ہے؛ محفوظ تبدیلی ممکن نہیں۔ پرانی فائل کی جگہ نئی نہ لگائیں۔');
   const out=text.replace(old,updated);
   if(!out.includes('Already registered? Login') || out.includes('New public registrations are disabled.'))throw new Error('فائل کی جانچ ناکام ہوگئی۔');
   ready=out;
   download.disabled=false;
   setStatus('کامیاب! مکمل Dart فائل تیار ہوگئی ہے۔ نیچے Download دبائیں۔',true);
 }
 github.addEventListener('click',async()=>{
   download.disabled=true;ready=null;github.disabled=true;
   setStatus('GitHub کی اصل auth_entry.dart کھولی جا رہی ہے…');
   try {const r=await fetch(githubSource,{cache:'no-store'});if(!r.ok)throw new Error('GitHub HTTP '+r.status);prepare(await r.text());}
   catch(e){setStatus('GitHub سے خودکار فائل حاصل نہیں ہوئی۔ اوپر File Choose کرکے اصل auth_entry.dart منتخب کریں۔ ('+e.message+')',false);}
   finally{github.disabled=false;}
 });
 input.addEventListener('change',async()=>{
   download.disabled=true;ready=null;
   const f=input.files&&input.files[0];if(!f)return;
   try{if(!f.name.endsWith('.dart'))throw new Error('صرف .dart فائل منتخب کریں۔');prepare(await f.text());}
   catch(e){setStatus('فائل اپڈیٹ نہیں ہوئی: '+e.message,false);}
 });
 download.addEventListener('click',()=>{
   if(!ready)return;
   const url=URL.createObjectURL(new Blob([ready],{type:'text/plain;charset=utf-8'}));
   const a=document.createElement('a');a.href=url;a.download='auth_entry.dart';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);
   setStatus('فائل Download شروع ہوگئی ہے۔ اسے GitHub کے lib فولڈر میں Replace اور Commit کریں۔',true);
 });
})();
</script>
</body>
</html>

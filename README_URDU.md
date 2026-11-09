# Sarmaya Plus | سرمایہ پلس (Version 0.1 Demo)

یہ Flutter سے لکھی گئی **حقیقی Android App کا قابلِ Build Source Code** ہے، Website Shortcut نہیں۔
یہ ورژن **Offline Demo** ہے، اس میں Sample Balance اور Admin Demo شامل ہیں۔

**اہم فرق:** یہ مکمل Live Investment Service نہیں ہے۔ تمام Sample Amounts مقامی فون میں
رہتے ہیں، مختلف Users کے فونز پر خود سے Sync نہیں ہوتے۔ Password Login، KYC،
اصل Easypaisa Integration، Cloud Database اور محفوظ Server-side Approval ابھی شامل نہیں۔
اس Demo کو حقیقی رقم کا مستقل مالی ریکارڈ یا Live Service سمجھ کر استعمال نہ کریں۔

## ابھی کام کرنے والی Demo Screens

- Urdu / English language switcher، Sarmaya Plus brand colors اور Logo
- Investor Dashboard: Total Wallet (تبدیل ہونے والی رقم)، Total Deposited Lifetime، Total Referral Received Lifetime
- Wallet: External Deposit Request اور Demo Admin Approval؛ ایک Withdrawal Account کی Example
- Investments: Plan Buy/Upgrade; Referral Wallet + Cash Wallet دونوں استعمال ہو سکتے ہیں
- Referral Code Copy، QR Code، WhatsApp، SMS اور Android Share
- Referral Rewards ON/OFF، Manually Grant Approved Reward (صرف Demo Fund سے)
- Exit Request، Self-Cancel before trade، Admin Exit Settle اور Realized Proceeds
- Admin Deposits / Withdrawals / Plan Settings
- Trading Manager Buy/Sell Records: Weighted Average Cost اور Realized P&L
- Profit split 50% Users, 30% Owner, 20% Reserve+Referral؛ 3-Step Demo Approval
- Staff Accounts (max 5), Staff Salaries, Owner-Funded Office Expenses, Audit History
- Support Tickets اور Demo Notifications
- Local Saved Demo State on the phone

## APK بنانے کا سب سے آسان Free طریقہ (GitHub Actions)

1. GitHub پر نیا **Private** Repository بنائیں، مثلاً `sarmaya-plus`۔
2. اس ZIP کے اندر موجود **سارا Content** repository کی Root میں Upload کریں،
   `.github/workflows/build-apk.yml` سمیت (Hidden `.github` Folder ضروری ہے)۔
3. GitHub Repository میں `Actions` کھولیں۔
4. **Build Sarmaya Plus Demo APK** workflow منتخب کرکے **Run workflow** دبائیں۔
5. Build مکمل ہونے پر اس Run کے **Artifacts** میں `sarmaya-plus-demo-debug-apk` کھول کر ZIP Download کریں۔
6. اس میں `app-debug.apk` ہوگی، اسے Android پر Install کر سکتے ہیں۔

GitHub Actions Free Quota اور Build Minutes لاگو ہوں گے؛ unlimited free builds کی ضمانت نہیں۔
APK ابھی یہاں Compile نہیں ہوئی، کیونکہ اس environment میں Flutter/Android SDK نصب نہیں۔

## مقامی Computer پر Build

```bash
flutter create --platforms=android --project-name=sarmaya_plus --org=pk.sarmayaplus .
flutter pub get
flutter analyze
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

## حقیقی Live App کے لیے مستقبل کے ضروری Technical Parts

- Cloudflare Workers + D1 Database، درست Multi-user session authentication
- Server-side role permissions + 2FA + admin authorization
- Separate per-user balanced ledger and immutable transaction history
- Verified deposit receipts, approved withdrawals with actual payout proof
- Per-user daily investment allocation with no more than daily verified realized profit
- Fixed-price/weighted inventory account reconciliation and loss carry
- Secure document storage, encryption, audit events and reliable backup/restore
- Proper notification delivery and invitation deep links with owned domain
- App signing/release management and extensive testing

اس Demo میں `Admin Demo` کا Login Button **پاس ورڈ کے بغیر** ہے؛ یہ صرف Preview ہے۔
اسے عوامی مالی Service کے لیے Deployment نہ کریں۔

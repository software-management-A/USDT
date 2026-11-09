# Sarmaya Plus Android APK — Quick Build

This ZIP contains the Flutter source for a **working offline demo**, not a pre-built APK.
No live Cloudflare database, payment processor, identity verification or secure multi-user login is connected yet.

## Free GitHub Actions build

1. Unzip the archive.
2. Create a private GitHub repository.
3. Upload **all extracted files and folders** to the repository root, including `.github`.
4. In GitHub, open **Actions → Build Sarmaya Plus Demo APK → Run workflow**.
5. Open the completed run, download **sarmaya-plus-demo-debug-apk** artifact, unzip it and install `app-debug.apk` on Android.

A debug APK is for testing, not public financial operations.
GitHub Actions usage is subject to GitHub's free limits.

## Local developer build

Install Flutter and Android SDK, open this folder, then run:

```bash
flutter create --platforms=android --project-name=sarmaya_plus --org=pk.sarmayaplus .
flutter pub get
flutter analyze
flutter build apk --debug
```

## App screens

- Investor: Home, Plans, Wallet, Referrals, Exit, History, Profile, Support, Notifications.
- Admin: Overview, Deposits, Withdrawals, Referrals, Plans, P2P Trading,
  Profit Approvals, Expenses, Payroll, Staff Accounts, User & KYC summary, Reports.

## Financial behavior tested in the design (not bank-integrated)

- Total Wallet is a current balance; lifetime deposit and referral totals remain historical.
- Referral credits cannot be withdrawn directly but can pay for plans/upgrades.
- Realized exit proceeds may be withdrawable after a full exit, with losses possible.
- Withdrawal request amount reserves non-referral funds, and only one request is allowed per PKT day.
- Owner expenses and staff salaries do not debit users' funds.
- Sales use weighted average USDT inventory cost; accumulated losses are offset before positive profit allocation.
- This is a one-user local simulation; true multi-user profit apportionment is *not* implemented yet.

Because no Flutter/Android SDK was available in this environment, the APK build has **not** been executed or verified here.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// Sarmaya Plus — Account Dashboard v1
// Firebase Email/Password + verified Cloudflare /v1/me profile.
// No deposits, withdrawals, trading, investment or KYC document submission.
const Color deepGreen = Color(0xFF123F2B);
const Color paleGreen = Color(0xFFEAF3EC);
const Color paper = Color(0xFFF5F7F3);
const Color gold = Color(0xFFD4AF37);
const String apiBase = 'https://sarmaya-plus-api.bismurahved-819.workers.dev';
const String termsVersion = 'draft-2026-11';
const String riskVersion = 'draft-2026-11';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SarmayaPlusApp());
}

class SarmayaPlusApp extends StatelessWidget {
  const SarmayaPlusApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sarmaya Plus',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: paper,
          colorScheme: ColorScheme.fromSeed(seedColor: deepGreen),
          appBarTheme: const AppBarTheme(
            backgroundColor: paper,
            foregroundColor: deepGreen,
            centerTitle: false,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: deepGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
            ),
          ),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text('Authentication unavailable: ${snapshot.error}')),
            );
          }
          final user = snapshot.data;
          if (user == null) return const AccountPage();
          if (!user.emailVerified) return VerifyEmailPage(user: user);
          return AccountHomePage(key: ValueKey(user.uid), user: user);
        },
      );
}

String readableAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Enter a valid email.';
      case 'weak-password':
        return 'Use a stronger password.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Internet connection unavailable.';
    }
    return error.message ?? error.code;
  }
  return error.toString();
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  final referral = TextEditingController();
  final confirm = TextEditingController();
  bool signup = false;
  bool busy = false;
  bool showPassword = false;
  bool acceptTerms = false;
  bool acceptRisk = false;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    displayName.dispose();
    referral.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final e = email.text.trim();
    final p = password.text;
    if (e.isEmpty || !e.contains('@') || p.length < 8) {
      setState(() => message = 'Enter a valid email and password (8+ characters).');
      return;
    }
    if (signup) {
      if (displayName.text.trim().length < 2 || confirm.text != p) {
        setState(() => message = 'Enter your name and matching passwords.');
        return;
      }
      if (!acceptTerms || !acceptRisk) {
        setState(() => message = 'Accept both Terms and Risk Notice to create an account.');
        return;
      }
      if (referral.text.trim().length > 32) {
        setState(() => message = 'Referral code is too long.');
        return;
      }
    }
    setState(() { busy = true; message = null; });
    try {
      if (signup) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: e,
          password: p,
        );
        final user = credential.user!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('registration_${user.uid}', jsonEncode({
          'name': displayName.text.trim(),
          'referral_code': referral.text.trim().toUpperCase(),
          'terms_version': termsVersion,
          'risk_version': riskVersion,
        }));
        await user.updateDisplayName(displayName.text.trim());
        await user.sendEmailVerification();
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: p);
      }
    } catch (error) {
      if (mounted) setState(() => message = readableAuthError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    final e = email.text.trim();
    if (!e.contains('@')) {
      setState(() => message = 'Enter your email first.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      if (mounted) setState(() => message = 'If an account exists, check your email.');
    } catch (error) {
      if (mounted) setState(() => message = readableAuthError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سرمایہ پلس • Sarmaya Plus')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 70, color: deepGreen),
                  const SizedBox(height: 12),
                  Text(
                    signup ? 'Create account / نیا اکاؤنٹ' : 'Login / لاگ اِن',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: deepGreen,
                      fontSize: 23,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  if (signup) ...[
                    TextField(
                      controller: displayName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full name / مکمل نام'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: !showPassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => showPassword = !showPassword),
                        icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                  ),
                  if (signup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirm,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirm password'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: referral,
                      decoration: const InputDecoration(
                        labelText: 'Referral code (optional, signup only)',
                      ),
                    ),
                    CheckboxListTile(
                      value: acceptTerms,
                      onChanged: busy ? null : (v) => setState(() => acceptTerms = v ?? false),
                      title: const Text('I accept the Terms / میں شرائط قبول کرتا ہوں'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: acceptRisk,
                      onChanged: busy ? null : (v) => setState(() => acceptRisk = v ?? false),
                      title: const Text('I understand trading risks and possible losses / میں خطرات سمجھتا ہوں'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(message!, style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Please wait...' : (signup ? 'Create Account' : 'Login')),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() { signup = !signup; message = null; }),
                    child: Text(signup ? 'Already registered? Login' : 'New user? Create account'),
                  ),
                  if (!signup)
                    TextButton(
                      onPressed: busy ? null : resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                  const SizedBox(height: 14),
                  const Text(
                    'Email verification is required. Identity verification and financial authorization are separate approval steps.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.user});
  final User user;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool busy = false;
  String? message;

  Future<void> verify() async {
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (mounted && FirebaseAuth.instance.currentUser?.emailVerified != true) {
        setState(() => message = 'Open the verification email link first.');
      }
    } catch (e) {
      if (mounted) setState(() => message = readableAuthError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() => message = 'Email sent. Check Inbox and Spam.');
    } catch (e) {
      if (mounted) setState(() => message = readableAuthError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verify Email / ای میل تصدیق')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 72, color: deepGreen),
                  const SizedBox(height: 18),
                  Text('Email verification link sent to ${widget.user.email ?? ''}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: busy ? null : verify,
                    child: const Text('I verified my email — Check Again'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : resend,
                    child: const Text('Resend Verification Email'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                  if (message != null)
                    Text(message!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
        ),
      );
}

class AccountHomePage extends StatefulWidget {
  const AccountHomePage({super.key, required this.user});
  final User user;

  @override
  State<AccountHomePage> createState() => _AccountHomePageState();
}

class _AccountHomePageState extends State<AccountHomePage> {
  int tab = 0;
  bool loading = true;
  bool sendingEmail = false;
  bool hideEmail = false;
  final List<bool> readyChecklist = [false, false, false];
  String? error;
  Map<String, dynamic>? profile;
  DateTime? lastSynced;

  String get keyPrefix => 'dashboard_${widget.user.uid}_';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    refreshProfile();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      hideEmail = prefs.getBool('${keyPrefix}hide_email') ?? false;
      for (var i = 0; i < readyChecklist.length; i++) {
        readyChecklist[i] = prefs.getBool('${keyPrefix}check_$i') ?? false;
      }
    });
  }

  Future<void> _setChecklist(int index, bool value) async {
    setState(() => readyChecklist[index] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${keyPrefix}check_$index', value);
  }

  Future<void> _setEmailHidden(bool value) async {
    setState(() => hideEmail = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${keyPrefix}hide_email', value);
  }

  Future<Map<String, dynamic>> authenticatedRequest(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await widget.user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Firebase session unavailable. Please sign in again.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .openUrl(method, Uri.parse('$apiBase$path'))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 15));
      final bodyText = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map<String, dynamic>) throw Exception('Invalid server response.');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('${decoded['error'] ?? 'HTTP ${response.statusCode}'}');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refreshProfile() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final registrationKey = 'registration_${widget.user.uid}';
      final pending = prefs.getString(registrationKey);
      if (pending != null) {
        final raw = jsonDecode(pending);
        if (raw is Map<String, dynamic>) {
          await authenticatedRequest('POST', '/v1/register', raw);
          await prefs.remove(registrationKey);
        }
      }
      final result = await authenticatedRequest('GET', '/v1/me');
      if (!mounted) return;
      setState(() {
        profile = result['profile'] is Map<String, dynamic>
            ? result['profile'] as Map<String, dynamic>
            : null;
        if (profile == null) error = 'No cloud profile found for this account.';
        lastSynced = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get cloudName {
    final cloud = profile?['display_name']?.toString().trim();
    return cloud != null && cloud.isNotEmpty
        ? cloud
        : (widget.user.displayName?.trim().isNotEmpty == true
            ? widget.user.displayName!
            : 'Member');
  }

  String get cloudStatus => profile?['status']?.toString() ?? 'unknown';

  String get statusName {
    switch (cloudStatus) {
      case 'pending_kyc': return 'Pending KYC / شناختی تصدیق باقی';
      case 'active': return 'Account Active / اکاؤنٹ فعال';
      case 'suspended': return 'Suspended / عارضی طور پر بند';
      case 'closed': return 'Closed / بند';
      default: return 'Status unavailable';
    }
  }

  String get shownEmail {
    final value = profile?['email']?.toString() ?? widget.user.email ?? '';
    if (!hideEmail || value.isEmpty) return value;
    final split = value.split('@');
    if (split.length != 2) return '••••••';
    final local = split[0];
    final prefix = local.length < 3 ? local.substring(0, 1) : local.substring(0, 2);
    return '$prefix••••@${split[1]}';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetPassword() async {
    if (sendingEmail) return;
    final email = widget.user.email;
    if (email == null || email.isEmpty) {
      _snack('Email address unavailable.');
      return;
    }
    setState(() => sendingEmail = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Password reset email sent. Check Inbox / Spam.');
    } catch (e) {
      _snack(readableAuthError(e));
    } finally {
      if (mounted) setState(() => sendingEmail = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final doSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out / لاگ آؤٹ'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (doSignOut == true) await FirebaseAuth.instance.signOut();
  }

  Widget _sectionHeading(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.only(top: 15, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: deepGreen)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Colors.black54)),
            ],
          ],
        ),
      );

  Widget _statusBanner({bool compact = false}) => Card(
        color: paleGreen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(cloudStatus == 'active' ? Icons.verified_user : Icons.fact_check_outlined,
                  color: deepGreen, size: compact ? 25 : 35),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(statusName,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: deepGreen)),
                    const SizedBox(height: 3),
                    Text(
                      cloudStatus == 'pending_kyc'
                          ? 'Cloud account is created. Identity verification has not been completed.'
                          : 'This is the account status reported by Cloudflare.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorCard() => Card(
        color: const Color(0xFFFFF1F0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cloud sync issue',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 8),
              Text(error ?? ''),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: loading ? null : refreshProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _infoRow(String title, String value, {IconData? icon, VoidCallback? onCopy}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: deepGreen),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 3),
                  SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (onCopy != null)
              IconButton(onPressed: onCopy, icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copy'),
          ],
        ),
      );

  List<Widget> _homeWidgets() => [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: deepGreen,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سرمایہ پلس  •  Sarmaya Plus',
                  style: TextStyle(color: Color(0xFFDDE8DE), fontSize: 14)),
              const SizedBox(height: 18),
              Text('Welcome, $cloudName',
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
              const SizedBox(height: 8),
              const Row(children: [
                Icon(Icons.verified_outlined, color: gold, size: 20),
                SizedBox(width: 8),
                Text('Email verified', style: TextStyle(color: Colors.white)),
              ]),
            ],
          ),
        ),
        _sectionHeading('Account Overview / اکاؤنٹ خلاصہ'),
        if (profile != null) _statusBanner(),
        if (profile == null && !loading)
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Your Cloudflare profile is not available. Refresh to try again.'),
          )),
        Card(child: Column(children: [
          ListTile(
            leading: const Icon(Icons.person_outline, color: deepGreen),
            title: const Text('My Profile / میری پروفائل'),
            subtitle: const Text('Cloud account name, email and record'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => tab = 1),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: deepGreen),
            title: const Text('KYC Preparation / شناختی تصدیق'),
            subtitle: const Text('Prepare requirements; no documents uploaded'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => tab = 2),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: deepGreen),
            title: const Text('Account Settings / سیٹنگز'),
            subtitle: const Text('Privacy and password recovery'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => tab = 3),
          ),
        ])),
        _sectionHeading('Service availability'),
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline, color: deepGreen),
            SizedBox(width: 12),
            Expanded(child: Text(
              'Deposits, withdrawals, USDT P2P, trading, investments, financial balances and referral rewards are not enabled. No money is held or moved by this dashboard.',
            )),
          ]),
        )),
      ];

  List<Widget> _profileWidgets() => [
        _sectionHeading('My Profile / میری پروفائل',
            subtitle: 'Details securely retrieved from your Cloudflare account'),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            CircleAvatar(
              radius: 31,
              backgroundColor: paleGreen,
              child: Text(cloudName.isNotEmpty ? cloudName[0].toUpperCase() : 'S',
                  style: const TextStyle(fontSize: 27, color: deepGreen)),
            ),
            const SizedBox(height: 12),
            Text(cloudName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('Verified email account', style: TextStyle(color: Colors.black54)),
            const Divider(height: 28),
            _infoRow('Full name / نام', cloudName, icon: Icons.person_outline),
            _infoRow('Email / ای میل', shownEmail, icon: Icons.email_outlined),
            _infoRow('Email verification', 'Verified', icon: Icons.verified_outlined),
            _infoRow('Account status', statusName, icon: Icons.fact_check_outlined),
            _infoRow('Account created (UTC)',
                profile?['created_at']?.toString() ?? 'Not available',
                icon: Icons.event_outlined),
            _infoRow('Cloud account ID', widget.user.uid, icon: Icons.fingerprint,
                onCopy: () async {
                  await Clipboard.setData(ClipboardData(text: widget.user.uid));
                  _snack('Account ID copied. Keep it private.');
                }),
          ]),
        )),
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'For your protection, your Firebase email and cloud registration details cannot be edited on this screen. Account changes need a secure, authenticated server endpoint.',
            style: TextStyle(fontSize: 12),
          ),
        )),
      ];

  List<Widget> _kycWidgets() => [
        _sectionHeading('KYC Application / شناختی تصدیق',
            subtitle: 'View status and prepare for future identity verification'),
        if (profile != null) _statusBanner(compact: true),
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: deepGreen),
            SizedBox(width: 12),
            Expanded(child: Text(
              'KYC applications and identity document uploads are not open yet. No CNIC, passport, photos or other identity documents are collected in this version.',
            )),
          ]),
        )),
        _sectionHeading('Preparation checklist / تیاری'),
        Card(child: Column(children: [
          CheckboxListTile(
            title: const Text('I have my valid identity document ready'),
            subtitle: const Text('Do not enter or upload the document here'),
            value: readyChecklist[0],
            onChanged: (v) => _setChecklist(0, v ?? false),
          ),
          const Divider(height: 1),
          CheckboxListTile(
            title: const Text('My legal name and date of birth are accurate'),
            subtitle: const Text('Do not enter these details here'),
            value: readyChecklist[1],
            onChanged: (v) => _setChecklist(1, v ?? false),
          ),
          const Divider(height: 1),
          CheckboxListTile(
            title: const Text('I can provide proof of address if required'),
            subtitle: const Text('Do not upload a document here'),
            value: readyChecklist[2],
            onChanged: (v) => _setChecklist(2, v ?? false),
          ),
        ])),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: readyChecklist.where((ready) => ready).length / readyChecklist.length,
          minHeight: 8,
          borderRadius: BorderRadius.circular(10),
          color: deepGreen,
          backgroundColor: const Color(0xFFDDE7DE),
        ),
        const SizedBox(height: 8),
        Text('${readyChecklist.where((ready) => ready).length} of 3 preparation items ready',
            style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        const Text(
          'This checklist is saved on this device only. It is not a KYC submission, does not change the Cloudflare account status, and is not proof of approval.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ];

  List<Widget> _settingsWidgets() => [
        _sectionHeading('Account Settings / اکاؤنٹ سیٹنگز'),
        Card(child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined, color: deepGreen),
            title: const Text('Hide email in this app'),
            subtitle: const Text('Privacy on this device; does not change your email'),
            value: hideEmail,
            onChanged: _setEmailHidden,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.password_outlined, color: deepGreen),
            title: const Text('Reset password'),
            subtitle: const Text('Send recovery link to your verified email'),
            trailing: sendingEmail
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: sendingEmail ? null : _resetPassword,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined, color: deepGreen),
            title: const Text('Sync cloud profile'),
            subtitle: Text(lastSynced == null
                ? 'Not synced in this session'
                : 'Last checked: ${lastSynced!.hour.toString().padLeft(2, '0')}:${lastSynced!.minute.toString().padLeft(2, '0')} (device time)'),
            trailing: const Icon(Icons.refresh),
            onTap: loading ? null : refreshProfile,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sign out / لاگ آؤٹ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _confirmSignOut,
          ),
        ])),
        _sectionHeading('About & privacy'),
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Sarmaya Plus • Account Dashboard v1\n'
            'Login: Firebase Authentication\n'
            'Account profile: Cloudflare API + D1\n'
            'KYC checklist and email-hide setting: stored on this device only\n\n'
            'Financial features and KYC document submission are disabled pending security, verified procedures and applicable authorization.',
          ),
        )),
      ];

  @override
  Widget build(BuildContext context) {
    final title = ['Dashboard / ڈیش بورڈ', 'My Profile', 'KYC / شناخت', 'Settings'][tab];
    final pageWidgets = switch (tab) {
      0 => _homeWidgets(),
      1 => _profileWidgets(),
      2 => _kycWidgets(),
      _ => _settingsWidgets(),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh cloud profile',
            onPressed: loading ? null : refreshProfile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: RefreshIndicator(
              onRefresh: refreshProfile,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (loading) const LinearProgressIndicator(minHeight: 3),
                  if (error != null) _errorCard(),
                  ...pageWidgets,
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge), label: 'KYC'),
          NavigationDestination(icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

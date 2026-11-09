import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

const Color deepGreen = Color(0xFF123F2B);
const Color paper = Color(0xFFF5F7F3);
const String apiBase = 'https://sarmaya-plus-api.bismurahved-819.workers.dev';
const String termsVersion = 'draft-2026-11';
const String riskVersion = 'draft-2026-11';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: deepGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
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
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(body: Center(child: Text('Authentication unavailable: ${snapshot.error}')));
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
      case 'email-already-in-use': return 'This email is already registered.';
      case 'invalid-email': return 'Enter a valid email.';
      case 'weak-password': return 'Use a stronger password.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found': return 'Incorrect email or password.';
      case 'too-many-requests': return 'Too many attempts. Try later.';
      case 'network-request-failed': return 'Internet connection unavailable.';
    }
    return error.message ?? error.code;
  }
  return error.toString();
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override State<AccountPage> createState() => _AccountPageState();
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

  @override void dispose() {
    email.dispose(); password.dispose(); displayName.dispose();
    referral.dispose(); confirm.dispose(); super.dispose();
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
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: e, password: p);
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

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سرمایہ پلس • Sarmaya Plus')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.account_balance_wallet_outlined, size: 70, color: deepGreen),
        const SizedBox(height: 12),
        Text(signup ? 'Create account / نیا اکاؤنٹ' : 'Login / لاگ اِن',
          style: const TextStyle(fontWeight: FontWeight.bold, color: deepGreen, fontSize: 23),
          textAlign: TextAlign.center),
        const SizedBox(height: 22),
        if (signup) ...[
          TextField(controller: displayName, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name / مکمل نام', border: OutlineInputBorder())),
          const SizedBox(height: 12),
        ],
        TextField(controller: email, keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: !showPassword,
          decoration: InputDecoration(labelText: 'Password', border: const OutlineInputBorder(),
            suffixIcon: IconButton(onPressed: () => setState(() => showPassword = !showPassword),
              icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility)))),
        if (signup) ...[
          const SizedBox(height: 12),
          TextField(controller: confirm, obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: referral,
            decoration: const InputDecoration(labelText: 'Referral code (optional, signup only)', border: OutlineInputBorder())),
          CheckboxListTile(value: acceptTerms,
            onChanged: busy ? null : (v) => setState(() => acceptTerms = v ?? false),
            title: const Text('I accept the Terms / میں شرائط قبول کرتا ہوں'),
            controlAffinity: ListTileControlAffinity.leading),
          CheckboxListTile(value: acceptRisk,
            onChanged: busy ? null : (v) => setState(() => acceptRisk = v ?? false),
            title: const Text('I understand trading risks and possible losses / میں خطرات سمجھتا ہوں'),
            controlAffinity: ListTileControlAffinity.leading),
        ],
        if (message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(message!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : submit,
          child: Text(busy ? 'Please wait...' : (signup ? 'Create Account' : 'Login'))),
        TextButton(onPressed: busy ? null : () => setState(() { signup = !signup; message = null; }),
          child: Text(signup ? 'Already registered? Login' : 'New user? Create account')),
        if (!signup) TextButton(onPressed: busy ? null : resetPassword,
          child: const Text('Forgot password?')),
        const SizedBox(height: 14),
        const Text('Email verification is required. KYC, account authorization and trading access are separate approval steps.',
          style: TextStyle(color: Colors.black54, fontSize: 12)),
      ]),
    ))),
  );
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.user});
  final User user;
  @override State<VerifyEmailPage> createState() => _VerifyEmailPageState();
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

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify Email / ای میل تصدیق')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.mark_email_unread_outlined, size: 72, color: deepGreen),
        const SizedBox(height: 18),
        Text('Email verification link sent to ${widget.user.email ?? ''}', textAlign: TextAlign.center),
        const SizedBox(height: 22),
        FilledButton(onPressed: busy ? null : verify, child: const Text('I verified my email — Check Again')),
        OutlinedButton(onPressed: busy ? null : resend, child: const Text('Resend Verification Email')),
        TextButton(onPressed: busy ? null : () => FirebaseAuth.instance.signOut(), child: const Text('Sign out')),
        if (message != null) Text(message!, style: const TextStyle(color: Colors.red)),
      ]),
    ))),
  );
}

class AccountHomePage extends StatefulWidget {
  const AccountHomePage({super.key, required this.user});
  final User user;
  @override State<AccountHomePage> createState() => _AccountHomePageState();
}

class _AccountHomePageState extends State<AccountHomePage> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? profile;

  @override void initState() { super.initState(); refreshProfile(); }

  Future<Map<String, dynamic>> authenticatedRequest(String method, String path, [Map<String, dynamic>? body]) async {
    final token = await widget.user.getIdToken();
    if (token == null || token.isEmpty) throw Exception('Firebase token unavailable');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.openUrl(method, Uri.parse('$apiBase$path'))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 15));
      final parsed = jsonDecode(text);
      if (parsed is! Map<String, dynamic>) throw Exception('Bad server response');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('${parsed['error'] ?? 'HTTP ${response.statusCode}'}');
      }
      return parsed;
    } finally { client.close(force: true); }
  }

  Future<void> refreshProfile() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'registration_${widget.user.uid}';
      final pending = prefs.getString(key);
      if (pending != null) {
        final raw = jsonDecode(pending);
        if (raw is Map<String, dynamic>) {
          await authenticatedRequest('POST', '/v1/register', raw);
          await prefs.remove(key);
        }
      }
      final result = await authenticatedRequest('GET', '/v1/me');
      if (!mounted) return;
      setState(() => profile = result['profile'] is Map<String, dynamic>
          ? result['profile'] as Map<String, dynamic> : null);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sarmaya Plus / سرمایہ پلس'), actions: [
      IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: refreshProfile),
      IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout),
        onPressed: () => FirebaseAuth.instance.signOut()),
    ]),
    body: SafeArea(child: RefreshIndicator(onRefresh: refreshProfile,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        const Icon(Icons.verified_user, size: 64, color: deepGreen),
        const SizedBox(height: 12),
        Text('Email Verified • ${widget.user.email ?? ''}', textAlign: TextAlign.center),
        const SizedBox(height: 22),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cloudflare profile unavailable', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8), Text(error!, style: const TextStyle(fontSize: 12)),
            const Text('The account is authenticated, but user data sync is not ready until the secure API is deployed.'),
          ]))),
        if (profile != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your Cloud Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Text('Name: ${profile!['display_name'] ?? ''}'),
            Text('Email: ${profile!['email'] ?? ''}'),
            Text('Account status: ${profile!['status'] ?? 'pending_kyc'}'),
            Text('Account created: ${profile!['created_at'] ?? ''}'),
          ]))),
        const SizedBox(height: 16),
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
          'Deposits, withdrawals, referrals, investment execution, trading and admin screens are not enabled. '
          'They require verified identities, role-based permissions, audited financial ledgers and applicable regulatory authorization. '
          'Your personal data must not be used as a shared demo wallet.',
          style: TextStyle(fontSize: 12)))),
      ]),
    )),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'remittance_v10.dart';
import 'v11_features.dart';
import 'package:android_id/android_id.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Only the authenticated Cloudflare backend grants admin access.
typedef ApiRequest = Future<Map<String, dynamic>> Function(
    String method, String path, [Map<String, dynamic>? body]);

// Sarmaya Plus v7 Personal Edition: private manual ledger and existing admin/KYC
// Firebase Email/Password + verified Cloudflare /v1/me profile.
// No real money/crypto transfers, order execution or KYC document submission.
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
        builder: (context, navigator) => StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (user == null) return navigator ?? const SizedBox.shrink();
            return V11SessionGate(key: ValueKey('v11_${user.uid}'),
                user: user, child: navigator ?? const SizedBox.shrink());
          },
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
          return UnifiedAccessGate(key: ValueKey(user.uid), user: user);
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
        final deviceId = await const AndroidId().getId();
        if (deviceId == null || !RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(deviceId)) {
          throw StateError('Device registration ID unavailable. Account setup cannot finish.');
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('registration_${user.uid}', jsonEncode({
          'name': displayName.text.trim(),
          'device_id': deviceId,
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('New accounts require email verification and server-side approval. Financial access is not automatic.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => setState(() {
                      signup = !signup;
                      message = null;
                      password.clear();
                      confirm.clear();
                    }),
                    child: Text(
                      signup
                          ? 'Already registered? Login / لاگ اِن'
                          : 'New user? Sign Up / نیا اکاؤنٹ بنائیں',
                    ),
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
  bool savingProfile = false;
  bool hideEmail = false;
  bool kycSubmitting = false;
  bool kycAcknowledged = false;
  String? adminRole;
  int unreadNotifications = 0;
  bool personalEnabled = false;
  bool unifiedOwner = false;
  String unifiedMode = 'PERSONAL';
  String? v9StaffRole;
  Map<String, dynamic> personalSummary = {};
  String? kycError;
  Map<String, dynamic>? kycRequest;
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
      final appInfo = await PackageInfo.fromPlatform();
      request.headers.set('X-Sarmaya-Build', appInfo.buildNumber);
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
      final currentMode = await authenticatedRequest('GET', '/v1/platform/status');
      if (mounted) setState(() {
        unifiedOwner = currentMode['is_super_admin'] == true;
        unifiedMode = currentMode['mode']?.toString() ?? 'PERSONAL';
      });
      final result = await authenticatedRequest('GET', '/v1/me');
      if (!mounted) return;
      setState(() {
        profile = result['profile'] is Map<String, dynamic>
            ? result['profile'] as Map<String, dynamic>
            : null;
        if (profile == null) error = 'No cloud profile found for this account.';
        lastSynced = DateTime.now();
      });
      // Keep the successful profile visible if the new KYC endpoint is unavailable.
      try {
        final kyc = await authenticatedRequest('GET', '/v1/kyc-request');
        if (mounted) setState(() {
          kycRequest = kyc['request'] is Map<String, dynamic>
              ? kyc['request'] as Map<String, dynamic>
              : null;
          kycError = null;
        });
      } catch (e) {
        if (mounted) setState(() => kycError = 'KYC request sync unavailable: $e');
      }
      try {
        final notifications = await authenticatedRequest('GET', '/v1/notifications');
        if (mounted) setState(() => unreadNotifications =
            (notifications['unread'] as num?)?.toInt() ?? 0);
      } catch (_) {
        // Keep existing cloud profile available if notifications are temporarily offline.
      }
      // Owner-only personal records; never infer access from local device state.
      try {
        final personal = await authenticatedRequest('GET', '/v1/personal/summary');
        if (mounted) setState(() {
          personalEnabled = personal['personal_only'] == true;
          personalSummary = personal;
        });
      } catch (_) {
        if (mounted) setState(() { personalEnabled = false; personalSummary = {}; });
      }
      // Remittance roles come from a signed, D1-authorized backend response.
      try {
        final v9Access = await authenticatedRequest('GET', '/v1/remit/access');
        if (mounted) setState(() => v9StaffRole = v9Access['staff'] == true
            ? v9Access['role']?.toString() : null);
      } catch (_) { if (mounted) setState(() => v9StaffRole = null); }
      // Ordinary accounts get no Admin button. A verified UID alone is insufficient.
      try {
        final access = await authenticatedRequest('GET', '/v1/admin/overview');
        if (mounted) setState(() => adminRole =
            access['role'] == 'admin' || access['role'] == 'reviewer'
                ? access['role'] as String : null);
      } catch (_) {
        if (mounted) setState(() => adminRole = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _editName() async {
    if (profile == null || savingProfile || loading) return;
    String candidate = cloudName;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit name / نام تبدیل کریں'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: cloudName,
              onChanged: (value) => candidate = value,
              maxLength: 100,
              maxLines: 1,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Full name / مکمل نام'),
            ),
            const Text(
              'Only your display name can be changed. Your email, KYC status and account ID stay protected.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, candidate),
            child: const Text('Save name'),
          ),
        ],
      ),
    );
    if (!mounted || newName == null) return;
    final name = newName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.runes.length < 2 || name.runes.length > 100 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      _snack('Enter a name between 2 and 100 characters.');
      return;
    }
    if (name == cloudName) return;
    setState(() => savingProfile = true);
    try {
      final response = await authenticatedRequest('PATCH', '/v1/me', {
        'display_name': name,
      });
      final updated = response['profile'];
      if (updated is! Map<String, dynamic> || updated['display_name'] != name) {
        throw Exception('Server did not confirm the updated name.');
      }
      if (!mounted) return;
      setState(() {
        profile = updated;
        error = null;
        lastSynced = DateTime.now();
      });
      // The D1 profile is authoritative; a Firebase display-name sync failure
      // must not undo a correctly saved Cloudflare profile.
      try {
        await widget.user.updateDisplayName(name);
      } catch (_) { /* A future sign-in will still load the cloud profile. */ }
      _snack('Name updated successfully in your cloud account.');
    } catch (e) {
      _snack('Name not updated: $e');
    } finally {
      if (mounted) setState(() => savingProfile = false);
    }
  }

  Future<void> _submitKycRequest() async {
    if (kycSubmitting || profile == null || kycRequest != null ||
        cloudStatus != 'pending_kyc' || !kycAcknowledged) return;
    setState(() { kycSubmitting = true; kycError = null; });
    try {
      final response = await authenticatedRequest('POST', '/v1/kyc-request', {
        'acknowledged': true,
        'version': 'kyc-request-2026-11',
      });
      final received = response['request'];
      if (received is! Map<String, dynamic>) {
        throw Exception('Server did not confirm your request.');
      }
      if (!mounted) return;
      setState(() {
        kycRequest = received;
        kycAcknowledged = false;
      });
      _snack('KYC review request received. Your identity is NOT yet verified.');
    } catch (e) {
      if (mounted) setState(() => kycError = 'Request not submitted: $e');
    } finally {
      if (mounted) setState(() => kycSubmitting = false);
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

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => NotificationsPage(request: authenticatedRequest),
    ));
    if (mounted) refreshProfile();
  }

  Future<void> _openUnified() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => UnifiedCustomerPage(request: authenticatedRequest,
        owner: unifiedOwner, mode: unifiedMode),
    ));
    if (mounted) refreshProfile();
  }

  Future<void> _openModeControl() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => UnifiedModePage(request: authenticatedRequest),
    ));
    if (mounted) refreshProfile();
  }

  Future<void> _openPersonal() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PersonalLedgerPage(request: authenticatedRequest, ownerName: cloudName),
    ));
    if (mounted) refreshProfile();
  }

  Future<void> _openTransferCustomer() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => TransferCustomerPage(request: authenticatedRequest),
    ));
    if (mounted) refreshProfile();
  }

  Future<void> _openV11() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      V11HubPage(request: authenticatedRequest, owner: unifiedOwner)));
    if (mounted) refreshProfile();
  }

  Future<void> _openTransferAdmin() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => TransferAdminPage(
        request: authenticatedRequest, owner: unifiedOwner,
        openInvestors: _openUnified,
        openPersonal: _openPersonal,
        openMode: _openModeControl,
        openKyc: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AdminConsolePage(request: authenticatedRequest),
        )),
      ),
    ));
    if (mounted) refreshProfile();
  }

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
        _sectionHeading('Main Dashboards / مرکزی ڈیش بورڈ'),
        if (unifiedOwner || v9StaffRole != null) Card(color: paleGreen, child: ListTile(
          leading: const Icon(Icons.admin_panel_settings, color: deepGreen),
          title: const Text('1. Admin & Staff'),
          subtitle: Text(unifiedOwner ? 'Owner • Staff • Orders • Rates • Trades'
              : 'Staff • Assigned order permissions'),
          trailing: const Icon(Icons.chevron_right), onTap: _openTransferAdmin,
        )),
        Card(color: paleGreen, child: ListTile(
          leading: const Icon(Icons.trending_up, color: deepGreen),
          title: const Text('2. P2P Trading Investors'),
          subtitle: const Text('Investments • Balance • Profit • Requests'),
          trailing: const Icon(Icons.chevron_right), onTap: _openUnified,
        )),
        Card(color: paleGreen, child: ListTile(
          leading: const Icon(Icons.currency_exchange, color: deepGreen),
          title: const Text('3. AED to PKR'),
          subtitle: const Text('Published Rate • Calculator • Sender • Receiver • Orders'),
          trailing: const Icon(Icons.chevron_right), onTap: _openTransferCustomer,
        )),
        Card(color: paleGreen, child: ListTile(
          leading: const Icon(Icons.auto_awesome, color: deepGreen),
          title: const Text('Sarmaya Plus v11 — Final Tools'),
          subtitle: const Text('Multi-Lot Sales • Records • Plans • Reports • Backups'),
          trailing: const Icon(Icons.chevron_right), onTap: _openV11,
        )),
        _sectionHeading('Account Overview / اکاؤنٹ خلاصہ'),
        if (profile != null) _statusBanner(),
        if (profile == null && !loading)
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Your Cloudflare profile is not available. Refresh to try again.'),
          )),
        Card(child: Column(children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined, color: deepGreen),
            title: const Text('Notifications / اطلاعات'),
            subtitle: Text(unreadNotifications == 0
                ? 'KYC updates and account notices'
                : '$unreadNotifications unread notification(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openNotifications,
          ),
          const Divider(height: 1),
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
        _sectionHeading(unifiedOwner ? 'Customer Accounts / کسٹمر اکاؤنٹس'
            : 'My Customer Account / میرا حساب'),
        Card(color: paleGreen, child: ListTile(
          leading: const Icon(Icons.groups_2_outlined, color: deepGreen),
          title: Text(unifiedOwner ? 'Customers, Investments & Profit Distribution'
              : 'My Balance, Statements & Requests'),
          subtitle: Text(unifiedOwner
              ? 'A separate private customer ledger for every person'
              : 'Only your linked customer records are visible'),
          trailing: const Icon(Icons.chevron_right), onTap: _openUnified,
        )),
        if (personalEnabled) ...[
          _sectionHeading('My Personal Finance / ذاتی مالی ریکارڈ'),
          Card(color: paleGreen, child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined, color: deepGreen),
            title: const Text('Private Ledger & USDT Journal / ذاتی حساب'),
            subtitle: Text('Manual PKR, AED & USDT records • ${personalSummary['journal_count'] ?? 0} entries'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPersonal,
          )),
        ],
        _sectionHeading('Service availability'),
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline, color: deepGreen),
            SizedBox(width: 12),
            Expanded(child: Text(
              'The customer accounts and trading journal record manual transactions. The app does not connect to banks, payment gateways or exchanges to move money.',
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
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: savingProfile || loading || profile == null ? null : _editName,
                icon: savingProfile
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.edit_outlined),
                label: Text(savingProfile ? 'Saving...' : 'Edit name / نام تبدیل کریں'),
              ),
            ),
            const Divider(height: 28),
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
            'You can securely update your name in Cloudflare. Email, account status, KYC, registration/referral records and account ID cannot be changed here.',
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
              'You can request a future identity review. This does NOT verify your identity or approve your account. Do not enter or upload CNIC, passport, birth date, photos or other identity documents.',
            )),
          ]),
        )),
        _sectionHeading('Request a KYC review / درخواست'),
        if (kycError != null) Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(kycError!, style: const TextStyle(color: Colors.red)),
        )),
        if (kycRequest != null) Card(
          color: paleGreen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your request was received / درخواست موصول ہوگئی',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 9),
              Text('Request status: ${kycRequest!['status'] ?? 'submitted'}'),
              const SizedBox(height: 5),
              Text('Submitted (UTC): ${kycRequest!['created_at'] ?? 'Unknown'}'),
              const SizedBox(height: 10),
              const Text('This is a review request only. KYC remains pending until a separate authorized verification process is completed.',
                style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
        if (kycRequest == null && profile != null && cloudStatus == 'pending_kyc')
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Request to join the identity review queue',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Only your existing Cloudflare account ID is used. No identity documents or ID numbers are requested.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I understand this does not verify my identity or enable financial services.'),
                value: kycAcknowledged,
                onChanged: kycSubmitting ? null
                    : (value) => setState(() => kycAcknowledged = value ?? false),
              ),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: kycAcknowledged && !kycSubmitting ? _submitKycRequest : null,
                icon: kycSubmitting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
                label: Text(kycSubmitting ? 'Submitting...' : 'Submit review request / درخواست بھیجیں'),
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
        if (unifiedOwner) ...[
          _sectionHeading('Super Admin / سپر ایڈمن'),
          Card(child: ListTile(
            leading: const Icon(Icons.toggle_on_outlined, color: deepGreen),
            title: Text('Application Mode: $unifiedMode'),
            subtitle: const Text('Personal / Multi-User • freeze & restore customer access'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openModeControl,
          )),
        ],
        Card(child: ListTile(
          leading: const Icon(Icons.people_outline, color: deepGreen),
          title: Text(unifiedOwner ? 'Customer Accounts / کسٹمر اکاؤنٹس' : 'My Customer Dashboard'),
          subtitle: Text(unifiedOwner ? 'Private balances, investments, support & profit reports'
              : 'View only your own statements'),
          trailing: const Icon(Icons.chevron_right), onTap: _openUnified,
        )),
        if (adminRole != null) ...[
          _sectionHeading('Admin Console / ایڈمن'),
          Card(child: ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined, color: deepGreen),
            title: const Text('Admin KYC Review / انتظامی جائزہ'),
            subtitle: const Text('Review queue, users and audit history'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => AdminConsolePage(request: authenticatedRequest),
            )),
          )),
        ],
        if (personalEnabled) Card(child: ListTile(
          leading: const Icon(Icons.wallet_outlined, color: deepGreen),
          title: const Text('Personal Ledger / ذاتی مالی ریکارڈ'),
          subtitle: const Text('Income, expenses, USDT trades (manual), reports'),
          trailing: const Icon(Icons.chevron_right), onTap: _openPersonal,
        )),
        _sectionHeading('Account Settings / اکاؤنٹ سیٹنگز'),
        Card(child: Column(children: [
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined, color: deepGreen),
            title: const Text('My Notifications / میری اطلاعات'),
            subtitle: Text('$unreadNotifications unread'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openNotifications,
          ),
          const Divider(height: 1),
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
            'Sarmaya Plus • Unified Edition v11\n'
            'Login: Firebase Authentication\n'
            'Account profile: Cloudflare API + D1\n'
            'KYC checklist and email-hide setting: stored on this device only\n\n'
            'Staff and customers can access only their permitted records. Trading journals and transfer orders are internal records; no banking or crypto transfer is executed by this app.',
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


// Admin functions are always authorized in Cloudflare, never by the app UI.
// Role actions can ONLY grant/revoke reviewer access; existing admin role is protected.
class AdminConsolePage extends StatefulWidget {
  const AdminConsolePage({super.key, required this.request});
  final ApiRequest request;

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage> {
  final searchController = TextEditingController();
  bool loading = false;
  bool changing = false;
  String? error;
  String? busyUid;
  String role = '';
  String search = '';
  String filter = 'all';
  int section = 0;
  int offset = 0;
  int total = 0;
  int pageSize = 20;
  int reportDays = 30;
  Map<String, dynamic> metrics = {};
  Map<String, dynamic> reports = {};
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> events = [];
  List<Map<String, dynamic>> roles = [];
  List<Map<String, dynamic>> roleEvents = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> asRecords(dynamic items) {
    if (items is! List) return [];
    return items.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  String textOf(dynamic value) => value?.toString() ?? '';
  String pathWithQuery(String path, [Map<String, String> query = const {}]) =>
      Uri(path: path, queryParameters: query).toString();

  Future<void> refresh() async {
    if (!mounted || loading) return;
    setState(() { loading = true; error = null; });
    try {
      final overview = await widget.request('GET', '/v1/admin/overview');
      final newRole = textOf(overview['role']);
      final newMetrics = overview['metrics'] is Map
          ? Map<String, dynamic>.from(overview['metrics'] as Map) : <String, dynamic>{};
      var rows = <Map<String, dynamic>>[];
      var newReports = <String, dynamic>{};
      var newRoles = <Map<String, dynamic>>[];
      var newCount = 0;
      if (section == 0) {
        final data = await widget.request('GET', pathWithQuery('/v1/admin/requests', {
          'q': search, 'status': filter, 'offset': '$offset',
        }));
        rows = asRecords(data['requests']);
        newCount = (data['total'] as num?)?.toInt() ?? rows.length;
      } else if (section == 1) {
        final data = await widget.request('GET', pathWithQuery('/v1/admin/users', {
          'q': search, 'offset': '$offset',
        }));
        rows = asRecords(data['users']);
        newCount = (data['total'] as num?)?.toInt() ?? rows.length;
      } else if (section == 2) {
        final data = await widget.request('GET', pathWithQuery('/v1/admin/audit', {
          'offset': '$offset',
        }));
        rows = asRecords(data['events']);
        newCount = (data['total'] as num?)?.toInt() ?? rows.length;
      } else if (section == 3) {
        newReports = await widget.request('GET', pathWithQuery('/v1/admin/reports', {
          'days': '$reportDays',
        }));
      } else if (section == 4 && newRole == 'admin') {
        final rolesResponse = await widget.request('GET', '/v1/admin/reviewers');
        final history = await widget.request('GET', pathWithQuery('/v1/admin/role-audit', {
          'offset': '$offset',
        }));
        newRoles = asRecords(rolesResponse['roles']);
        rows = asRecords(history['events']);
        newCount = (history['total'] as num?)?.toInt() ?? rows.length;
      }
      if (!mounted) return;
      setState(() {
        role = newRole;
        metrics = newMetrics;
        total = newCount;
        if (section == 0) requests = rows;
        if (section == 1) users = rows;
        if (section == 2) events = rows;
        if (section == 3) reports = newReports;
        if (section == 4) { roles = newRoles; roleEvents = rows; }
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Unable to load Admin data: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void switchSection(int index) {
    if (section == index || loading) return;
    setState(() { section = index; offset = 0; total = 0; error = null; });
    refresh();
  }

  void findRecords() {
    if (loading) return;
    final next = searchController.text.trim();
    if (next.length > 64) {
      showMessage('Search must be 64 characters or fewer.');
      return;
    }
    setState(() { search = next; offset = 0; });
    refresh();
  }

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<String> transitions(String state) => switch (state) {
    'submitted' => ['under_review', 'needs_information', 'closed'],
    'under_review' => ['needs_information', 'closed'],
    'needs_information' => ['under_review', 'closed'],
    _ => [],
  };

  String statusTitle(String status) => switch (status) {
    'submitted' => 'Submitted / موصول',
    'under_review' => 'Under review / جائزہ جاری',
    'needs_information' => 'Needs information / مزید معلومات',
    'closed' => 'Closed / درخواست بند',
    _ => status,
  };

  Future<bool> confirm(String title, String detail) async {
    final yes = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title), content: Text(detail),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm')),
          ],
        ));
    return yes == true;
  }

  Future<void> changeStatus(Map<String, dynamic> row, String next) async {
    if (changing || loading) return;
    final uid = textOf(row['firebase_uid']);
    if (!await confirm('Change review status?',
        '${textOf(row['display_name'])}\n'
        '${statusTitle(textOf(row['status']))} → ${statusTitle(next)}\n\n'
        'Review status only. Identity stays unverified; no financial access is enabled.')) return;
    if (!mounted) return;
    setState(() { changing = true; busyUid = uid; });
    try {
      await widget.request('POST', '/v1/admin/request-status', {
        'firebase_uid': uid, 'status': next,
      });
      showMessage('Review saved. Audit entry and user notification created.');
    } catch (e) {
      showMessage('Review was not saved: $e');
    } finally {
      if (mounted) setState(() { changing = false; busyUid = null; });
    }
    await refresh();
  }

  Future<void> changeReviewer(Map<String, dynamic> row, bool enable) async {
    if (role != 'admin' || changing || loading) return;
    final uid = textOf(row['firebase_uid']);
    final name = textOf(row['display_name']);
    final action = enable ? 'Grant reviewer access' : 'Disable reviewer access';
    if (!await confirm(action, '$name\n\nReviewer access allows limited KYC review.'
        ' It does not approve identity or enable money transactions.')) return;
    if (!mounted) return;
    setState(() { changing = true; busyUid = uid; });
    try {
      await widget.request('POST', '/v1/admin/reviewer-role', {
        'firebase_uid': uid, 'enabled': enable,
      });
      showMessage('Reviewer access updated and recorded in audit history.');
    } catch (e) {
      showMessage('Role was not changed: $e');
    } finally {
      if (mounted) setState(() { changing = false; busyUid = null; });
    }
    await refresh();
  }

  Widget metric(String label, dynamic n, IconData icon) => SizedBox(
    width: 155,
    child: Card(color: paleGreen,
      child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: deepGreen),
          const SizedBox(height: 8),
          Text(textOf(n).isEmpty ? '0' : textOf(n),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    ),
  );

  Widget requestCard(Map<String, dynamic> row) {
    final state = textOf(row['status']);
    final choices = transitions(state);
    return Card(child: ListTile(
      title: Text(textOf(row['display_name']),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(textOf(row['email'])),
        Text(statusTitle(state), style: const TextStyle(color: deepGreen)),
        Text('Submitted UTC: ${textOf(row['created_at'])}',
            style: const TextStyle(fontSize: 12)),
      ]),
      trailing: choices.isEmpty ? const Icon(Icons.check_circle_outline) :
          PopupMenuButton<String>(
            enabled: !changing && !loading,
            tooltip: 'Change review status',
            onSelected: (value) => changeStatus(row, value),
            itemBuilder: (_) => choices.map((value) => PopupMenuItem<String>(
              value: value, child: Text(statusTitle(value)),
            )).toList(),
          ),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: textOf(row['firebase_uid'])));
        showMessage('Account ID copied. Treat it as private.');
      },
    ));
  }

  Widget userCard(Map<String, dynamic> row) {
    final uid = textOf(row['firebase_uid']);
    final adminRole = textOf(row['admin_role']);
    final reviewerOn = adminRole == 'reviewer' && (row['admin_enabled'] as num?) == 1;
    final isSelf = FirebaseAuth.instance.currentUser?.uid == uid;
    return Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.person_outline, color: deepGreen),
          title: Text(textOf(row['display_name'])),
          subtitle: Text('${textOf(row['email'])}\n'
              'Account: ${textOf(row['status'])}\n'
              'KYC: ${textOf(row['kyc_request_status']).isEmpty ? 'Not requested' : textOf(row['kyc_request_status'])}\n'
              'Role: ${adminRole.isEmpty ? 'User' : (reviewerOn || adminRole == 'admin' ? adminRole : 'Reviewer disabled')}'),
        ),
        if (role == 'admin' && adminRole != 'admin' && !isSelf)
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: OutlinedButton.icon(
              onPressed: changing ? null : () => changeReviewer(row, !reviewerOn),
              icon: Icon(reviewerOn ? Icons.person_remove_outlined : Icons.person_add_alt_1_outlined),
              label: Text(reviewerOn ? 'Disable reviewer' : 'Grant reviewer'),
            ),
          ),
      ]),
    ));
  }

  Widget auditCard(Map<String, dynamic> row) => Card(child: ListTile(
    leading: const Icon(Icons.history, color: deepGreen),
    title: Text('${textOf(row['old_status'])} → ${textOf(row['new_status'])}'),
    subtitle: Text('Reviewer: ${textOf(row['actor_name']).isEmpty ? textOf(row['actor_uid']) : textOf(row['actor_name'])}\n'
        'Account: ${textOf(row['target_uid'])}\nUTC: ${textOf(row['created_at'])}'),
  ));

  Widget roleAuditCard(Map<String, dynamic> row) => Card(child: ListTile(
    leading: const Icon(Icons.manage_accounts_outlined, color: deepGreen),
    title: Text('${textOf(row['old_role']).isEmpty ? 'User' : textOf(row['old_role'])} → '
        '${textOf(row['new_enabled']) == '1' ? 'Active reviewer' : 'Reviewer disabled'}'),
    subtitle: Text('Account: ${textOf(row['target_uid'])}\n'
        'Changed by: ${textOf(row['actor_name'])}\nUTC: ${textOf(row['created_at'])}'),
  ));

  Widget paging() {
    if (section == 3 || loading) return const SizedBox.shrink();
    final first = total == 0 ? 0 : offset + 1;
    final last = total < offset + pageSize ? total : offset + pageSize;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('Showing $first–$last of $total', style: const TextStyle(fontSize: 12)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Previous page', icon: const Icon(Icons.chevron_left),
          onPressed: offset == 0 ? null : () {
            setState(() => offset -= pageSize);
            refresh();
          }),
        IconButton(tooltip: 'Next page', icon: const Icon(Icons.chevron_right),
          onPressed: offset + pageSize >= total ? null : () {
            setState(() => offset += pageSize);
            refresh();
          }),
      ]),
    ]);
  }

  Widget reportWidgets() {
    final statuses = asRecords(reports['request_status']);
    final days = asRecords(reports['daily_requests']);
    final activeRoles = asRecords(reports['active_roles']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: [7, 30, 90].map((value) => ChoiceChip(
        label: Text('$value days'), selected: reportDays == value,
        onSelected: (_) { setState(() => reportDays = value); refresh(); },
      )).toList()),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Operational activity (not a financial report)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('KYC review changes: ${textOf(reports['review_changes'])}'),
          Text('Reviewer role changes: ${textOf(reports['role_changes'])}'),
          const SizedBox(height: 9),
          ...statuses.map((row) => Text('${statusTitle(textOf(row['status']))}: ${textOf(row['n'])}')),
          const SizedBox(height: 9),
          ...activeRoles.map((row) => Text('Active ${textOf(row['role'])}: ${textOf(row['n'])}')),
        ]),
      )),
      const SizedBox(height: 12),
      const Text('KYC requests created by day (UTC)', style: TextStyle(fontWeight: FontWeight.bold)),
      if (days.isEmpty) const Text('No requests for this period'),
      ...days.map((row) => Card(child: ListTile(
        leading: const Icon(Icons.calendar_today_outlined, color: deepGreen),
        title: Text(textOf(row['day'])),
        trailing: Text(textOf(row['submitted'])),
      ))),
      const SizedBox(height: 12),
      const Text('No investment, payments or profits are processed or reported by this version.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }

  Widget roleWidgets() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Active roles / Administrative access',
        style: TextStyle(fontWeight: FontWeight.bold, color: deepGreen)),
    const SizedBox(height: 5),
    const Text('Only the existing Admin can grant or disable Reviewer access using the Users tab. '
        'Admin ownership cannot be granted or removed in the app.',
        style: TextStyle(fontSize: 12)),
    ...roles.map((row) => Card(child: ListTile(
      leading: const Icon(Icons.shield_outlined, color: deepGreen),
      title: Text(textOf(row['display_name'])),
      subtitle: Text('${textOf(row['email'])}\n${textOf(row['role'])} • '
          '${textOf(row['enabled']) == '1' ? 'Enabled' : 'Disabled'}'),
    ))),
    const SizedBox(height: 12),
    const Text('Role audit history', style: TextStyle(fontWeight: FontWeight.bold, color: deepGreen)),
    ...roleEvents.map(roleAuditCard),
  ]);

  @override
  Widget build(BuildContext context) {
    final rows = section == 0 ? requests : section == 1 ? users :
        section == 2 ? events : roleEvents;
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Console / ایڈمن'), actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh',
          onPressed: loading ? null : refresh),
      ]),
      body: RefreshIndicator(onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          Text('Firebase admin access • ${role.isEmpty ? 'Checking...' : role}',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            metric('Users', metrics['users'], Icons.people_outline),
            metric('KYC requests', metrics['requests'], Icons.badge_outlined),
            metric('New', metrics['submitted'], Icons.inbox_outlined),
            metric('Under review', metrics['under_review'], Icons.fact_check_outlined),
          ]),
          const Card(child: Padding(padding: EdgeInsets.all(12),
            child: Text('Review workflow only. No identity approvals, account activation, '
                'document uploads, deposits, withdrawals or investments.',
              style: TextStyle(fontSize: 12)))),
          Wrap(spacing: 6, runSpacing: 4, children: [
            ChoiceChip(label: const Text('KYC queue'), selected: section == 0,
              onSelected: (_) => switchSection(0)),
            ChoiceChip(label: const Text('Users'), selected: section == 1,
              onSelected: (_) => switchSection(1)),
            ChoiceChip(label: const Text('KYC audit'), selected: section == 2,
              onSelected: (_) => switchSection(2)),
            ChoiceChip(label: const Text('Reports'), selected: section == 3,
              onSelected: (_) => switchSection(3)),
            if (role == 'admin') ChoiceChip(label: const Text('Roles'),
              selected: section == 4, onSelected: (_) => switchSection(4)),
          ]),
          if (section == 0 || section == 1) ...[
            const SizedBox(height: 10),
            TextField(controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => findRecords(),
              decoration: InputDecoration(
                labelText: 'Search name / email / account ID',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.arrow_forward),
                  onPressed: findRecords),
              ),
            ),
            if (section == 0) Padding(padding: const EdgeInsets.only(top: 7),
              child: Wrap(spacing: 6, children: ['all','submitted','under_review',
                'needs_information','closed'].map((value) => ChoiceChip(
                  label: Text(value.replaceAll('_', ' ')), selected: filter == value,
                  onSelected: (_) { setState(() { filter = value; offset = 0; }); refresh(); },
                )).toList()),
            ),
          ],
          const SizedBox(height: 10),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Card(child: Padding(padding: const EdgeInsets.all(14),
            child: Text(error!, style: const TextStyle(color: Colors.red)))),
          if (!loading && error == null) ...[
            if (section == 3) reportWidgets()
            else if (section == 4) roleWidgets()
            else ...[
              if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(14),
                  child: Text('No records in this section.'))),
              ...rows.map((row) => section == 0 ? requestCard(row) :
                  section == 1 ? userCard(row) : auditCard(row)),
            ],
            if (section != 3) paging(),
          ],
        ]),
      ),
    );
  }
}

// Read-only, account-scoped notices. Only the server can create notifications.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.request});
  final ApiRequest request;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> items = [];
  int unread = 0;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    if (loading) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.request('GET', '/v1/notifications');
      final list = result['notifications'];
      if (!mounted) return;
      setState(() {
        items = list is List ? list.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)).toList() : [];
        unread = (result['unread'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> markRead(Map<String, dynamic> row) async {
    if (row['read_at'] != null) return;
    final id = row['id'];
    if (id is! int) return;
    try {
      await widget.request('POST', '/v1/notifications/read', {'id': id});
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to mark as read: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications / اطلاعات'), actions: [
      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh',
        onPressed: loading ? null : refresh),
    ]),
    body: RefreshIndicator(onRefresh: refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Unread: $unread', style: const TextStyle(color: deepGreen,
            fontWeight: FontWeight.bold)),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Card(child: Padding(padding: const EdgeInsets.all(14),
            child: Text(error!, style: const TextStyle(color: Colors.red)))),
        if (!loading && error == null && items.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16),
            child: Text('No notifications yet. Review updates will appear here.'))),
        ...items.map((row) => Card(
          color: row['read_at'] == null ? paleGreen : null,
          child: ListTile(
            leading: Icon(row['read_at'] == null ? Icons.markunread_outlined
                : Icons.mark_email_read_outlined, color: deepGreen),
            title: Text('${row['title'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${row['message'] ?? ''}\n${row['created_at'] ?? ''} UTC'),
            trailing: row['read_at'] == null
                ? IconButton(tooltip: 'Mark as read',
                    onPressed: () => markRead(row), icon: const Icon(Icons.done))
                : null,
            onTap: () => markRead(row),
          ),
        )),
      ]),
    ),
  );
}



// Sarmaya Plus Personal Edition: authenticated, owner-only bookkeeping.
// This journal NEVER sends or receives real money, crypto, or investment orders.
class PersonalLedgerPage extends StatefulWidget {
  const PersonalLedgerPage({super.key, required this.request, required this.ownerName});
  final ApiRequest request;
  final String ownerName;
  @override
  State<PersonalLedgerPage> createState() => _PersonalLedgerPageState();
}

class _PersonalLedgerPageState extends State<PersonalLedgerPage> {
  bool loading = true;
  bool saving = false;
  bool urdu = false;
  String? error;
  int days = 30;
  int offset = 0;
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> events = [];
  List<Map<String, dynamic>> positions = [];
  Map<String, dynamic> reports = {};
  int journalCount = 0;

  String t(String english, String urduText) => urdu ? urduText : english;
  List<Map<String, dynamic>> maps(Object? value) =>
      value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  String money(Object? raw, String currency) {
    final n = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    final d = currency == 'USDT' ? 6 : 2;
    final power = d == 6 ? 1000000 : 100;
    final negative = n < 0 ? '-' : '';
    final abs = n.abs();
    return '$negative${abs ~/ power}.${(abs % power).toString().padLeft(d, '0')} $currency';
  }
  String accountName(String? id) {
    for (final a in accounts) {
      if (a['account_id'] == id) return '${a['name']} (${a['currency']})';
    }
    return id == null ? t('Outside app', 'بیرونی اکاؤنٹ') : t('Unknown account', 'نامعلوم اکاؤنٹ');
  }

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    refresh();
  }
  Future<void> _loadLanguage() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => urdu = p.getBool('personal_urdu') ?? false);
  }
  Future<void> changeLanguage(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('personal_urdu', value);
    if (mounted) setState(() => urdu = value);
  }
  void message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final data = await widget.request('GET', '/v1/personal/summary');
      final list = await widget.request('GET', '/v1/personal/entries?offset=$offset');
      final report = await widget.request('GET', '/v1/personal/reports?days=$days');
      if (!mounted) return;
      setState(() {
        accounts = maps(data['accounts']);
        positions = maps(data['positions']);
        events = maps(list['events']);
        reports = report;
        journalCount = (data['journal_count'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  Future<void> perform(Future<Map<String, dynamic>> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
      message(t('Saved to private cloud journal', 'ذاتی کلاؤڈ ریکارڈ محفوظ ہوگیا'));
      await refresh();
    } catch (e) {
      message('$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
  Widget label(String title, {IconData icon = Icons.info_outline}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [Icon(icon, color: deepGreen), const SizedBox(width: 9),
      Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: deepGreen)))]),
  );
  Widget info(String text) => Card(child: Padding(
    padding: const EdgeInsets.all(14), child: Text(text)));
  Widget accountCard(Map<String, dynamic> a) => Card(child: ListTile(
    leading: const CircleAvatar(backgroundColor: paleGreen, child: Icon(Icons.account_balance_wallet_outlined, color: deepGreen)),
    title: Text('${a['name']}'),
    subtitle: Text('${a['kind']} • ${a['currency']}'),
    trailing: Text(money(a['balance_minor'], '${a['currency']}'),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
  ));
  String typeLabel(String type) {
    switch (type) {
      case 'income': return t('Manual money in', 'آمدن کا ریکارڈ');
      case 'expense': return t('Manual expense', 'اخراجات کا ریکارڈ');
      case 'transfer': return t('Internal transfer', 'اندرونی منتقلی');
      case 'p2p_buy': return t('USDT purchase journal', 'USDT خریداری کا ریکارڈ');
      case 'p2p_sell': return t('USDT sale journal', 'USDT فروخت کا ریکارڈ');
      default: return t('Reversal', 'واپسی / تصحیح');
    }
  }

  Future<void> newAccount() async {
    final name = TextEditingController();
    String currency = 'AED';
    String kind = 'wallet';
    final data = await showDialog<Map<String, String>>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => AlertDialog(
        title: Text(t('New private account', 'نیا ذاتی اکاؤنٹ')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 60, decoration: InputDecoration(labelText: t('Name', 'نام'))),
          DropdownButtonFormField<String>(value: currency, decoration: InputDecoration(labelText: t('Currency', 'کرنسی')),
            items: ['PKR', 'AED', 'USDT'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) => setModal(() => currency = v ?? currency)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: kind, decoration: InputDecoration(labelText: t('Account type', 'اکاؤنٹ کی قسم')),
            items: ['cash','bank','wallet','exchange','other']
              .map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) => setModal(() => kind = v ?? kind)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'name': name.text.trim(), 'currency': currency, 'kind': kind,
          }), child: Text(t('Create', 'بنائیں')))],
      ),
    ));
    name.dispose();
    if (data == null) return;
    await perform(() => widget.request('POST','/v1/personal/accounts', data));
  }

  Future<void> newEntry() async {
    if (accounts.isEmpty) { message(t('Create an account first', 'پہلے اکاؤنٹ بنائیں')); return; }
    String type = 'income';
    String accountId = '${accounts.first['account_id']}';
    String toId = accounts.length > 1 ? '${accounts[1]['account_id']}' : accountId;
    final amount = TextEditingController();
    final received = TextEditingController();
    final note = TextEditingController();
    final tradeProfit = TextEditingController();
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => AlertDialog(
        title: Text(t('Record manually', 'دستی ریکارڈ درج کریں')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('This DOES NOT send money or place trades.', 'اس سے رقم منتقل یا ٹریڈ نہیں ہوتی۔'),
            style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: type, isExpanded: true,
            decoration: InputDecoration(labelText: t('Entry type', 'اندراج کی قسم')),
            items: ['income','expense','transfer','p2p_buy','p2p_sell']
              .map((x) => DropdownMenuItem(value: x, child: Text(typeLabel(x)))).toList(),
            onChanged: (v) => setModal(() => type = v ?? type)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: accountId, isExpanded: true,
            decoration: InputDecoration(labelText: t('Main account', 'بنیادی اکاؤنٹ')),
            items: accounts.map((a) => DropdownMenuItem(value: '${a['account_id']}',
              child: Text('${a['name']} (${a['currency']})', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setModal(() => accountId = v ?? accountId)),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('Main amount', 'بنیادی رقم'), hintText: '100.00')),
          if (!['income','expense'].contains(type)) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: toId, isExpanded: true,
              decoration: InputDecoration(labelText: t('Destination account', 'منزل اکاؤنٹ')),
              items: accounts.map((a) => DropdownMenuItem(value: '${a['account_id']}',
                child: Text('${a['name']} (${a['currency']})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setModal(() => toId = v ?? toId)),
          ],
          if (type == 'p2p_buy' || type == 'p2p_sell') ...[
            const SizedBox(height: 12),
            TextField(controller: received, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t('Received amount', 'موصول رقم'), hintText: '25.000000')),
          ],
          if (type == 'p2p_sell') ...[
            const SizedBox(height: 12),
            TextField(controller: tradeProfit, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: t('Your estimated profit/loss (optional)',
                'آپ کا اندازاً نفع/نقصان (اختیاری)'), hintText: '2.50 or -1.00')),
          ],
          const SizedBox(height: 12),
          TextField(controller: note, maxLength: 160,
            decoration: InputDecoration(labelText: t('Note (optional)', 'نوٹ (اختیاری)'))),
          const SizedBox(height: 5),
          Text(t('Buy: fiat → USDT. Sell: USDT → fiat. Transfer: same currency.',
            'خرید: رقم سے USDT، فروخت: USDT سے رقم۔ منتقلی: ایک ہی کرنسی۔'),
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'type': type, 'account_id': accountId, 'to_account_id': toId,
            'amount': amount.text.trim(), 'received_amount': received.text.trim(),
            'note': note.text.trim(), 'trade_profit': tradeProfit.text.trim(),
          }), child: Text(t('Save record', 'ریکارڈ محفوظ کریں')))],
      ),
    ));
    amount.dispose(); received.dispose(); note.dispose(); tradeProfit.dispose();
    if (data == null) return;
    data['request_id'] = 'p_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1000000000)}';
    await perform(() => widget.request('POST', '/v1/personal/entries', data));
  }

  Future<void> reverseEntry(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('Reverse this record?', 'یہ اندراج واپس کریں؟')),
      content: Text(t('An opposite journal entry will be created; history is not deleted. If the balance is too low, reversal will be rejected.',
        'الٹا اندراج بنے گا، تاریخ حذف نہیں ہوگی۔ بیلنس کم ہوا تو عمل رد ہوگا۔')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false),child: Text(t('Cancel', 'منسوخ'))),
        FilledButton(onPressed: () => Navigator.pop(ctx,true), child: Text(t('Confirm', 'تصدیق')))],
    ));
    if (ok != true) return;
    await perform(() => widget.request('POST', '/v1/personal/reverse', {'event_id': e['event_id']}));
  }

  Future<void> editPosition([Map<String, dynamic>? existing]) async {
    final asset = TextEditingController(text: '${existing?['asset_name'] ?? ''}');
    final units = TextEditingController(text: existing == null ? '' : money(existing['units_micros'], 'USDT').split(' ').first);
    final cost = TextEditingController(text: existing == null ? '' : money(existing['cost_minor'], '${existing['quote_currency']}').split(' ').first);
    final value = TextEditingController(text: existing == null ? '' : money(existing['current_value_minor'], '${existing['quote_currency']}').split(' ').first);
    final notes = TextEditingController(text: '${existing?['notes'] ?? ''}');
    String currency = '${existing?['quote_currency'] ?? 'AED'}';
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => AlertDialog(
        title: Text(t('Manual investment valuation', 'سرمایہ کاری کی دستی قیمت')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: asset, maxLength: 60,
            decoration: InputDecoration(labelText: t('Asset (e.g. USDT, gold)', 'اثاثہ (USDT، سونا وغیرہ)'))),
          TextField(controller: units, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('Units (max 6 decimals)', 'تعداد (6 اعشاری مقامات)'))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: currency,
            decoration: InputDecoration(labelText: t('Value currency', 'قیمت کی کرنسی')),
            items: ['AED','PKR'].map((x) => DropdownMenuItem(value: x,child: Text(x))).toList(),
            onChanged: (v) => setModal(() => currency = v ?? currency)),
          const SizedBox(height: 12),
          TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('Original cost', 'اصل لاگت'))),
          const SizedBox(height: 12),
          TextField(controller: value, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('Estimated current value', 'موجودہ اندازاً قیمت'))),
          const SizedBox(height: 12),
          TextField(controller: notes, maxLength: 160,
            decoration: InputDecoration(labelText: t('Notes', 'نوٹس'))),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel','منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            if (existing != null) 'position_id': existing['position_id'],
            'asset_name': asset.text.trim(), 'units': units.text.trim(),
            'quote_currency': currency, 'cost': cost.text.trim(),
            'current_value': value.text.trim(), 'notes': notes.text.trim(),
          }), child: Text(t('Save','محفوظ کریں')))],
      ),
    ));
    asset.dispose(); units.dispose(); cost.dispose(); value.dispose(); notes.dispose();
    if (data == null) return;
    await perform(() => widget.request('POST','/v1/personal/positions',data));
  }

  Future<void> exportCopy() async {
    final sure = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('Copy private JSON backup?', 'ذاتی JSON بیک اپ کاپی کریں؟')),
      content: Text(t('This copies sensitive personal financial records to your phone clipboard. Copy it only into a private safe place. Maximum 1,000 records per backup.',
        'اس سے ذاتی مالی ریکارڈ فون کے کلپ بورڈ میں جائے گا۔ صرف محفوظ جگہ رکھیں۔ زیادہ سے زیادہ 1000 ریکارڈ۔')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: Text(t('Cancel','منسوخ'))),
        FilledButton(onPressed: () => Navigator.pop(ctx,true), child: Text(t('Copy','کاپی')))],
    ));
    if (sure != true) return;
    try {
      final result = await widget.request('GET','/v1/personal/export');
      await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(result)));
      message(result['truncated'] == true
        ? t('Partial backup copied: export exceeds limit','جزوی بیک اپ کاپی ہوا، ریکارڈ زیادہ ہیں')
        : t('Private backup copied','ذاتی بیک اپ کاپی ہوگیا'));
    } catch (e) { message('$e'); }
  }

  List<Widget> overview() => [
    label(t('Personal money tracker', 'ذاتی مالی ریکارڈ'), icon: Icons.wallet_outlined),
    info(t('Only your verified account can open these records. No funds, payments or USDT are held, moved, or traded by this app.',
      'یہ صرف آپ کے ذاتی اکاؤنٹ کا ریکارڈ ہے۔ ایپ سے رقم یا USDT وصول، منتقل یا ٹریڈ نہیں ہوتی۔')),
    Card(color: paleGreen, child: Padding(padding: const EdgeInsets.all(17), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Welcome, ${widget.ownerName}', 'خوش آمدید، ${widget.ownerName}'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
        const SizedBox(height: 8),
        Text(t('$journalCount journal records', '$journalCount اندراجات')),
        const SizedBox(height: 9),
        ...['AED','PKR','USDT'].map((c) {
          final minor = accounts.where((a) => a['currency'] == c)
            .fold<int>(0, (sum, a) => sum + ((a['balance_minor'] as num?)?.toInt() ?? 0));
          return Padding(padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(money(minor,c), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)));
        }),
      ]))),
    const SizedBox(height: 14),
    FilledButton.icon(onPressed: saving ? null : newEntry,
      icon: const Icon(Icons.add), label: Text(t('Add manual transaction', 'نیا دستی اندراج'))),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: saving ? null : newAccount,
      icon: const Icon(Icons.add_card_outlined), label: Text(t('Create account', 'نیا اکاؤنٹ'))),
    label(t('Your accounts', 'آپ کے اکاؤنٹس'), icon: Icons.account_balance_wallet_outlined),
    ...accounts.map(accountCard),
  ];
  List<Widget> accountWidgets() => [
    label(t('Cash, bank and wallet records', 'کیش، بینک اور والٹ کا ریکارڈ'), icon: Icons.account_balance),
    OutlinedButton.icon(onPressed: saving ? null : newAccount,
      icon: const Icon(Icons.add), label: Text(t('New account','نیا اکاؤنٹ'))),
    const SizedBox(height: 8),
    ...accounts.map(accountCard),
    info(t('Balances are self-entered bookkeeping values, not verified bank or blockchain balances.',
      'یہ آپ کا دستی حساب ہے، حقیقی بینک یا بلاک چین بیلنس کی تصدیق نہیں۔')),
  ];
  List<Widget> journalWidgets() => [
    label(t('Immutable transaction journal', 'مستقل لین دین ریکارڈ'), icon: Icons.receipt_long),
    FilledButton.icon(onPressed: saving ? null : newEntry, icon: const Icon(Icons.add),
      label: Text(t('Add record','نیا اندراج'))),
    ...events.map((e) {
      final postings = maps(e['postings']);
      final visible = postings.where((p) => p['account_id'] != null).toList();
      final reversed = e['reversed_by'] != null || e['reverse_of'] != null;
      return Card(child: Padding(padding: const EdgeInsets.all(12),child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,children: [
          Row(children: [Expanded(child: Text(typeLabel('${e['type']}'),
            style: const TextStyle(fontWeight: FontWeight.bold))),
            if (!reversed) IconButton(tooltip: t('Reverse','واپس کریں'), onPressed: saving ? null : () => reverseEntry(e),
              icon: const Icon(Icons.undo_outlined))]),
          Text('${e['created_at'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (reversed) Text(t('Reversed / correction','واپس / تصحیح'),
            style: const TextStyle(color: Colors.deepOrange)),
          if (e['trade_pnl_minor'] != null) Text(
            '${t('Self-reported P/L', 'اپنا درج کردہ نفع/نقصان')}: '
            '${money(e['trade_pnl_minor'], '${e['trade_pnl_currency']}')}'),
          if ('${e['note'] ?? ''}'.isNotEmpty) Text('${e['note']}'),
          ...visible.map((p) => Text('${accountName(p['account_id']?.toString())}: '
            '${money(p['amount_minor'], '${p['currency']}')}')),
        ])));
    }),
    if (events.isEmpty) info(t('No records yet. Start with a manual money-in entry.',
      'ابھی ریکارڈ نہیں۔ پہلے دستی آمدن درج کریں۔')),
    Row(children: [
      TextButton(onPressed: offset == 0 || loading ? null : () { offset = (offset - 40).clamp(0, 100000).toInt(); refresh(); },
        child: Text(t('Previous','پچھلا'))),
      Text('${offset + 1}–${offset + events.length}'),
      TextButton(onPressed: events.length < 40 || loading ? null : () { offset += 40; refresh(); },
        child: Text(t('Next','اگلا'))),
    ]),
  ];
  List<Widget> portfolioWidgets() => [
    label(t('Investment watchlist (manual)', 'سرمایہ کاری کی دستی فہرست'),icon: Icons.trending_up),
    info(t('Valuations are estimates entered by you and are NOT counted as cash or certified realized profit.',
      'قیمتیں آپ نے خود درج کی ہیں؛ یہ کیش بیلنس یا تصدیق شدہ منافع نہیں۔')),
    FilledButton.icon(onPressed: saving ? null : () => editPosition(), icon: const Icon(Icons.add_chart),
      label: Text(t('Add investment / asset','اثاثہ درج کریں'))),
    ...positions.map((p) {
      final currency = '${p['quote_currency']}';
      final profit = (p['current_value_minor'] as num).toInt() - (p['cost_minor'] as num).toInt();
      return Card(child: ListTile(
        title: Text('${p['asset_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${money(p['units_micros'], 'USDT').split(' ').first} units • '
          '${t('Cost', 'لاگت')}: ${money(p['cost_minor'],currency)} • '
          '${t('Value', 'قیمت')}: ${money(p['current_value_minor'],currency)}\n'
          '${t('Unrealized estimate','غیر حقیقی اندازاً منافع')}: ${money(profit,currency)}'),
        trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: saving ? null : () => editPosition(p)),
      ));
    }),
  ];
  List<Widget> reportWidgets() {
    final types = maps(reports['by_type']);
    final flows = maps(reports['income_expense']);
    final pnl = maps(reports['self_reported_trade_pnl']);
    return [
      label(t('Activity reports', 'سرگرمی کی رپورٹس'),icon: Icons.assessment_outlined),
      Wrap(spacing: 8, children: [7,30,90,365].map((d) => ChoiceChip(
        label: Text('$d ${t('days','دن')}'), selected: days == d,
        onSelected: (v) { if (v) { days = d; refresh(); } },
      )).toList()),
      info(t('These are manual journal summaries, not bank statements, realized trading returns, or tax reports.',
        'یہ دستی حساب کی رپورٹ ہے، بینک اسٹیٹمنٹ یا تصدیق شدہ نفع / ٹیکس رپورٹ نہیں۔')),
      ...types.map((x) => Card(child: ListTile(
        title: Text(typeLabel('${x['type']}')), trailing: Text('${x['n']}')))),
      label(t('Income and expenses', 'آمدن اور اخراجات'), icon: Icons.analytics_outlined),
      ...flows.map((x) => Card(child: ListTile(
        title: Text(typeLabel('${x['type']}')), trailing: Text(money(x['amount_minor'],'${x['currency']}'))))),
      label(t('Your entered USDT sale profit/loss', 'آپ کا درج کردہ USDT نفع/نقصان'), icon: Icons.trending_up),
      ...pnl.map((x) => Card(child: ListTile(
        title: Text(t('Estimated P/L from your entries', 'دستی اندراج سے اندازاً نفع/نقصان')),
        trailing: Text(money(x['pnl_minor'], '${x['currency']}'))))),
      OutlinedButton.icon(onPressed: exportCopy, icon: const Icon(Icons.copy_all_outlined),
        label: Text(t('Copy private JSON backup','ذاتی JSON بیک اپ کاپی کریں'))),
      SwitchListTile(title: Text(t('Urdu language for personal pages','ذاتی صفحات اردو میں')),
        value: urdu, onChanged: changeLanguage),
    ];
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
    child: DefaultTabController(length: 5, child: Scaffold(
      appBar: AppBar(
        title: Text(t('My Personal Ledger', 'میرا ذاتی حساب')),
        actions: [IconButton(onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh), tooltip: t('Refresh','تازہ کریں'))],
        bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: t('Overview','خلاصہ')),
          Tab(text: t('Accounts','اکاؤنٹس')),
          Tab(text: t('Journal','اندراجات')),
          Tab(text: t('Investments','سرمایہ کاری')),
          Tab(text: t('Reports','رپورٹس')),
        ]),
      ),
      body: Column(children: [
        if (loading) const LinearProgressIndicator(minHeight: 3),
        if (error != null) Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Text(error!, style: const TextStyle(color: Colors.red)))),
        Expanded(child: TabBarView(children: [
          overview(), accountWidgets(), journalWidgets(), portfolioWidgets(), reportWidgets(),
        ].map((children) => RefreshIndicator(onRefresh: refresh,
          child: ListView(padding: const EdgeInsets.all(14), children: children))).toList())),
      ]),
    )),
  );
}
// Sarmaya Plus Unified Edition — Personal and Multi-User modes.
// Firebase identity is verified by Worker on every request. This UI holds no admin secrets.
typedef UnifiedRequest = Future<Map<String, dynamic>> Function(
    String method, String path, [Map<String, dynamic>? body]);

class UnifiedAccessGate extends StatefulWidget {
  const UnifiedAccessGate({super.key, required this.user});
  final User user;
  @override
  State<UnifiedAccessGate> createState() => _UnifiedAccessGateState();
}

class _UnifiedAccessGateState extends State<UnifiedAccessGate>
    with WidgetsBindingObserver {
  bool loading = true;
  bool frozen = false;
  String? error;
  Timer? monitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    check();
    // Also freeze a customer already using the app when owner changes mode.
    monitor = Timer.periodic(const Duration(seconds: 30), (_) => check(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check(silent: true);
  }

  Future<void> check({bool silent = false}) async {
    try {
      final token = await widget.user.getIdToken();
      if (token == null) throw Exception('Login session unavailable');
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      try {
        final req = await http.getUrl(Uri.parse('$apiBase/v1/platform/status'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final appInfo = await PackageInfo.fromPlatform();
        req.headers.set('X-Sarmaya-Build', appInfo.buildNumber);
        final response = await req.close().timeout(const Duration(seconds: 15));
        final value = jsonDecode(await utf8.decoder.bind(response).join());
        if (response.statusCode != 200 || value is! Map<String, dynamic>) {
          throw Exception(value is Map ? '${value['error']}' : 'System mode unavailable');
        }
        final next = value['account_frozen'] == true;
        if (mounted && next && !frozen) {
          // Close customer detail routes so prior cached account data is not visible
          // after Super Admin switches the server to Personal Mode.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
          });
        }
        if (mounted && (loading || next != frozen || error != null)) {
          setState(() { frozen = next; loading = false; error = null; });
        }
      } finally { http.close(force: true); }
    } catch (e) {
      // Fail closed for all users if platform mode cannot be validated.
      if (mounted) setState(() { loading = false; frozen = true; error = '$e'; });
    }
  }

  @override
  void dispose() {
    monitor?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!frozen) return AccountHomePage(key: ValueKey(widget.user.uid), user: widget.user);
    return Scaffold(
      appBar: AppBar(title: const Text('Sarmaya Plus / سرمایہ پلس')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_clock_outlined, size: 72, color: deepGreen),
            const SizedBox(height: 20),
            const Text('Account on Hold / اکاؤنٹ عارضی طور پر بند',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(error ?? 'Super Admin has enabled Personal Mode. Your account and records are safe. Access returns when Multi-User Mode is enabled.',
              textAlign: TextAlign.center),
            const SizedBox(height: 22),
            FilledButton(onPressed: () => check(), child: const Text('Check Access / دوبارہ چیک کریں')),
            TextButton(onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Sign Out / لاگ آؤٹ')),
          ],
        )),
      )),
    );
  }
}

class UnifiedModePage extends StatefulWidget {
  const UnifiedModePage({super.key, required this.request});
  final UnifiedRequest request;
  @override
  State<UnifiedModePage> createState() => _UnifiedModePageState();
}

class _UnifiedModePageState extends State<UnifiedModePage> {
  String mode = 'PERSONAL';
  bool loading = true;
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> history = [];

  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.request('GET','/v1/platform/mode');
      if (!mounted) return;
      setState(() {
        mode = '${result['mode']}';
        history = _unifiedMaps(result['history']);
      });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> switchMode(String next) async {
    if (next == mode || busy) return;
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(next == 'PERSONAL' ? 'Enable Personal Mode?' : 'Enable Multi-User Mode?'),
      content: Text(next == 'PERSONAL'
        ? 'Other accounts will be frozen immediately. Their data will not be deleted. Only Super Admin keeps access.'
        : 'Registered customers can log in and view ONLY their linked accounts. Your private ledgers remain hidden.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Switch')),
      ],
    ));
    if (accepted != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.request('POST','/v1/platform/mode',{
        'mode': next, 'confirm': 'CONFIRM_MODE_CHANGE',
      });
      await refresh();
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Super Admin — Mode Control')),
    body: RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(16),children: [
      if (loading || busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      Card(color: paleGreen,child: Padding(padding: const EdgeInsets.all(18),child: Column(children: [
        const Icon(Icons.admin_panel_settings, size: 52, color: deepGreen),
        const SizedBox(height: 12),
        Text('Current Mode: $mode', style: const TextStyle(fontSize: 22,fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(mode == 'PERSONAL'
          ? 'Only Super Admin has access. Other customer logins are frozen.'
          : 'Customer logins are enabled with private account access.'),
      ]))),
      const SizedBox(height: 12),
      RadioListTile<String>(title: const Text('Personal Mode / ذاتی استعمال'),
        subtitle: const Text('Keep customer records private and freeze other logins'),
        value:'PERSONAL', groupValue:mode,
        onChanged: busy || loading ? null : (v) { if (v != null) switchMode(v); }),
      RadioListTile<String>(title: const Text('Multi-User Mode / تمام صارفین'),
        subtitle: const Text('Give each customer access only to their own linked account'),
        value:'MULTI', groupValue:mode,
        onChanged: busy || loading ? null : (v) { if (v != null) switchMode(v); }),
      const Divider(),
      const Text('Mode Change History', style: TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      ...history.map((h) => ListTile(
        leading: const Icon(Icons.history),
        title: Text('${h['old_mode']} → ${h['new_mode']}'),
        subtitle: Text('${h['created_at'] ?? ''}'),
      )),
      const SizedBox(height: 12),
      const Text('Switching mode never deletes profiles, balances, statements or KYC records. It does not initiate financial transfers.'),
    ])),
  );
}

List<Map<String, dynamic>> _unifiedMaps(dynamic raw) {
  if (raw is! List) return [];
  return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}

class UnifiedCustomerPage extends StatefulWidget {
  const UnifiedCustomerPage({super.key, required this.request,
    required this.owner, required this.mode});
  final UnifiedRequest request;
  final bool owner;
  final String mode;
  @override
  State<UnifiedCustomerPage> createState() => _UnifiedCustomerPageState();
}

class _UnifiedCustomerPageState extends State<UnifiedCustomerPage> {
  bool loading = true;
  bool busy = false;
  String? error;
  List<Map<String,dynamic>> clients = [];
  String customerSearch = '';
  List<Map<String,dynamic>> plans = [];
  List<Map<String,dynamic>> investments = [];
  List<Map<String,dynamic>> requests = [];
  List<Map<String,dynamic>> tickets = [];
  List<Map<String,dynamic>> periods = [];
  Map<String,dynamic>? selected;
  List<Map<String,dynamic>> entries = [];

  @override
  void initState(){super.initState(); refresh();}
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        widget.request('GET','/v1/clients'),
        widget.request('GET','/v1/plans'),
        widget.request('GET','/v1/investments'),
        widget.request('GET','/v1/clients/requests'),
        widget.request('GET','/v1/support'),
        if(widget.owner) widget.request('GET','/v1/pnl'),
      ]);
      if (!mounted) return;
      setState(() {
        clients = _unifiedMaps(results[0]['clients']);
        plans = _unifiedMaps(results[1]['plans']);
        investments = _unifiedMaps(results[2]['investments']);
        requests = _unifiedMaps(results[3]['requests']);
        tickets = _unifiedMaps(results[4]['tickets']);
        if (widget.owner) periods = _unifiedMaps(results[5]['periods']);
      });
      if (selected != null) await loadLedger('${selected!['id']}');
    } catch(e) { if(mounted) setState(() => error='$e'); }
    finally { if(mounted) setState(() => loading=false); }
  }
  Future<void> loadLedger(String id) async {
    try {
      final result=await widget.request('GET','/v1/clients/ledger?client_id=$id');
      if(mounted) setState(() {
        selected = Map<String,dynamic>.from(result['client'] as Map);
        entries = _unifiedMaps(result['entries']);
      });
    } catch(e) { alert('$e'); }
  }
  void alert(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  Future<void> perform(Future<void> Function() call) async {
    if (busy) return;
    setState(() { busy=true; error=null; });
    try { await call(); await refresh(); alert('Saved / محفوظ ہوگیا'); }
    catch(e) { alert('$e'); }
    finally { if(mounted) setState(() => busy=false); }
  }
  // Text money avoids floating-point rounding errors in wallet bookkeeping.
  int moneyValue(String input, String currency, {bool signed=false,bool allowZero=false}) {
    final digits=currency=='USDT'?6:2;
    final match=RegExp(r'^(-?)([0-9]{1,10})(?:\.([0-9]+))?$').firstMatch(input.trim());
    if(match==null || (!signed && match.group(1)=='-')) throw const FormatException('Invalid amount');
    final frac=match.group(3)??'';
    if(frac.length>digits) throw FormatException('Max $digits decimal places');
    final whole=int.parse(match.group(2)!);
    final units=whole*(_power10(digits)) + int.parse(frac.padRight(digits,'0'));
    if(units>1000000000000 || (!allowZero && units==0)) throw const FormatException('Amount out of range');
    return match.group(1)=='-'?-units:units;
  }
  int _power10(int n){var v=1;for(var i=0;i<n;i++)v*=10;return v;}
  String showMoney(dynamic raw,String currency) {
    final value=(raw is num?raw.toInt():int.tryParse('$raw')??0);
    final scale=_power10(currency=='USDT'?6:2);
    final fraction=(value.abs()%scale).toString().padLeft(currency=='USDT'?6:2,'0');
    final prefix=value<0?'-':'';
    return '$prefix${value.abs()~/scale}.$fraction $currency';
  }
  String getClientName(String id) {
    for(final c in clients) { if(c['id']==id) return '${c['full_name']}'; }
    return id.substring(0,id.length>8?8:id.length);
  }
  Future<String?> textPrompt(String title, String label, {String initial=''}) async {
    final ctrl=TextEditingController(text:initial);
    try { return await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:TextField(controller:ctrl,autofocus:true,
      decoration:InputDecoration(labelText:label)),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,ctrl.text.trim()),child:const Text('Save')),
    ])); } finally {ctrl.dispose();}
  }
  Future<void> newClient() async => customerForm();
  Future<void> customerForm([Map<String,dynamic>? current]) async {
    final name=TextEditingController(text:'${current?['full_name'] ?? ''}');
    final phone=TextEditingController(text:'${current?['phone'] ?? ''}');
    final email=TextEditingController(text:'${current?['email'] ?? ''}');
    final address=TextEditingController(text:'${current?['address'] ?? ''}');
    String currency='${current?['currency'] ?? 'PKR'}';
    try {
      final data=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>StatefulBuilder(
        builder:(ctx,change)=>AlertDialog(
          title:Text(current==null?'Create Customer Account':'Edit Customer Profile'),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:name,decoration:const InputDecoration(labelText:'Full Name *')),
            const SizedBox(height:10),
            TextField(controller:phone,keyboardType:TextInputType.phone,
              decoration:const InputDecoration(labelText:'Mobile Number (optional)')),
            const SizedBox(height:10),
            TextField(controller:email,keyboardType:TextInputType.emailAddress,
              decoration:const InputDecoration(labelText:'Email Address (optional)')),
            const SizedBox(height:10),
            TextField(controller:address,decoration:const InputDecoration(labelText:'Address (optional)')),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(value:currency,
              decoration:const InputDecoration(labelText:'Account Currency'),
              items:const [
                DropdownMenuItem(value:'PKR',child:Text('PKR')),
                DropdownMenuItem(value:'AED',child:Text('AED')),
                DropdownMenuItem(value:'USDT',child:Text('USDT')),
              ],onChanged:(v){if(v!=null)change(()=>currency=v);}),
          ])),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,{
              'full_name':name.text.trim(),'phone':phone.text.trim(),
              'email':email.text.trim(),'address':address.text.trim(),'currency':currency,
            }),child:const Text('Save Customer')),
          ],
        ),
      ));
      if(data==null)return;
      if((data['full_name']??'').length<2){alert('Full name is required.');return;}
      if((data['email']??'').isNotEmpty && !(data['email']??'').contains('@')){
        alert('Invalid customer email.');return;
      }
      await perform(()async{await widget.request('POST',
        current==null?'/v1/clients':'/v1/clients/profile',{
        ...data,if(current!=null)'client_id':current['id'],
      });});
    }finally{name.dispose();phone.dispose();email.dispose();address.dispose();}
  }
  Future<String?> choose(String title,List<String> values) async =>
    showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:Text(title),children:values.map((v)=>
      SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,v),child:Padding(
        padding:const EdgeInsets.symmetric(vertical:10),child:Text(v)))).toList()));
  Future<void> linkClient(Map<String,dynamic> client) async {
    final email=await textPrompt('Link verified login to ${client['full_name']}','Customer email');
    if(email==null || !email.contains('@'))return;
    await perform(()async{await widget.request('POST','/v1/clients/link',{
      'client_id':client['id'],'email':email,
    });});
  }
  Future<void> holdClient(Map<String,dynamic> client) async {
    final next=client['status']=='active'?'hold':'active';
    await perform(()async{await widget.request('POST','/v1/clients/hold',{
      'client_id':client['id'],'status':next,
    });});
  }
  Future<void> postEntry() async {
    final c=selected;
    if(c==null)return;
    final kind=await choose('Manual Record',[
      'capital_in','capital_out','profit','loss','fee','bonus','referral']);
    if(kind==null)return;
    final amount=await textPrompt('Amount / رقم','Amount in ${c['currency']}');
    if(amount==null)return;
    final note=await textPrompt('Private admin note','Optional description',initial:'Manual record');
    if(note==null)return;
    try {
      var minor=moneyValue(amount,'${c['currency']}');
      if(['capital_out','loss','fee'].contains(kind))minor=-minor;
      final key='UI_${DateTime.now().microsecondsSinceEpoch}_${minor.abs()}';
      await perform(()async{await widget.request('POST','/v1/clients/ledger',{
        'client_id':c['id'],'kind':kind,'amount_minor':minor,'note':note,'request_id':key,
      });});
    }catch(e){alert('$e');}
  }
  Future<void> newRequest() async {
    if(clients.isEmpty){alert('No linked customer accounts');return;}
    final cid=await choose('Customer account',clients.map((c)=>'${c['id']}').toList());
    if(cid==null)return;
    final client=clients.firstWhere((e)=>e['id']==cid);
    final kind=await choose('Request Type',['deposit','withdrawal','exit','question']);
    if(kind==null)return;
    final text=await textPrompt('Request amount','Amount in ${client['currency']}',initial:'0');
    if(text==null)return;
    final note=await textPrompt('Request details','Message',initial:'Please review this request');
    if(note==null)return;
    try {
      final minor=moneyValue(text,'${client['currency']}',allowZero:true);
      await perform(()async{await widget.request('POST','/v1/clients/requests',{
        'client_id':cid,'kind':kind,'amount_minor':minor,'note':note,
      });});
    }catch(e){alert('$e');}
  }
  Future<void> reviewRequest(Map<String,dynamic> request) async {
    final status=await choose('Change request status',['under_review','completed','rejected']);
    if(status==null)return;
    await perform(()async{await widget.request('POST','/v1/clients/requests/review',{
      'request_id':request['request_id'],'status':status,
    });});
  }
  Future<void> newPlan() async {
    final title=await textPrompt('New Investment Plan','Title');if(title==null)return;
    final currency=await choose('Currency',['PKR','AED','USDT']);if(currency==null)return;
    final amount=await textPrompt('Minimum Investment','Minimum in $currency',initial:'1000');
    if(amount==null)return;
    final duration=await textPrompt('Duration','Days',initial:'30');if(duration==null)return;
    try {
      final min=moneyValue(amount,currency,allowZero:true);
      final days=int.parse(duration);
      await perform(()async{await widget.request('POST','/v1/plans',{
        'title':title,'currency':currency,'min_amount_minor':min,'duration_days':days,
      });});
    }catch(e){alert('$e');}
  }
  Future<void> managePlan(Map<String,dynamic> p) async {
    final enabled=await choose('Plan Status',['Enabled','Disabled']);
    if(enabled==null)return;
    final title=await textPrompt('Plan Title','Title',initial:'${p['title']}');
    if(title==null)return;
    final amount=await textPrompt('Minimum Investment','Amount in ${p['currency']}',
      initial:showMoney(p['min_amount_minor'],'${p['currency']}').split(' ').first);
    if(amount==null)return;
    final duration=await textPrompt('Plan Duration','Days',initial:'${p['duration_days']}');
    if(duration==null)return;
    try {
      await perform(()async{await widget.request('POST','/v1/plans/manage',{
        'plan_id':p['plan_id'],'title':title,'min_amount_minor':moneyValue(amount,'${p['currency']}',allowZero:true),
        'duration_days':int.parse(duration),'enabled':enabled=='Enabled',
      });});
    }catch(e){alert('$e');}
  }
  Future<void> newInvestment() async {
    if(clients.isEmpty||plans.isEmpty){alert('Create customer and plan first');return;}
    final cid=await choose('Customer',clients.map((c)=>'${c['id']}').toList());
    if(cid==null)return;
    final c=clients.firstWhere((e)=>e['id']==cid);
    final matching=plans.where((p)=>p['currency']==c['currency'] && p['enabled']==1).toList();
    if(matching.isEmpty){alert('No matching plan');return;}
    final planId=await choose('Plan',matching.map((x)=>'${x['plan_id']}').toList());
    if(planId==null)return;
    final amount=await textPrompt('Investment Principal','Amount in ${c['currency']}');
    if(amount==null)return;
    try {
      final minor=moneyValue(amount,'${c['currency']}');
      await perform(()async{await widget.request('POST','/v1/investments',{
        'client_id':cid,'plan_id':planId,'principal_minor':minor,
      });});
    }catch(e){alert('$e');}
  }
  Future<void> closeInvestment(Map<String,dynamic> entry) async {
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Close investment record?'),
      content:const Text('This closes the record only. No funds move automatically.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Close'))]));
    if(accepted!=true)return;
    await perform(()async{await widget.request('POST','/v1/investments/close',{'id':entry['id']});});
  }
  Future<void> newPeriod() async {
    final currency=await choose('Profit currency',['PKR','AED']);if(currency==null)return;
    final amount=await textPrompt('Realized trading net P/L (signed)','e.g. 2500.00 or -100.00');
    if(amount==null)return;
    final note=await textPrompt('Period reference','Optional notes',initial:'Manual realized P/L record');
    if(note==null)return;
    try{
      final net=moneyValue(amount,currency,signed:true,allowZero:true);
      await perform(()async{await widget.request('POST','/v1/pnl',{
        'currency':currency,'realized_net_minor':net,'note':note,
      });});
    }catch(e){alert('$e');}
  }
  Future<void> allocatePeriod(Map<String,dynamic> period) async {
    final candidates=clients.where((c)=>c['currency']==period['currency']&&c['status']=='active').toList();
    if(candidates.isEmpty){alert('No active customers in this currency');return;}
    final cid=await choose('Client for profit credit',candidates.map((e)=>'${e['id']}').toList());
    if(cid==null)return;
    final input=await textPrompt('Profit credit','Amount in ${period['currency']}');
    if(input==null)return;
    try{
      final amount=moneyValue(input,'${period['currency']}');
      await perform(()async{await widget.request('POST','/v1/pnl/allocate',{
        'client_id':cid,'period_id':period['period_id'],'amount_minor':amount,
      });});
    }catch(e){alert('$e');}
  }
  Future<void> autoDistribute(Map<String,dynamic> period) async {
    final agreed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Distribute verified customer profit?'),
      content:const Text('The customer pool will be credited proportionately to current active investments. This updates the internal ledger only and does not transfer money.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Distribute'))]));
    if(agreed!=true)return;
    await perform(()async{
      await widget.request('POST','/v1/pnl/distribute',{'period_id':period['period_id']});
    });
  }
  Future<void> copyCustomerBackup() async {
    final agreed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Copy private customer backup?'),
      content:const Text('This copies account records to the phone clipboard. Keep the exported JSON private. Very large histories may be truncated.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Copy'))]));
    if(agreed!=true)return;
    try {
      final payload=await widget.request('GET','/v1/clients/export');
      await Clipboard.setData(ClipboardData(text:const JsonEncoder.withIndent('  ').convert(payload)));
      alert(payload['truncated']==true?'Partial backup copied: export limit reached':'Private JSON backup copied');
    } catch(e){alert('$e');}
  }
  Future<void> newTicket() async {
    final title=await textPrompt('Support Ticket','Subject');if(title==null)return;
    final details=await textPrompt('Describe your issue','Message');if(details==null)return;
    await perform(()async{await widget.request('POST','/v1/support',{'subject':title,'message':details});});
  }
  Future<void> resolveTicket(Map<String,dynamic> ticket) async {
    await perform(()async{await widget.request('POST','/v1/support/resolve',{'ticket_id':ticket['ticket_id']});});
  }
  Widget intro(String text)=>Padding(padding:const EdgeInsets.fromLTRB(2,12,2,6),
    child:Text(text,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:deepGreen)));
  Widget tip(String text)=>Card(child:Padding(padding:const EdgeInsets.all(13),child:Text(text)));
  List<Widget> customersView()=>[
    intro(widget.owner?'Customer Accounts / کسٹمر اکاؤنٹس':'My Private Account / میرا اکاؤنٹ'),
    if(widget.owner)FilledButton.icon(onPressed:busy?null:newClient,
      icon:const Icon(Icons.person_add_alt),label:const Text('Add Customer / نیا کسٹمر')),
    if(widget.owner)OutlinedButton.icon(onPressed:busy?null:copyCustomerBackup,
      icon:const Icon(Icons.copy_all_outlined),label:const Text('Copy Private JSON Backup')),
    tip(widget.owner
      ? 'Each customer has a separate account and statement. Customers cannot see your internal trading costs or private accounting.'
      : 'You can see only accounts that Super Admin explicitly linked to your login.'),
    if(widget.owner)TextField(
      decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Search Customer / Name / Code / Phone / Email'),
      onChanged:(v)=>setState(()=>customerSearch=v.trim().toLowerCase())),
    ...clients.where((c)=>!widget.owner || customerSearch.isEmpty ||
      ['full_name','customer_code','phone','email'].any((k)=>'${c[k] ?? ''}'.toLowerCase().contains(customerSearch)))
      .map((c)=>Card(child:Column(children:[
      ListTile(leading:const Icon(Icons.account_circle_outlined,color:deepGreen),
        title:Text('${c['full_name']}'),
        subtitle:Text('${c['customer_code'] ?? 'Customer'} • ${c['status']} • ${c['currency']}\n${c['phone'] ?? ''} ${c['email'] ?? ''}'),
        trailing:const Icon(Icons.chevron_right),
        onTap:()=>loadLedger('${c['id']}')),
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,10),child:Align(
        alignment:Alignment.centerLeft,child:Text('Recorded Balance: ${showMoney(c['balance_minor'],'${c['currency']}')}',
          style:const TextStyle(fontWeight:FontWeight.bold)))),
      if(widget.owner)Wrap(spacing:8,children:[
        TextButton(onPressed:busy?null:()=>customerForm(c),child:const Text('Edit Profile')),
        TextButton(onPressed:busy?null:()=>linkClient(c),child:const Text('Link Login')),
        TextButton(onPressed:busy?null:()=>holdClient(c),child:Text(c['status']=='hold'?'Activate':'Hold')),
      ]),
    ]))),
    if(clients.isEmpty)tip(widget.owner?'Add your first customer.':'No account linked yet.'),
  ];
  List<Widget> ledgerView()=>[
    intro('Customer Statement / اکاؤنٹ اسٹیٹمنٹ'),
    if(selected==null)tip('Tap any customer on Accounts tab to open its statement.'),
    if(selected!=null)...[
      Card(color:paleGreen,child:ListTile(title:Text('${selected!['full_name']}'),
        subtitle:Text('${selected!['status']}'),
        trailing:Text(showMoney(selected!['balance_minor'],'${selected!['currency']}')))),
      if(widget.owner)FilledButton.icon(onPressed:busy?null:postEntry,icon:const Icon(Icons.add),
        label:const Text('Add Manual Ledger Entry')),
      OutlinedButton.icon(onPressed:()=>v11ShareCustomerStatementPdf(selected!,entries),
        icon:const Icon(Icons.picture_as_pdf),label:const Text('Share PDF Statement')),
      ...entries.map((e)=>Card(child:ListTile(
        title:Text('${e['kind']}'),subtitle:Text('${e['created_at']} ${e['note']??''}'),
        trailing:Text(showMoney(e['amount_minor'],'${selected!['currency']}'))))),
      if(entries.isEmpty)tip('No ledger entries yet.'),
    ],
    tip('All entries are manual financial records. No bank, wallet or blockchain transfers occur here.'),
  ];
  List<Widget> plansView()=>[
    intro('Investment Plans / سرمایہ کاری پلان'),
    if(widget.owner)FilledButton.icon(onPressed:busy?null:newPlan,
      icon:const Icon(Icons.add),label:const Text('Create Plan')),
    ...plans.map((p)=>Card(child:ListTile(
      title:Text('${p['title']}'),
      subtitle:Text('Min ${showMoney(p['min_amount_minor'],'${p['currency']}')} • ${p['duration_days']} days • ${p['enabled']==1?'Active':'Disabled'}'),
      trailing:widget.owner?IconButton(icon:const Icon(Icons.edit),
        onPressed:busy?null:()=>managePlan(p)):null))),
    intro('Investment Records / سرمایہ کاری ریکارڈ'),
    if(widget.owner)FilledButton.icon(onPressed:busy?null:newInvestment,
      icon:const Icon(Icons.add_chart),label:const Text('Assign Investment')),
    ...investments.map((i)=>Card(child:ListTile(
      title:Text('${i['full_name']} — ${i['title']}'),
      subtitle:Text('${i['status']} • ${i['started_at']}'),
      trailing:widget.owner && i['status']=='active'
        ?IconButton(icon:const Icon(Icons.check_circle_outline),tooltip:'Close record',
           onPressed:busy?null:()=>closeInvestment(i))
        :Text(showMoney(i['principal_minor'],'${i['currency']}'))))),
    if(investments.isEmpty)tip('No investment records yet.'),
    tip('No guaranteed return is shown. The owner records actual realized profit/loss separately.'),
  ];
  List<Widget> requestsView()=>[
    intro('Deposit, Withdrawal & Exit Requests / درخواستیں'),
    FilledButton.icon(onPressed:busy?null:newRequest,icon:const Icon(Icons.edit_note),
      label:const Text('New Request / درخواست بھیجیں')),
    ...requests.map((r)=>Card(child:ListTile(
      title:Text('${r['full_name']} • ${r['kind']}'),
      subtitle:Text('${r['status']} • ${r['created_at']}\n${r['note']??''}'),
      trailing:widget.owner && ['submitted','under_review'].contains(r['status'])
       ?IconButton(icon:const Icon(Icons.more_vert),onPressed:busy?null:()=>reviewRequest(r))
       :Text(showMoney(r['amount_minor'],'${r['currency']}'))))),
    tip('These are requests only. Marking completed does not send or receive money.'),
  ];
  List<Widget> pnlView()=>[
    intro('Verified Realized P/L Journal / نفع و نقصان'),
    FilledButton.icon(onPressed:busy?null:newPeriod,icon:const Icon(Icons.add_chart),
      label:const Text('Record Period Result')),
    tip('Allocation formula: 50% customer pool, 30% owner pool, 20% reserve/referrals. Earlier losses carry forward before profit is shared.'),
    ...periods.map((p)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${p['created_at']} • ${p['currency']}',style:const TextStyle(fontWeight:FontWeight.bold)),
        Text('Realized Net: ${showMoney(p['realized_net_minor'],'${p['currency']}')}'),
        Text('Unrecovered Loss: ${showMoney(p['unrecovered_loss_minor'],'${p['currency']}')}'),
        Text('Users 50%: ${showMoney(p['users_share_minor'],'${p['currency']}')}'),
        Text('Owner 30%: ${showMoney(p['owner_share_minor'],'${p['currency']}')}'),
        Text('Reserve 20%: ${showMoney(p['reserve_share_minor'],'${p['currency']}')}'),
        Text('Already credited: ${showMoney(p['allocated_minor'],'${p['currency']}')}'),
        if((p['users_share_minor'] as num).toInt()>0 && (p['allocated_minor'] as num).toInt()==0)
          FilledButton.icon(onPressed:busy?null:()=>autoDistribute(p),
            icon:const Icon(Icons.groups_2_outlined),
            label:const Text('Distribute 50% Pool to All Active Clients')),
        if((p['users_share_minor'] as num).toInt()>0)
          TextButton(onPressed:busy?null:()=>allocatePeriod(p),
            child:const Text('Allocate to One Client')),
      ])))),
    if(periods.isEmpty)tip('Record your first realized trading result.'),
  ];
  List<Widget> supportView()=>[
    intro('Support & Messages / مدد'),
    FilledButton.icon(onPressed:busy?null:newTicket,
      icon:const Icon(Icons.support_agent),label:const Text('Open Support Ticket')),
    ...tickets.map((t)=>Card(child:ListTile(
      title:Text('${t['subject']}'),
      subtitle:Text('${t['status']} • ${t['created_at']}\n${t['message']}'),
      trailing:widget.owner && t['status']=='open' ? IconButton(
        icon:const Icon(Icons.done),tooltip:'Resolve ticket',
        onPressed:busy?null:()=>resolveTicket(t)) : null))),
    if(tickets.isEmpty)tip('No support messages yet.'),
  ];
  @override
  Widget build(BuildContext context) {
    final tabs=widget.owner
      ?const ['Customers','Statements','Plans','Requests','Profit','Support']
      :const ['My Account','Statement','Plans','Requests','Support'];
    final contents=widget.owner
      ?<List<Widget>>[customersView(),ledgerView(),plansView(),requestsView(),pnlView(),supportView()]
      :<List<Widget>>[customersView(),ledgerView(),plansView(),requestsView(),supportView()];
    return DefaultTabController(length:tabs.length,child:Scaffold(
      appBar:AppBar(title:Text(widget.owner?'Customer Management / کسٹمر اکاؤنٹس'
        :'My Customer Dashboard / میرا اکاؤنٹ'),
        actions:[IconButton(onPressed:loading?null:refresh,icon:const Icon(Icons.refresh))],
        bottom:TabBar(isScrollable:true,tabAlignment:TabAlignment.start,
          tabs:tabs.map((t)=>Tab(text:t)).toList())),
      body:Column(children:[
        if(loading||busy)const LinearProgressIndicator(minHeight:3),
        if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,
          style:const TextStyle(color:Colors.red))),
        Expanded(child:TabBarView(children:contents.map((children)=>RefreshIndicator(
          onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(14),children:children))).toList())),
      ]),
    ));
  }
}
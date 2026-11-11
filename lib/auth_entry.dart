import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// Only the authenticated Cloudflare backend grants admin access.
typedef ApiRequest = Future<Map<String, dynamic>> Function(
    String method, String path, [Map<String, dynamic>? body]);

// Sarmaya Plus — Account Dashboard v5: notifications, search, reports and reviewer roles
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
  bool savingProfile = false;
  bool hideEmail = false;
  bool kycSubmitting = false;
  bool kycAcknowledged = false;
  String? adminRole;
  int unreadNotifications = 0;
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
            'Sarmaya Plus • Account Dashboard v5\n'
            'Login: Firebase Authentication\n'
            'Account profile: Cloudflare API + D1\n'
            'KYC checklist and email-hide setting: stored on this device only\n\n'
            'KYC review requests store only the requesting account ID and status in Cloudflare. Identity document uploads and financial services remain disabled.',
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

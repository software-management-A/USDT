import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'main.dart' as existingDemo;

const Color forest = Color(0xFF123F2B);
const Color gold = Color(0xFFD4AF37);
const Color paper = Color(0xFFF5F7F3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await existingDemo.data.init();
  runApp(const SarmayaFirebaseApp());
}

class SarmayaFirebaseApp extends StatelessWidget {
  const SarmayaFirebaseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sarmaya Plus — Firebase Demo',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: paper,
          colorScheme: ColorScheme.fromSeed(seedColor: forest),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: forest,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _userStream;

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseAuth.instance.userChanges();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: _userStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text('Firebase error: ${snapshot.error}')),
            );
          }
          final user = snapshot.data;
          if (user == null) return const EmailLoginPage();
          if (!user.emailVerified) return VerifyEmailPage(user: user);
          return DemoEntryPage(user: user);
        },
      );
}

String friendlyError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email already has an account.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try later.';
      case 'network-request-failed':
        return 'Check your internet connection.';
      default:
        return error.message ?? error.code;
    }
  }
  return error.toString();
}

class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key});
  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool createAccount = false;
  bool busy = false;
  bool showPassword = false;
  bool termsChecked = false;
  bool riskChecked = false;
  String? message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@') || password.length < 6) {
      setState(() => message = 'Use a valid email and password (6+ characters).');
      return;
    }
    if (createAccount && _confirm.text != password) {
      setState(() => message = 'Passwords do not match.');
      return;
    }
    if (createAccount && (!termsChecked || !riskChecked)) {
      setState(() => message = 'Accept both demo terms and risk notices.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      if (createAccount) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await credential.user?.sendEmailVerification();
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
      }
    } catch (error) {
      if (mounted) setState(() => message = friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => message = 'Enter your email first.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => message = 'If this account exists, check its email.');
      }
    } catch (error) {
      if (mounted) setState(() => message = friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('سرمایہ پلس · Sarmaya Plus'),
          backgroundColor: paper,
          actions: [
            TextButton(
              onPressed: () => setState(() => existingDemo.data
                  .setLanguage(!existingDemo.data.urdu)),
              child: const Text('اردو / English'),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.verified_user_outlined,
                      color: forest, size: 65),
                  const SizedBox(height: 12),
                  Text(
                    createAccount ? 'Create test account / رجسٹریشن' : 'Email Login / لاگ اِن',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: forest, fontWeight: FontWeight.bold, fontSize: 23),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: !showPassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => showPassword = !showPassword),
                        icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                  ),
                  if (createAccount) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Confirm password', border: OutlineInputBorder()),
                    ),
                    CheckboxListTile(
                      value: termsChecked,
                      onChanged: (v) => setState(() => termsChecked = v ?? false),
                      title: const Text('I accept the demo terms / شرائط قبول ہیں'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: riskChecked,
                      onChanged: (v) => setState(() => riskChecked = v ?? false),
                      title: const Text('I understand trading losses and no guaranteed returns / خطرہ تسلیم ہے'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(message!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Please wait...' :
                        createAccount ? 'Register & Verify Email' : 'Login'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            createAccount = !createAccount;
                            message = null;
                          }),
                    child: Text(createAccount
                        ? 'Already registered? Login'
                        : 'New user? Create test account'),
                  ),
                  if (!createAccount)
                    TextButton(
                      onPressed: busy ? null : resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                  const SizedBox(height: 18),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(15),
                      child: Text(
                        'DEMO ONLY. Firebase verifies email identities; KYC, admin roles, '
                        'server token validation and multi-user ledger isolation are NOT implemented. '
                        'No real deposits, withdrawals or investments.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
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
  String? message;
  bool busy = false;

  Future<void> check() async {
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final u = FirebaseAuth.instance.currentUser;
      if (mounted && u?.emailVerified != true) {
        setState(() => message = 'Email is not verified yet. Open the verification link first.');
      }
    } catch (error) {
      if (mounted) setState(() => message = friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() => message = 'Email sent. Check inbox and spam.');
    } catch (error) {
      if (mounted) setState(() => message = friendlyError(error));
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
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.mark_email_unread_outlined,
                      size: 65, color: forest),
                  const SizedBox(height: 12),
                  Text('Verification link sent to ${widget.user.email ?? 'your email'}.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: busy ? null : check,
                    child: const Text('I verified my email — Check Again'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : resend,
                    child: const Text('Resend verification email'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                  if (message != null)
                    Text(message!, style: const TextStyle(color: Colors.deepOrange)),
                  const SizedBox(height: 16),
                  const Text('Do not share your password or verification links.'),
                ],
              ),
            ),
          ),
        ),
      );
}

class DemoEntryPage extends StatelessWidget {
  const DemoEntryPage({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sarmaya Plus — Email Verified'),
          backgroundColor: paper,
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.verified, color: forest, size: 66),
                  const SizedBox(height: 12),
                  const Text('Firebase Login Successful',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 23)),
                  const SizedBox(height: 12),
                  Text(user.email ?? '', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const existingDemo.SarmayaApp(),
                      ),
                    ),
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Open Local Demo App'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                  ),
                  const SizedBox(height: 18),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(15),
                      child: Text(
                        'Your email is verified, but DEMO Admin access is NOT role restricted. '
                        'The original wallet and trading screens still share LOCAL sample data '
                        'on this device (not isolated by email). Never enter real money or personal documents. '
                        'Use the Android Back button to return from the demo.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

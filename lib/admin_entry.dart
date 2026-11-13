// Sarmaya Plus — dedicated Admin & Staff Android entry point.
// This APK uses a separate Android package and Firebase app registration.
// It reuses existing admin modules, and NEVER renders the customer home screen.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_entry.dart' show
    AdminConsolePage,
    PersonalLedgerPage,
    UnifiedCustomerPage,
    UnifiedModePage,
    VerifyEmailPage,
    apiBase,
    deepGreen,
    paleGreen,
    readableAuthError;
import 'firebase_options.dart';
import 'remittance_v10.dart' show TransferAdminPage;
import 'v11_features.dart' show
    V11AccountsPage,
    V11AdminToolsPage,
    V11PlansPage,
    V11ReportsPage,
    V11TradingPage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SarmayaAdminApp());
}

class SarmayaAdminApp extends StatelessWidget {
  const SarmayaAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sarmaya Plus Admin',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: deepGreen),
          scaffoldBackgroundColor: const Color(0xFFF5F7F3),
          appBarTheme: const AppBarTheme(
            foregroundColor: deepGreen,
            backgroundColor: Color(0xFFF5F7F3),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: deepGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
            ),
          ),
        ),
        home: const AdminAuthGate(),
      );
}

class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});

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
                body: Center(child: Text('Login error: ${snapshot.error}')));
          }
          final user = snapshot.data;
          if (user == null) return const AdminLoginPage();
          if (!user.emailVerified) return VerifyEmailPage(user: user);
          return AdminDashboard(key: ValueKey(user.uid), user: user);
        },
      );
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool showPassword = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (busy) return;
    if (!email.text.contains('@') || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(), password: password.text,
      );
    } catch (e) {
      if (mounted) setState(() => error = readableAuthError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!email.text.contains('@')) {
      setState(() => error = 'Enter your email first.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.text.trim(),
      );
      if (mounted) setState(() => error = 'If registered, check your email.');
    } catch (e) {
      if (mounted) setState(() => error = readableAuthError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sarmaya Plus Admin')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(22),
              children: [
                const Icon(Icons.admin_panel_settings_outlined,
                    size: 74, color: deepGreen),
                const SizedBox(height: 12),
                const Text('Admin & Staff Login / انتظامی لاگ اِن',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21)),
                const SizedBox(height: 22),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: !showPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => showPassword = !showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (error != null) Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
                FilledButton(
                  onPressed: busy ? null : _login,
                  child: Text(busy ? 'Signing in...' : 'Sign In'),
                ),
                TextButton(onPressed: busy ? null : _resetPassword,
                    child: const Text('Forgot password?')),
                const Text('Only server-authorized Admin and Staff accounts may enter. '
                    'No public admin signup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.user});
  final User user;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool loading = true;
  bool isSuperAdmin = false;
  bool isRemittanceStaff = false;
  String adminRole = '';
  String staffRole = '';
  String platformMode = 'PERSONAL';
  String? syncError;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await widget.user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Session expired. Please sign in again.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client
          .openUrl(method, Uri.parse('$apiBase$path'))
          .timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final info = await PackageInfo.fromPlatform();
      req.headers.set('X-Sarmaya-Build', info.buildNumber);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final response = await req.close().timeout(const Duration(seconds: 15));
      final raw = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected server response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('${data['error'] ?? 'HTTP ${response.statusCode}'}');
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      syncError = null;
      // Fail closed while rechecking server-side roles.
      isSuperAdmin = false;
      isRemittanceStaff = false;
      adminRole = '';
      staffRole = '';
    });
    try {
      final platform = await _request('GET', '/v1/platform/status');
      final superAdmin = platform['is_super_admin'] == true;
      final mode = platform['mode']?.toString() ?? 'PERSONAL';
      var nextAdminRole = '';
      var nextStaffRole = '';
      var nextStaff = false;
      try {
        final access = await _request('GET', '/v1/admin/overview');
        final role = access['role']?.toString() ?? '';
        if (role == 'admin' || role == 'reviewer') nextAdminRole = role;
      } catch (_) {
        // Accounts without KYC-console authorization must not see it.
      }
      try {
        final access = await _request('GET', '/v1/remit/access');
        nextStaff = access['staff'] == true;
        nextStaffRole = nextStaff ? (access['role']?.toString() ?? '') : '';
      } catch (_) {
        // No remittance permission unless server explicitly grants it.
      }
      if (!mounted) return;
      setState(() {
        isSuperAdmin = superAdmin;
        platformMode = mode;
        adminRole = nextAdminRole;
        isRemittanceStaff = nextStaff;
        staffRole = nextStaffRole;
      });
    } catch (e) {
      if (mounted) setState(() => syncError = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context,
        MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _refresh();
  }

  void _openKyc() => _open(AdminConsolePage(request: _request));
  void _openInvestors() => _open(UnifiedCustomerPage(
      request: _request, owner: isSuperAdmin, mode: platformMode));
  void _openPersonal() => _open(PersonalLedgerPage(
      request: _request, ownerName: widget.user.displayName ?? 'Owner'));
  void _openMode() => _open(UnifiedModePage(request: _request));

  void _openRemittance() => _open(TransferAdminPage(
        request: _request,
        owner: isSuperAdmin,
        openInvestors: isSuperAdmin ? _openInvestors : null,
        openPersonal: isSuperAdmin ? _openPersonal : null,
        openMode: isSuperAdmin ? _openMode : null,
        openKyc: adminRole.isNotEmpty ? _openKyc : null,
      ));

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(3, 18, 0, 8),
        child: Text(title, style: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.bold, color: deepGreen)),
      );

  Widget _tile(String title, String subtitle, IconData icon, VoidCallback action) =>
      Card(child: ListTile(
        leading: Icon(icon, color: deepGreen),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: action,
      ));

  @override
  Widget build(BuildContext context) {
    final allowed = isSuperAdmin || isRemittanceStaff || adminRole.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sarmaya Plus Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: loading ? null : _refresh,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : syncError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text('Could not verify access: $syncError', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _refresh, child: const Text('Retry')),
                  ]),
                ))
              : !allowed
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.lock_outline, size: 55),
                        const SizedBox(height: 12),
                        const Text('Admin/Staff access not enabled for this account.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Sign Out'),
                        ),
                      ]),
                    ))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(padding: const EdgeInsets.all(15), children: [
                        Card(color: paleGreen,
                            child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Admin & Staff Workspace',
                                  style: TextStyle(fontSize: 21,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 7),
                              Text('Signed in: ${widget.user.email ?? ''}'),
                              Text(isSuperAdmin
                                  ? 'Super Admin • $platformMode'
                                  : isRemittanceStaff
                                      ? 'Staff • $staffRole'
                                      : 'KYC • $adminRole'),
                            ],
                          ),
                        )),
                        if (isSuperAdmin || isRemittanceStaff) ...[
                          _section('Daily Operations / روزمرہ کام'),
                          _tile('Transfers, Orders & Staff',
                            'Rates • orders • approvals • trading records',
                            Icons.receipt_long_outlined, _openRemittance),
                        ],
                        if (adminRole.isNotEmpty) ...[
                          _section('Identity & Customers / شناخت'),
                          _tile('KYC Reviews & Users',
                            'Requests • users • reviewer roles • audit',
                            Icons.verified_user_outlined, _openKyc),
                        ],
                        if (isSuperAdmin) ...[
                          _section('Investment & Finance / سرمایہ کاری'),
                          _tile('Customers, Investments & Profit',
                            'Client records • plans • 50/30/20 allocations',
                            Icons.groups_outlined, _openInvestors),
                          _tile('Investment Plans & Funding',
                            'Plan terms and funding records',
                            Icons.trending_up_outlined,
                            () => _open(V11PlansPage(request: _request, owner: true))),
                          _tile('Verified Profit & Loss Reports',
                            'Trading reports and PDF export',
                            Icons.bar_chart_outlined,
                            () => _open(V11ReportsPage(request: _request))),
                          _tile('Bank & Binance Accounts',
                            'Accounts used for manual trading records',
                            Icons.account_balance_outlined,
                            () => _open(V11AccountsPage(request: _request))),
                          _tile('USDT Trading — Multi-Lot',
                            'Manual buy/sell records and inventory',
                            Icons.currency_exchange_outlined,
                            () => _open(V11TradingPage(request: _request))),
                          _section('System & Security / انتظامات'),
                          _tile('Backup, Staff Approvals & Audit',
                            'Backup • policy • audit • advanced tools',
                            Icons.backup_outlined,
                            () => _open(V11AdminToolsPage(request: _request))),
                          _tile('Access Mode',
                            'Personal / Multi-User Mode',
                            Icons.toggle_on_outlined, _openMode),
                          _tile('Private Owner Ledger',
                            'Owner-only financial records',
                            Icons.account_balance_wallet_outlined, _openPersonal),
                        ],
                        const SizedBox(height: 14),
                        const Text('All permissions are checked by the shared backend. '
                            'Transactions in this version are recordkeeping only.',
                            style: TextStyle(color: Colors.black54, fontSize: 12)),
                      ]),
                    ),
    );
  }
}

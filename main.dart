import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';

final data = SarmayaStore();
const green = Color(0xFF123F2B);
const gold = Color(0xFFD4AF37);
const canvas = Color(0xFFF5F7F3);
String t(String urdu,String english) => data.urdu ? urdu : english;
String money(num n) => 'Rs. ${n.toStringAsFixed(2)}';
void snack(BuildContext ctx, String? message, [bool error=false]) {
  if(message==null) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(message),
    backgroundColor:error?Colors.red.shade800:green));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await data.init();
  runApp(const SarmayaApp());
}

class SarmayaApp extends StatefulWidget {
  const SarmayaApp({super.key});
  @override State<SarmayaApp> createState()=>_SarmayaAppState();
}
class _SarmayaAppState extends State<SarmayaApp> {
  bool entered=false;
  bool admin=false;
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:data,builder:(context,_)=>
    MaterialApp(
      debugShowCheckedModeBanner:false,
      title:'Sarmaya Plus • Demo',
      theme:ThemeData(
        useMaterial3:true,
        colorScheme:ColorScheme.fromSeed(seedColor:green,primary:green,secondary:gold),
        scaffoldBackgroundColor:canvas,
        appBarTheme:const AppBarTheme(backgroundColor:canvas,foregroundColor:green,centerTitle:false),
        filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(
          backgroundColor:green,foregroundColor:Colors.white,
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(13)),
          padding:const EdgeInsets.symmetric(vertical:13,horizontal:18))),
        cardTheme:CardThemeData(color:Colors.white,margin:EdgeInsets.zero,
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(17))),
      ),
      home:Directionality(textDirection:data.urdu?TextDirection.rtl:TextDirection.ltr,
        child:entered ? (admin ? AdminShell(onLogout:()=>setState(()=>entered=false)) :
          InvestorShell(onLogout:()=>setState(()=>entered=false))) :
          WelcomeScreen(onEnter:(asAdmin)=>setState(() {admin=asAdmin;entered=true;}))),
    ));
}

class Block extends StatelessWidget {
  const Block({super.key,required this.child,this.padding=const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override Widget build(BuildContext context) => Card(child:Padding(padding:padding,child:child));
}
class TitleLine extends StatelessWidget {
  const TitleLine(this.label,{super.key,this.trailing});
  final String label;final Widget? trailing;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:9),
    child:Row(children:[Expanded(child:Text(label,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:green))),if(trailing!=null)trailing!]));
}
class Stat extends StatelessWidget {
  const Stat({super.key,required this.label,required this.value,this.icon=Icons.account_balance_wallet_outlined});
  final String label,value;final IconData icon;
  @override Widget build(BuildContext context)=>Block(padding:const EdgeInsets.all(13),child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:green,size:22),const SizedBox(height:9),
      Text(label,style:TextStyle(color:Colors.grey.shade700,fontSize:12)),const SizedBox(height:5),
      Text(value,style:const TextStyle(color:green,fontWeight:FontWeight.w900,fontSize:17)),
    ]));
}
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label,{super.key});final String label;
  @override Widget build(BuildContext context) {
    final good=['Approved','Paid','Active','Completed'].contains(label);
    final bad=['Rejected','Disabled','OFF','Unpaid / Part-paid'].contains(label);
    final c=good?Colors.green:(bad?Colors.red:Colors.orange);
    return Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),
      decoration:BoxDecoration(color:c.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),
      child:Text(label,style:TextStyle(color:c.shadeForText(),fontWeight:FontWeight.bold,fontSize:11)));
  }
}
extension StatusColor on Color {
  Color shadeForText() => this==Colors.orange ? const Color(0xFF935C00) :
    this==Colors.green ? const Color(0xFF176B2A) : const Color(0xFFB71C1C);
}
class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});
  @override Widget build(BuildContext context) => Container(
    width:double.infinity,padding:const EdgeInsets.symmetric(vertical:8,horizontal:12),
    color:const Color(0xFFFFF0CD),child:Row(children:[const Icon(Icons.science_outlined,size:16,color:Color(0xFF7C4A00)),
      const SizedBox(width:8),Expanded(child:Text(t('صرف DEMO — حقیقی رقم یا Live Sync نہیں','DEMO ONLY — no real money or live sync'),
      style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:Color(0xFF7C4A00))))]));
}
class ScreenPad extends StatelessWidget {
  const ScreenPad({super.key,required this.child});final Widget child;
  @override Widget build(BuildContext context)=>SafeArea(child:ListView(
    padding:const EdgeInsets.fromLTRB(16,16,16,32),children:[child]));
}
class FormLine extends StatelessWidget {
  const FormLine({super.key,required this.controller,required this.label,this.numeric=false,this.maxLines=1});
  final TextEditingController controller;final String label;final bool numeric;final int maxLines;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(
    controller:controller,maxLines:maxLines,keyboardType:numeric?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,
    decoration:InputDecoration(labelText:label,filled:true,fillColor:Colors.white,
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)))));
}
Future<void> showForm(BuildContext context,String title,List<Widget> fields,Future<void> Function() onSubmit) async {
  await showDialog<void>(context:context,builder:(ctx)=>Directionality(
    textDirection:data.urdu?TextDirection.rtl:TextDirection.ltr,
    child:AlertDialog(title:Text(title),content:SingleChildScrollView(child:SizedBox(width:340,
      child:Column(mainAxisSize:MainAxisSize.min,children:fields))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(t('بند کریں','Cancel'))),
        FilledButton(onPressed:() async {await onSubmit();},child:Text(t('محفوظ کریں','Save')))])));
}
Widget bigButton(String text,VoidCallback action,{IconData icon=Icons.check_circle_outline}) =>
  SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:action,icon:Icon(icon,size:19),label:Text(text)));
void go(BuildContext ctx,Widget page)=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>
  Directionality(textDirection:data.urdu?TextDirection.rtl:TextDirection.ltr,child:page)));

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key,required this.onEnter});
  final ValueChanged<bool> onEnter;
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Padding(
    padding:const EdgeInsets.all(24),child:Column(children:[
      Align(alignment:AlignmentDirectional.centerEnd,child:TextButton.icon(
        onPressed:()=>data.setLanguage(!data.urdu),icon:const Icon(Icons.language),
        label:Text(data.urdu?'English':'اردو'))),
      const Spacer(),Container(width:150,height:150,clipBehavior:Clip.antiAlias,
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(30)),
        child:Image.asset('assets/sarmaya_icon.png',fit:BoxFit.cover)),
      const SizedBox(height:20),const Text('SARMAYA PLUS',style:TextStyle(fontSize:29,
        fontWeight:FontWeight.w900,letterSpacing:1.4,color:green)),
      const Text('سرمایہ پلس',style:TextStyle(fontSize:23,fontWeight:FontWeight.w700,color:green)),
      const SizedBox(height:14),Text(t('دوستوں کے لیے انویسٹمنٹ ریکارڈ اور لائیو حساب کا تصور',
        'Investment records & transparent account tracking'),textAlign:TextAlign.center,
        style:TextStyle(color:Colors.grey.shade700)),
      const SizedBox(height:24),const DemoNotice(),const Spacer(),
      bigButton(t('Investor Demo کھولیں','Open Investor Demo'),()=>onEnter(false),icon:Icons.person_outline),
      const SizedBox(height:12),OutlinedButton.icon(onPressed:()=>onEnter(true),
        icon:const Icon(Icons.admin_panel_settings_outlined),label:Text(t('Admin Demo کھولیں','Open Admin Demo')),
        style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(48))),
      const SizedBox(height:16),Text(t('یہ محفوظ Login نہیں، صرف Preview ہے۔','No secure login in this preview.'),
        style:const TextStyle(fontSize:11,color:Colors.red)),
    ]))));
}

class InvestorShell extends StatefulWidget {
  const InvestorShell({super.key,required this.onLogout});final VoidCallback onLogout;
  @override State<InvestorShell> createState()=>_InvestorShellState();
}
class _InvestorShellState extends State<InvestorShell> {
  int tab=0;
  @override Widget build(BuildContext context) {
    final pages=[const DashboardPage(),const PlansPage(),const WalletPage(),const ReferralPage(),
      MorePage(onLogout:widget.onLogout)];
    return Scaffold(appBar:AppBar(title:Row(children:[Image.asset('assets/sarmaya_icon.png',width:34,height:34),
      const SizedBox(width:9),const Text('Sarmaya Plus',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))]),
      actions:[IconButton(tooltip:'Language',onPressed:()=>data.setLanguage(!data.urdu),icon:const Icon(Icons.language)),
        IconButton(onPressed:()=>go(context,const NotificationsPage()),icon:const Icon(Icons.notifications_none))]),
      body:Column(children:[const DemoNotice(),Expanded(child:pages[tab])]),
      bottomNavigationBar:NavigationBar(height:67,selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),
        destinations:[
          NavigationDestination(icon:const Icon(Icons.dashboard_outlined),selectedIcon:const Icon(Icons.dashboard),label:t('ہوم','Home')),
          NavigationDestination(icon:const Icon(Icons.savings_outlined),selectedIcon:const Icon(Icons.savings),label:t('پلان','Plans')),
          NavigationDestination(icon:const Icon(Icons.account_balance_wallet_outlined),selectedIcon:const Icon(Icons.account_balance_wallet),label:t('والٹ','Wallet')),
          NavigationDestination(icon:const Icon(Icons.people_outline),selectedIcon:const Icon(Icons.people),label:t('ریفرل','Referrals')),
          NavigationDestination(icon:const Icon(Icons.menu),label:t('مزید','More')),
        ]));
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('${t('خوش آمدید','Welcome')}, ${data.name}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:green)),
    const SizedBox(height:12),Container(padding:const EdgeInsets.all(21),
      decoration:BoxDecoration(gradient:const LinearGradient(colors:[green,Color(0xFF176A43)]),
        borderRadius:BorderRadius.circular(21)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(t('Total Wallet Balance','Total Wallet Balance'),style:const TextStyle(color:Color(0xFFE5D9A7))),
        const SizedBox(height:9),Text(money(data.totalWallet),style:const TextStyle(color:Colors.white,fontSize:31,fontWeight:FontWeight.w900)),
        const SizedBox(height:12),Text(t('موجودہ قابلِ استعمال رقم — کم یا زیادہ ہو سکتی ہے','Current available wallet balance'),
          style:const TextStyle(color:Colors.white70,fontSize:12)),
      ])),
    const SizedBox(height:13),Row(children:[Expanded(child:Stat(label:t('Total Deposited • Lifetime','Total Deposited • Lifetime'),
      value:money(data.lifetimeDeposit),icon:Icons.payments_outlined)),const SizedBox(width:10),
      Expanded(child:Stat(label:t('Total Referral Received','Total Referral Received'),
        value:money(data.lifetimeReferral),icon:Icons.group_add_outlined))]),
    const SizedBox(height:10),Row(children:[Expanded(child:Stat(label:t('Active Investment','Active Investment'),
      value:money(data.invested),icon:Icons.show_chart)),const SizedBox(width:10),
      Expanded(child:Stat(label:t('Withdrawable Now','Withdrawable Now'),
        value:money(data.withdrawable),icon:Icons.account_balance_outlined))]),
    const SizedBox(height:10),Row(children:[Expanded(child:Stat(label:t('Total Earnings Received','Total Earnings Received'),
      value:money(data.lifetimeEarnings),icon:Icons.trending_up)),const SizedBox(width:10),
      Expanded(child:Stat(label:t('Total Withdrawn','Total Withdrawn'),
        value:money(data.lifetimeWithdrawn),icon:Icons.receipt_long_outlined))]),
    const SizedBox(height:10),Block(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(t('والٹ کی تفصیل','Wallet detail'),style:const TextStyle(fontWeight:FontWeight.bold,color:green)),
      const SizedBox(height:8),valueRow(t('Cash / Deposit available','Cash / Deposit available'),money(data.cashWallet)),
      valueRow(t('Referral spendable (not directly withdrawable)','Referral spendable (not directly withdrawable)'),money(data.referralWallet)),
      valueRow(t('Earnings available','Earnings available'),money(data.earningsWallet)),
      valueRow(t('Earnings waiting till next day','Earnings waiting till next day'),money(data.earningsWaiting)),
    ])),
    const TitleLine('Recent Activity'),
    ...data.activity.take(5).map((x)=>activityTile(x)),
    const SizedBox(height:14),Text(t('منافع کی ضمانت نہیں؛ یہ مثال حقیقی سرمایہ کاری نہیں۔',
      'No guaranteed returns. This is demo data.'),style:const TextStyle(fontSize:12,color:Colors.black54)),
  ]));
}
Widget valueRow(String label,String val)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[
  Expanded(child:Text(label,style:const TextStyle(fontSize:12))),Text(val,style:const TextStyle(fontWeight:FontWeight.w800,color:green))]));
Widget activityTile(Map<String,dynamic> x)=>Padding(padding:const EdgeInsets.only(bottom:6),child:Block(
  padding:const EdgeInsets.all(12),child:Row(children:[const Icon(Icons.history,color:green),
    const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[Text(x['type'].toString(),style:const TextStyle(fontWeight:FontWeight.w700)),
        Text('${x['detail']} • ${x['at']}',style:const TextStyle(fontSize:11,color:Colors.black54))])),
    if((x['amount'] as num? ?? 0)!=0)Text(money((x['amount'] as num).toDouble()),style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold))])));

class PlansPage extends StatelessWidget {
  const PlansPage({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    TitleLine(t('Investment Plans','Investment Plans'),trailing:StatusBadge(data.activePlan.isEmpty?'Pending':'Active')),
    Text(t('Plan Prices صرف Demo ہیں؛ Admin انہیں تبدیل کر سکتا ہے۔ Profit Weight اصل روزانہ Net Profit کے Pool پر ہے، Principal پر Fixed Return نہیں۔',
      'Prices are DEMO settings, editable by Admin. Profit weights are not guaranteed returns on principal.'),
      style:const TextStyle(fontSize:12,color:Colors.black54)),const SizedBox(height:12),
    ...data.plans.where((p)=>p['active']==true).map((p)=>Padding(
      padding:const EdgeInsets.only(bottom:10),child:Block(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[const Icon(Icons.workspace_premium,color:gold),const SizedBox(width:8),
          Expanded(child:Text(p['name'].toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:green))),
          if(data.activePlan==p['name'])const StatusBadge('Active')]),const SizedBox(height:7),
        Text(money(p['price'] as num),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:22)),
        const SizedBox(height:4),Text('${t('Profit Pool Weight','Profit Pool Weight')}: ${p['weight']}  •  ${t('Referral Reward','Referral Reward')}: ${money(p['referral'] as num)}',
          style:const TextStyle(fontSize:12,color:Colors.black54)),const SizedBox(height:10),
        FilledButton(onPressed:()=>onPlanTap(context,p),child:Text(data.activePlan.isEmpty ? t('Buy Plan','Buy Plan'):
          data.activePlan==p['name'] ? t('Current Plan','Current Plan'):t('Upgrade','Upgrade'))),
      ])))),
  ]));
  void onPlanTap(BuildContext ctx,Map<String,dynamic> plan) async {
    if(data.activePlan==plan['name']) {snack(ctx,t('یہ آپ کا موجودہ پلان ہے','Already selected'));return;}
    if(!data.admittedRisk) {
      final accepted=await showDialog<bool>(context:ctx,builder:(context)=>AlertDialog(
        title:Text(t('Risk Acknowledgment','Risk Acknowledgment')),
        content:Text(t('Investment میں نقصان ممکن ہے؛ Principal اور Profit کی ضمانت نہیں۔ Demo کے لیے اس بات کو تسلیم کریں۔',
          'Trading can result in losses. Principal and profit are not guaranteed. Accept for demo testing.')),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(t('نہیں','Cancel'))),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:Text(t('قبول ہے','Accept')))]));
      if(accepted!=true) return;data.recordRisk();
    }
    final msg=data.activePlan.isEmpty?data.purchasePlan(plan):data.upgradePlan(plan);
    if(ctx.mounted)snack(ctx,msg??t('Plan Update ہوگیا (Demo)','Plan updated (demo)'),msg!=null);
  }
}

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Wallet & Transactions'),
    Block(child:Column(children:[valueRow('Total Wallet',money(data.totalWallet)),
      valueRow('Directly Withdrawable',money(data.withdrawable)),
      valueRow('Lifetime Deposit',money(data.lifetimeDeposit)),
      valueRow('Lifetime Referral',money(data.lifetimeReferral)),
      valueRow('Payout Destination',data.withdrawalAccount)])),const SizedBox(height:12),
    Row(children:[Expanded(child:FilledButton.icon(onPressed:()=>depositForm(context),
      icon:const Icon(Icons.add),label:Text(t('Deposit Request','Deposit Request')))),const SizedBox(width:9),
      Expanded(child:OutlinedButton.icon(onPressed:()=>withdrawForm(context),
        icon:const Icon(Icons.outbox_outlined),label:Text(t('Withdraw','Withdraw'))))]),
    const SizedBox(height:12),Text(t('Payment اس Demo App میں نہیں ہوتا۔ Admin وصولی کی تصدیق کرے گا۔',
      'No in-app payment. Admin must verify an external receipt.'),style:const TextStyle(color:Colors.black54,fontSize:12)),
    const TitleLine('Deposit Requests'),
    if(data.deposits.isEmpty)const Block(child:Text('No requests yet')),
    ...data.deposits.map((x)=>entryCard('${x['reference']}',money(x['amount'] as num),'${x['at']}',x['status'].toString())),
    const TitleLine('Withdrawal Requests'),
    if(data.withdrawals.isEmpty)const Block(child:Text('No requests yet')),
    ...data.withdrawals.map((x)=>entryCard(x['account'].toString(),money(x['amount'] as num),'${x['at']}',x['status'].toString())),
  ]));
  void depositForm(BuildContext ctx){
    final amount=TextEditingController();final ref=TextEditingController();
    showForm(ctx,t('Deposit Request','Deposit Request'),[
      FormLine(controller:amount,label:'Amount in PKR',numeric:true),
      FormLine(controller:ref,label:'External transaction ID')],() async {
        final err=data.requestDeposit(double.tryParse(amount.text)??0,ref.text);
        if(err==null&&ctx.mounted)Navigator.pop(ctx);if(ctx.mounted)snack(ctx,err??'Request submitted',err!=null);
    });
  }
  void withdrawForm(BuildContext ctx){
    final amount=TextEditingController();
    showForm(ctx,t('Withdraw Request','Withdraw Request'),[
      Text('Approved account: ${data.withdrawalAccount}'),const SizedBox(height:12),
      FormLine(controller:amount,label:'Amount in PKR',numeric:true)],() async {
        final err=data.requestWithdrawal(double.tryParse(amount.text)??0);
        if(err==null&&ctx.mounted)Navigator.pop(ctx);if(ctx.mounted)snack(ctx,err??'Withdrawal requested',err!=null);
    });
  }
}
Widget entryCard(String title,String amount,String subtitle,String status)=>Padding(
  padding:const EdgeInsets.only(bottom:8),child:Block(padding:const EdgeInsets.all(12),child:
    Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),Text(subtitle,style:const TextStyle(fontSize:11,color:Colors.black54))])),
      Column(crossAxisAlignment:CrossAxisAlignment.end,children:[Text(amount,style:const TextStyle(fontWeight:FontWeight.w800)),
        StatusBadge(status)])])));

class ReferralPage extends StatelessWidget {
  const ReferralPage({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Referral Center'),
    Block(child:Column(children:[
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Referral Rewards'),StatusBadge(data.referralEnabled?'Active':'OFF')]),
      const SizedBox(height:12),Text(data.referralCode,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900,color:green)),
      const SizedBox(height:14),QrImageView(data:data.referralCode,size:165,backgroundColor:Colors.white),
      const SizedBox(height:8),Text(t('QR میں Code ہے؛ Invitation Link Backend کے بعد فعال ہوگا۔',
        'QR holds the referral code. Invitation link requires a configured domain.'),
        textAlign:TextAlign.center,style:const TextStyle(fontSize:11,color:Colors.black54)),
      const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,alignment:WrapAlignment.center,children:[
        OutlinedButton.icon(onPressed:(){Clipboard.setData(ClipboardData(text:data.referralCode));snack(context,'Referral code copied');},
          icon:const Icon(Icons.copy),label:const Text('Copy Code')),
        OutlinedButton.icon(onPressed:()=>Share.share('Sarmaya Plus demo invite code: ${data.referralCode}'),
          icon:const Icon(Icons.share),label:const Text('Share')),
        OutlinedButton.icon(onPressed:()=>launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Sarmaya Plus invite code: ${data.referralCode}')}'),
          mode:LaunchMode.externalApplication),icon:const Icon(Icons.chat_bubble_outline),label:const Text('WhatsApp')),
        OutlinedButton.icon(onPressed:()=>launchUrl(Uri(scheme:'sms',queryParameters:{'body':'Sarmaya Plus invite code: ${data.referralCode}'})),
          icon:const Icon(Icons.sms_outlined),label:const Text('SMS')),
      ])])),
    const SizedBox(height:12),Row(children:[Expanded(child:Stat(label:'Total Referral Received',value:money(data.lifetimeReferral),icon:Icons.people_alt_outlined)),
      const SizedBox(width:10),Expanded(child:Stat(label:'Referral Wallet Spendable',value:money(data.referralWallet),icon:Icons.savings_outlined))]),
    const SizedBox(height:10),Text(t('Referral Balance Plan Buy/Upgrade کے لیے استعمال ہوگا؛ Direct Withdrawal نہیں۔',
      'Referral credit can fund a plan or upgrade, but cannot be withdrawn directly.'),style:const TextStyle(fontSize:12)),
    const TitleLine('Referral History'),
    if(data.referralHistory.isEmpty)const Block(child:Text('No new referral awards yet')),
    ...data.referralHistory.map((x)=>entryCard(x['referred'].toString(),money(x['amount'] as num),x['at'].toString(),x['status'].toString())),
  ]));
}

class MorePage extends StatelessWidget {
  const MorePage({super.key,required this.onLogout});final VoidCallback onLogout;
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('More'),
    moreTile(context,Icons.exit_to_app,'Investment Exit',const ExitPage()),
    moreTile(context,Icons.receipt_long,'Earnings & Activity',const HistoryPage()),
    moreTile(context,Icons.person_outline,'Profile',const ProfilePage()),
    moreTile(context,Icons.support_agent,'Help & Support',const SupportPage()),
    moreTile(context,Icons.notifications_outlined,'Notifications',const NotificationsPage()),
    const SizedBox(height:15),OutlinedButton.icon(onPressed:onLogout,
      icon:const Icon(Icons.logout),label:Text(t('واپس جائیں','Back to Demo Login'))),
  ]));
}
Widget moreTile(BuildContext ctx,IconData icon,String label,Widget page)=>Padding(padding:const EdgeInsets.only(bottom:8),
 child:Block(padding:EdgeInsets.zero,child:ListTile(leading:Icon(icon,color:green),
 title:Text(label),trailing:const Icon(Icons.chevron_right),onTap:()=>go(ctx,page))));

class ExitPage extends StatelessWidget {
  const ExitPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Investment Exit')),
    body:Column(children:[const DemoNotice(),Expanded(child:ScreenPad(child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const TitleLine('Exit Status'),
      Block(child:Column(children:[valueRow('Current Plan',data.activePlan.isEmpty?'None':data.activePlan),
        valueRow('Invested Amount',money(data.invested)),valueRow('Exit Status',data.exitStatus),
        if(data.exitRequestedAt.isNotEmpty)valueRow('Requested',data.exitRequestedAt)])),
      const SizedBox(height:12),if(data.exitStatus=='none'&&data.activePlan.isNotEmpty)
        bigButton('Request Full Investment Exit',(){snack(context,data.requestExit()??'Exit request submitted');}),
      if(data.exitStatus=='pending'||data.exitStatus=='review')
        bigButton('Cancel Exit Request',(){snack(context,data.cancelExit()??'Request cancelled');},icon:Icons.cancel_outlined),
      const SizedBox(height:12),Block(child:Text(t('Exit Trade شروع ہونے سے پہلے آپ خود Cancel کر سکتے ہیں۔ Exit رقم اصل Trading Results، فیس اور Loss پر منحصر ہوگی؛ 5 Working Days صرف اندازہ ہے۔',
        'Self-cancel is available before liquidation starts. Exit proceeds depend on trading, losses and liquidity; five business days is only an estimate.'))),
    ])))]));
}
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Earnings & Activity')),
    body:Column(children:[const DemoNotice(),Expanded(child:ScreenPad(child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Stat(label:'Total Earnings',value:money(data.lifetimeEarnings),icon:Icons.trending_up),
      const SizedBox(height:10),Stat(label:'Earnings Pending Next-Day Release',value:money(data.earningsWaiting)),
      const TitleLine('Transaction History'),...data.activity.map((x)=>activityTile(x)),
    ])))]));
}
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Profile')),
    body:Column(children:[const DemoNotice(),Expanded(child:ScreenPad(child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Block(child:Column(children:[valueRow('Name',data.name),valueRow('Phone',data.phone),
        valueRow('Referral Code',data.referralCode),valueRow('Verified Withdrawal Account',data.withdrawalAccount)])),
      const SizedBox(height:12),bigButton('Edit Demo Profile',(){
        final name=TextEditingController(text:data.name);final phone=TextEditingController(text:data.phone);
        showForm(context,'Edit Profile',[FormLine(controller:name,label:'Name'),FormLine(controller:phone,label:'Mobile')],()async{
          data.changeProfile(name.text,phone.text);Navigator.pop(context);snack(context,'Saved demo profile');});
      }),const SizedBox(height:14),const Block(child:Text('Real app: CNIC, bank details and security-sensitive changes require verification and approval. No sensitive identity documents are collected by this demo.')),
    ])))]));
}
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Support Tickets')),
    body:Column(children:[const DemoNotice(),Expanded(child:ScreenPad(child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      bigButton('Create Ticket',(){
        final s=TextEditingController();final m=TextEditingController();
        showForm(context,'Create Support Ticket',[FormLine(controller:s,label:'Subject'),
          FormLine(controller:m,label:'Message',maxLines:3)],()async{
            if(s.text.trim().isEmpty||m.text.trim().isEmpty){snack(context,'Please complete fields',true);return;}
            data.addTicket(s.text,m.text);Navigator.pop(context);snack(context,'Ticket created');});
      }),const TitleLine('My Tickets'),
      ...data.tickets.map((x)=>entryCard(x['subject'].toString(),x['status'].toString(),x['message'].toString(),x['at'].toString())),
    ])))]));
}
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Notifications')),
    body:Column(children:[const DemoNotice(),Expanded(child:ScreenPad(child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(data.notices.isEmpty)const Block(child:Text('No notifications yet')),
      ...data.notices.map((x)=>entryCard(x['text'].toString(),'',x['at'].toString(),'Info')),
    ])))]));
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key,required this.onLogout});
  final VoidCallback onLogout;
  @override State<AdminShell> createState()=>_AdminShellState();
}
class _AdminShellState extends State<AdminShell> {
  int selected=0;
  static const labels=['Overview','Deposits','Withdrawals','Referrals','Plans',
    'P2P Trading','Profit Approval','Expenses','Staff Salaries','Staff Accounts',
    'Users & KYC','Reports & Audit'];
  static const icons=[Icons.dashboard,Icons.payments,Icons.outbox,Icons.people,
    Icons.savings,Icons.currency_exchange,Icons.verified,Icons.receipt_long,
    Icons.payroll,Icons.manage_accounts,Icons.badge,Icons.analytics];
  @override Widget build(BuildContext context) {
    final pages=<Widget>[
      AdminOverview(onSelect:(x)=>setState(()=>selected=x)),const AdminDeposits(),
      const AdminWithdrawals(),const AdminReferrals(),const AdminPlans(),
      const AdminTrading(),const AdminProfit(),const AdminExpenses(),
      const AdminPayroll(),const AdminStaff(),const AdminUsers(),const AdminReports()];
    return Scaffold(appBar:AppBar(title:Text('Admin • ${labels[selected]}',
      style:const TextStyle(fontWeight:FontWeight.bold,fontSize:19)),
      actions:[IconButton(onPressed:()=>data.setLanguage(!data.urdu),icon:const Icon(Icons.language))]),
      drawer:Drawer(child:SafeArea(child:Column(children:[
        Container(width:double.infinity,color:green,padding:const EdgeInsets.all(20),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Image.asset('assets/sarmaya_icon.png',width:53,height:53),
            const SizedBox(height:10),const Text('SARMAYA PLUS ADMIN',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
            const Text('LOCAL DEMO • NO REAL ACCESS CONTROL',style:TextStyle(color:Colors.amber,fontSize:10))])),
        Expanded(child:ListView.builder(itemCount:labels.length,itemBuilder:(ctx,i)=>ListTile(
          selected:i==selected,leading:Icon(icons[i]),title:Text(labels[i]),
          onTap:(){setState(()=>selected=i);Navigator.pop(ctx);}))),
        ListTile(leading:const Icon(Icons.logout),title:const Text('Back to Demo Login'),onTap:(){Navigator.pop(context);widget.onLogout();}),
      ]))),
      body:Column(children:[const DemoNotice(),Expanded(child:pages[selected])]));
  }
}

class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key,required this.onSelect});
  final ValueChanged<int> onSelect;
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Admin Dashboard'),
    const Text('All financial actions in this preview are local demo actions, not audited real-money operations.',
      style:TextStyle(fontSize:12,color:Colors.red)),const SizedBox(height:12),
    Row(children:[Expanded(child:Stat(label:'Unverified Deposits',value:'${data.deposits.where((x)=>x['status']=='Pending').length}',icon:Icons.pending_actions)),
      const SizedBox(width:10),Expanded(child:Stat(label:'Pending Withdrawals',value:'${data.withdrawals.where((x)=>x['status']=='Pending').length}',icon:Icons.hourglass_bottom))]),
    const SizedBox(height:10),Row(children:[Expanded(child:Stat(label:'Realized Profit Not Yet Allocated',value:money(data.profitReady),icon:Icons.show_chart)),
      const SizedBox(width:10),Expanded(child:Stat(label:'Prior Trading Losses',value:money(data.priorLossCarry),icon:Icons.trending_down))]),
    const SizedBox(height:10),Row(children:[Expanded(child:Stat(label:'Owner Funds',value:money(data.ownerAvailable),icon:Icons.account_balance)),
      const SizedBox(width:10),Expanded(child:Stat(label:'Owner Unpaid Expenses',value:money(data.ownerLiabilities),icon:Icons.receipt))]),
    const TitleLine('Quick Administration'),
    Wrap(spacing:8,runSpacing:8,children:[
      ActionChip(avatar:const Icon(Icons.payments,size:18),label:const Text('Deposits'),onPressed:()=>onSelect(1)),
      ActionChip(avatar:const Icon(Icons.currency_exchange,size:18),label:const Text('P2P Trades'),onPressed:()=>onSelect(5)),
      ActionChip(avatar:const Icon(Icons.verified,size:18),label:const Text('Profit Approval'),onPressed:()=>onSelect(6)),
      ActionChip(avatar:const Icon(Icons.people,size:18),label:const Text('Referrals'),onPressed:()=>onSelect(3)),
      ActionChip(avatar:const Icon(Icons.manage_accounts,size:18),label:const Text('Staff'),onPressed:()=>onSelect(9)),
    ]),
    const TitleLine('Recent Audit History'),
    ...data.activity.take(7).map((x)=>activityTile(x)),
  ]));
}

class AdminDeposits extends StatelessWidget {
  const AdminDeposits({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Manual Deposit Verification'),
    const Block(child:Text('Only approve after checking the real external receipt. No payment gateway is connected in this demo.')),
    const SizedBox(height:12),
    if(data.deposits.isEmpty)const Block(child:Text('No deposit requests. Create one from Investor Wallet.')),
    ...data.deposits.map((x)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Block(child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        valueRow('Transaction ID',x['reference'].toString()),valueRow('Amount',money(x['amount'] as num)),
        valueRow('Submitted',x['at'].toString()),valueRow('Status',x['status'].toString()),
        if(x['status']=='Pending')Row(children:[Expanded(child:OutlinedButton(onPressed:()=>confirmAction(context,
          'Reject deposit?',()=>data.approveDeposit(x['id'].toString(),false)),child:const Text('Reject'))),
          const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>confirmAction(context,
          'Confirm external payment received?',()=>data.approveDeposit(x['id'].toString(),true)),child:const Text('Approve')))]),
      ])))),
  ]));
}
Future<void> confirmAction(BuildContext context,String title,VoidCallback action) async {
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),
    content:const Text('This changes LOCAL DEMO data only.'),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]));
  if(ok==true) {action();if(context.mounted)snack(context,'Demo record updated');}
}

class AdminWithdrawals extends StatelessWidget {
  const AdminWithdrawals({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Withdrawal Requests'),
    if(data.withdrawals.isEmpty)const Block(child:Text('No withdrawal requests')),
    ...data.withdrawals.map((x)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Block(child:
      Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        valueRow('Amount',money(x['amount'] as num)),valueRow('Account',x['account'].toString()),
        valueRow('Requested',x['at'].toString()),valueRow('Status',x['status'].toString()),
        if(x['status']=='Pending')Row(children:[Expanded(child:OutlinedButton(onPressed:()=>confirmAction(context,
          'Reject request and return reserved balance?',()=>data.processWithdrawal(x['id'].toString(),false)),child:const Text('Reject'))),
          const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>confirmAction(context,
          'Mark externally paid? Only after actual transfer.',()=>data.processWithdrawal(x['id'].toString(),true)),child:const Text('Mark Paid')))]),
      ])))),
  ]));
}

class AdminReferrals extends StatelessWidget {
  const AdminReferrals({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Referral Rewards Settings'),
    Block(child:Column(children:[SwitchListTile(title:const Text('Enable Referral Rewards'),
      subtitle:const Text('OFF = no new rewards and no distribution'),
      value:data.referralEnabled,onChanged:(v)=>data.setReferrals(v)),
      valueRow('Demo Referral Fund (sample)',money(data.referralFund)),
      valueRow('Current Referral Credits',money(data.referralWallet)),
      valueRow('Lifetime Referral Awards',money(data.lifetimeReferral))])),
    const SizedBox(height:12),bigButton('Approve & Add Funded Reward',()=>referralGrantForm(context)),
    const SizedBox(height:9),const Block(child:Text('Rewards are manually approved. Suspicious cases stay on HOLD. No direct referral withdrawal. Duplicate awards rejected.')),
    const TitleLine('Award History'),
    ...data.referralHistory.map((x)=>entryCard(x['referred'].toString(),money(x['amount'] as num),x['at'].toString(),x['status'].toString())),
  ]));
  void referralGrantForm(BuildContext context){
    final who=TextEditingController();final amt=TextEditingController();
    showForm(context,'Add Approved Referral Credit',[
      FormLine(controller:who,label:'Referred unique user ID'),
      FormLine(controller:amt,label:'Approved reward PKR',numeric:true)],()async{
        final err=data.grantReferral(who.text,double.tryParse(amt.text)??0);
        if(err==null&&context.mounted)Navigator.pop(context);
        if(context.mounted)snack(context,err??'Credited to demo Referral Wallet',err!=null);
      });
  }
}
class AdminPlans extends StatelessWidget {
  const AdminPlans({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Plan Management'),
    const Block(child:Text('Demo plan prices and weights are editable. No guaranteed returns. Changes here are local to this demo device.')),
    const SizedBox(height:12),
    ...data.plans.asMap().entries.map((entry)=>Padding(padding:const EdgeInsets.only(bottom:8),
      child:Block(child:Column(children:[valueRow(entry.value['name'].toString(),money(entry.value['price'] as num)),
        valueRow('Weight',entry.value['weight'].toString()),
        valueRow('Referral Reward',money(entry.value['referral'] as num)),
        Row(children:[StatusBadge(entry.value['active']==true?'Active':'Disabled'),const Spacer(),
          OutlinedButton(onPressed:()=>editPlan(context,entry.key,entry.value),child:const Text('Edit'))])])))),
  ]));
  void editPlan(BuildContext context,int idx,Map<String,dynamic> plan){
    final amount=TextEditingController(text:'${plan['price']}');
    final weight=TextEditingController(text:'${plan['weight']}');
    final ref=TextEditingController(text:'${plan['referral']}');
    bool active=plan['active']==true;
    showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setLocal)=>AlertDialog(
      title:Text('Edit ${plan['name']}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        FormLine(controller:amount,label:'Price PKR',numeric:true),FormLine(controller:weight,label:'Profit Pool Weight',numeric:true),
        FormLine(controller:ref,label:'Referral PKR',numeric:true),SwitchListTile(title:const Text('Active'),value:active,onChanged:(v)=>setLocal(()=>active=v)),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        FilledButton(onPressed:(){final a=double.tryParse(amount.text)??0;final b=double.tryParse(weight.text)??0;
          final c=double.tryParse(ref.text)??-1;
          if(a<=0||b<=0||c<0){snack(ctx,'Invalid values',true);return;}
          data.updatePlan(idx,a,b,c,active);Navigator.pop(ctx);},child:const Text('Save'))])));
  }
}

class AdminTrading extends StatelessWidget {
  const AdminTrading({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('P2P Trades • Weighted Average Cost'),
    Block(child:Column(children:[valueRow('USDT Inventory','${data.inventoryUsdt.toStringAsFixed(4)} USDT'),
      valueRow('Total USDT Cost',money(data.inventoryCostPkr)),
      valueRow('Weighted Avg Cost / USDT',money(data.averageUsdtCost)),
      valueRow('Verified Realized Profit Pending',money(data.profitReady)),
      valueRow('Unrecovered Prior Loss',money(data.priorLossCarry))])),
    const SizedBox(height:12),Row(children:[Expanded(child:FilledButton.icon(onPressed:()=>tradeForm(context,true),
      icon:const Icon(Icons.add),label:const Text('Record Buy'))),const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(onPressed:()=>tradeForm(context,false),
        icon:const Icon(Icons.remove),label:const Text('Record Sell')))]),
    const SizedBox(height:9),const Block(child:Text('Enter actual amounts received/sent. Fees and differences must be reflected once in actual amounts. Real service requires verified trade receipts, reconciled accounts and admin approvals.')),
    const TitleLine('Trade Records'),
    if(data.trades.isEmpty)const Block(child:Text('No trades recorded')),
    ...data.trades.map((x)=>Padding(padding:const EdgeInsets.only(bottom:9),child:Block(child:Column(children:[
      valueRow('${x['type']} • ${x['orderId']}','${x['usdt']} USDT'),
      valueRow('Actual PKR',money(x['pkr'] as num)),
      valueRow('Actual Rate',money(x['rate'] as num)),
      if(x['type']=='SELL')valueRow('Realized P&L',money(x['pnl'] as num)),
      Text('${x['counterparty']}  /  ${x['transferId']}  /  ${x['at']}',style:const TextStyle(fontSize:11,color:Colors.black54)),
    ])))),
  ]));
  void tradeForm(BuildContext ctx,bool buy) {
    final usdt=TextEditingController();final pkr=TextEditingController();
    final order=TextEditingController();final transfer=TextEditingController();final party=TextEditingController();
    showForm(ctx,buy?'P2P USDT Buy':'P2P USDT Sell',[
      FormLine(controller:usdt,label:'Actual USDT ${buy?'received':'sent'}',numeric:true),
      FormLine(controller:pkr,label:'Actual PKR ${buy?'paid':'received'}',numeric:true),
      FormLine(controller:order,label:'Binance Order ID'),
      FormLine(controller:transfer,label:'Payment Transaction ID'),
      FormLine(controller:party,label:'Counterparty name / institution')],()async{
        final err=data.recordTrade(buy:buy,usdt:double.tryParse(usdt.text)??0,
          pkr:double.tryParse(pkr.text)??0,orderId:order.text,transferId:transfer.text,counterparty:party.text);
        if(err==null&&ctx.mounted)Navigator.pop(ctx);if(ctx.mounted)snack(ctx,err??'Trade saved',err!=null);
      });
  }
}

class AdminProfit extends StatelessWidget {
  const AdminProfit({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Realized Profit Allocation'),
    Block(child:Column(children:[valueRow('Profit ready (after loss carry)',money(data.profitReady)),
      valueRow('Users Pool (50%)',money(data.profitReady*.5)),
      valueRow('Owner (30%)',money(data.profitReady*.3)),
      valueRow('Loss Reserve (${data.reservePercent}%)',money(data.profitReady*data.reservePercent/100)),
      valueRow('Referral (${data.referralPercent}%)',money(data.profitReady*data.referralPercent/100)),
      valueRow('Approval Stage',data.distributionStage)])),
    const SizedBox(height:12),bigButton(
      data.distributionStage=='draft'?'Trading Manager: Review & Submit':
      data.distributionStage=='trading_checked'?'Finance Manager: Verify':
      'Super Admin: Approve & Allocate',
      (){if(data.profitReady<=0||data.activePlan.isEmpty){snack(context,'Need positive realized profit and active demo investment',true);return;}
        confirmAction(context,'Confirm ${data.distributionStage} approval?',data.progressDistribution);},
      icon:Icons.verified_user_outlined),
    const SizedBox(height:12),Block(child:Column(children:[
      valueRow('Owner Available',money(data.ownerAvailable)),
      valueRow('Loss Recovery Reserve',money(data.reserveFund)),
      valueRow('Referral Budget',money(data.referralFund)),
      valueRow('Earnings Pending Next Day',money(data.earningsWaiting))])),
    const TitleLine('20% Combined Fund Split'),
    Block(child:Column(children:[Text('Loss Recovery: ${data.reservePercent.toStringAsFixed(1)}%   •   Referral: ${data.referralPercent.toStringAsFixed(1)}%'),
      Slider(value:data.reservePercent,min:0,max:20,divisions:20,label:'${data.reservePercent}%',
        onChanged:(v)=>data.configureFundSplit(v)),
      const Text('Super Admin can set prospective split only; never exceed 20%.',style:TextStyle(fontSize:12,color:Colors.black54)),
    ])),
    const SizedBox(height:12),const Block(child:Text('Demo assumption: one investor holds the entire users pool. A multi-investor production engine must calculate all eligible weighted shares, reconcile net losses, freeze a profit date, and enforce idempotent approval transactions on the server.')),
  ]));
}

class AdminExpenses extends StatelessWidget {
  const AdminExpenses({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Owner-Funded Expenses'),
    Block(child:Column(children:[valueRow('Owner Remaining Share',money(data.ownerAvailable)),
      valueRow('Owner Liabilities (unpaid)',money(data.ownerLiabilities))])),
    const SizedBox(height:10),bigButton('Record Expense',()=>add(context)),
    const SizedBox(height:10),const Block(child:Text('Office expenses must be funded from owner 30% share, never the investors pool, referral/reserve fund or principal.')),
    const TitleLine('Expense Register'),
    ...data.expenses.map((x)=>entryCard(x['title'].toString(),money(x['amount'] as num),
      'Paid ${money(x['paid'] as num)}  •  ${x['at']}',x['status'].toString())),
  ]));
  void add(BuildContext ctx){
    final what=TextEditingController();final amount=TextEditingController();
    showForm(ctx,'Record Expense',[FormLine(controller:what,label:'Expense type / Payee'),
      FormLine(controller:amount,label:'Amount PKR',numeric:true)],()async{
        final err=data.addExpense(what.text,double.tryParse(amount.text)??0);
        if(err==null&&ctx.mounted)Navigator.pop(ctx);if(ctx.mounted)snack(ctx,err??'Expense recorded',err!=null);
      });
  }
}
class AdminPayroll extends StatelessWidget {
  const AdminPayroll({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Staff Salary & Payroll'),
    Block(child:Column(children:[valueRow('Owner Remaining Share',money(data.ownerAvailable)),
      valueRow('Owner Unpaid Liabilities',money(data.ownerLiabilities))])),
    const SizedBox(height:10),bigButton('Record Monthly Salary',()=>add(context)),
    const SizedBox(height:10),const Block(child:Text('Salaries are paid only from owner share or recorded as owner-funded liabilities. This demo does not transfer real salary payments.')),
    const TitleLine('Payroll History'),
    ...data.payroll.map((x)=>entryCard(x['employee'].toString(),money(x['amount'] as num),
      'Paid ${money(x['paid'] as num)}  •  ${x['at']}',x['status'].toString())),
  ]));
  void add(BuildContext ctx){
    final name=TextEditingController();final amount=TextEditingController();
    showForm(ctx,'Salary Entry',[FormLine(controller:name,label:'Staff Name / Month'),
      FormLine(controller:amount,label:'Salary PKR',numeric:true)],()async{
        final err=data.addSalary(name.text,double.tryParse(amount.text)??0);
        if(err==null&&ctx.mounted)Navigator.pop(ctx);if(ctx.mounted)snack(ctx,err??'Payroll recorded',err!=null);
      });
  }
}

class AdminStaff extends StatelessWidget {
  const AdminStaff({super.key});
  static const roles=['Admin','Finance Manager','Trading Manager','Support Staff'];
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Staff Accounts'),
    Block(child:Column(children:[valueRow('Active Staff', '${data.staff.where((x)=>x['active']==true).length} / 5'),
      const Text('DEMO only: Staff identities, credentials, MFA and permissions are not deployed.',
        style:TextStyle(fontSize:12,color:Colors.red))])),
    const SizedBox(height:10),bigButton('Add Staff Entry',()=>add(context)),
    const TitleLine('Staff Register'),
    ...data.staff.asMap().entries.map((entry)=>Padding(padding:const EdgeInsets.only(bottom:9),child:Block(child:Row(children:[
      const Icon(Icons.person_outline,color:green),const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(entry.value['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
        Text(entry.value['role'].toString(),style:const TextStyle(fontSize:12))])),
      if(entry.value['active']==true && entry.value['role']!='Super Admin')
        IconButton(tooltip:'Disable',onPressed:()=>confirmAction(context,'Disable demo staff?',()=>data.disableStaff(entry.key)),
          icon:const Icon(Icons.block,color:Colors.red))
      else StatusBadge(entry.value['active']==true?'Active':'Disabled'),
    ])))),
  ]));
  void add(BuildContext ctx){
    final name=TextEditingController();String role=roles.first;
    showDialog<void>(context:ctx,builder:(ctx)=>StatefulBuilder(builder:(ctx,upd)=>AlertDialog(
      title:const Text('Add Demo Staff'),content:Column(mainAxisSize:MainAxisSize.min,children:[
        FormLine(controller:name,label:'Staff Name'),
        DropdownButtonFormField<String>(value:role,items:roles.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
          onChanged:(v)=>upd(()=>role=v??role),decoration:const InputDecoration(labelText:'Role'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        FilledButton(onPressed:(){final err=data.addStaff(name.text,role);if(err==null)Navigator.pop(ctx);
          snack(context,err??'Staff entry created',err!=null);},child:const Text('Add'))])));
  }
}

class AdminUsers extends StatelessWidget {
  const AdminUsers({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('User & KYC Management'),
    Block(child:Column(children:[valueRow('Demo Investor',data.name),
      valueRow('Mobile',data.phone),valueRow('Referral Code',data.referralCode),
      valueRow('Demo Verified Withdrawal Account',data.withdrawalAccount),
      valueRow('Total Deposited',money(data.lifetimeDeposit)),
      valueRow('Active Investment',money(data.invested)),
      valueRow('Exit Status',data.exitStatus)])),
    const SizedBox(height:12),const Block(child:Text('No actual identity verification is performed here. CNIC and identity document upload are intentionally not collected in this local prototype.')),
    const TitleLine('Investment Exit Admin Control'),
    if(data.exitStatus=='pending')bigButton('Mark Exit Under Review',()=>data.reviewExit()),
    if(data.exitStatus=='pending'||data.exitStatus=='review')bigButton('Start Exit Liquidation',()=>
      confirmAction(context,'Begin actual exit process in DEMO? This locks user self-cancel.',data.startExitTrade)),
    if(data.exitStatus=='trading')bigButton('Settle Realized Exit Amount',()=>settle(context)),
  ]));
  void settle(BuildContext ctx){
    final amount=TextEditingController(text:data.invested.toStringAsFixed(2));
    showForm(ctx,'Exit Settlement • Realized Funds',[
      FormLine(controller:amount,label:'ACTUAL realized proceeds PKR',numeric:true),
      const Text('Use true realized value. Do not guarantee full principal.'),
    ],()async{final err=data.settleExit(double.tryParse(amount.text)??-1);
      if(err==null&&ctx.mounted)Navigator.pop(ctx);if(ctx.mounted)snack(ctx,err??'Demo exit settled',err!=null);});
  }
}

class AdminReports extends StatelessWidget {
  const AdminReports({super.key});
  @override Widget build(BuildContext context)=>ScreenPad(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const TitleLine('Reports & Audit History'),
    Block(child:Column(children:[valueRow('Approved Lifetime Deposits',money(data.lifetimeDeposit)),
      valueRow('Lifetime Referral Awards',money(data.lifetimeReferral)),
      valueRow('Lifetime Earnings',money(data.lifetimeEarnings)),
      valueRow('Lifetime Withdrawals',money(data.lifetimeWithdrawn)),
      valueRow('Invested Value (demo)',money(data.invested)),
      valueRow('Total Demo Wallet',money(data.totalWallet)),
      valueRow('USDT Inventory','${data.inventoryUsdt.toStringAsFixed(4)} USDT'),
      valueRow('Owner Liabilities',money(data.ownerLiabilities))])),
    const SizedBox(height:12),bigButton('Share Demo Audit CSV',()=>exportCsv(),icon:Icons.ios_share),
    const SizedBox(height:8),const Block(child:Text('For production: server-generated PDF/XLSX/CSV, retention, encrypted backups and immutable ledger exports are still required.')),
    const TitleLine('Audit Events'),...data.activity.map((x)=>activityTile(x)),
  ]));
  void exportCsv(){
    String quote(Object? value) => '"' + (value ?? '').toString().replaceAll('"', '""') + '"';
    final lines=<String>['type,detail,amount,timestamp'];
    for(final x in data.activity){lines.add([x['type'],x['detail'],x['amount'],x['at']].map(quote).join(','));}
    Share.share(lines.join('\n'),subject:'Sarmaya Plus Demo Audit CSV');
  }
}

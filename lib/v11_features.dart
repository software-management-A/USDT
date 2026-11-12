import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as hashing;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

typedef V11Request = Future<Map<String, dynamic>> Function(
    String method, String path, [Map<String, dynamic>? body]);
const v11Green = Color(0xFF123F2B);
const v11Pale = Color(0xFFEAF3EC);
const v11Url = 'https://sarmaya-plus-api.bismurahved-819.workers.dev';

List<Map<String,dynamic>> v11List(dynamic v) => v is List
    ? v.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList() : [];
String v11Format(dynamic raw,String currency) {
  final n=raw is num?raw.toInt():int.tryParse('$raw')??0;
  final d=currency=='USDT'?6:2,scale=currency=='USDT'?1000000:100;
  return '${n<0?'-':''}${n.abs()~/scale}.${(n.abs()%scale).toString().padLeft(d,'0')} $currency';
}
String v11Amount(double d,[int dp=2])=>d.isFinite?d.toStringAsFixed(dp):'0.00';
String v11Now()=>DateTime.now().toUtc().toIso8601String();
String v11Err(Object e)=>'$e'.replaceFirst('Exception: ', '');
void v11Toast(BuildContext c,String s){if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(s)));}
Future<String?> v11Prompt(BuildContext context,String title,{String initial='',String label='',bool secret=false})async{
  final controller=TextEditingController(text:initial);
  try{return await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(title),content:TextField(controller:controller,autofocus:true,obscureText:secret,
      decoration:InputDecoration(labelText:label.isEmpty?title:label)),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('OK'))],
  ));}finally{controller.dispose();}
}
Future<String?> v11Choose(BuildContext context,String title,List<String> options)async=>
  showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:Text(title),children:options.map((v)=>
  SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,v),child:Padding(padding:const EdgeInsets.all(9),child:Text(v)))).toList()));
Future<bool> v11Confirm(BuildContext context,String title,String description)async=>
  await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),
    content:SingleChildScrollView(child:Text(description)),actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm')),
  ]))??false;
Future<bool> v11Reauth(BuildContext context)async{
  final user=FirebaseAuth.instance.currentUser;if(user==null||user.email==null)return false;
  final password=await v11Prompt(context,'Confirm Admin Password',secret:true);
  if(password==null||password.isEmpty)return false;
  try{await user.reauthenticateWithCredential(EmailAuthProvider.credential(email:user.email!,password:password));
    await user.getIdToken(true);return true;
  }catch(e){if(context.mounted)v11Toast(context,'Authentication failed: $e');return false;}
}

class V11SessionGate extends StatefulWidget {
  const V11SessionGate({super.key,required this.user,required this.child});
  final User user;final Widget child;
  @override State<V11SessionGate> createState()=>_V11SessionGateState();
}
class _V11SessionGateState extends State<V11SessionGate> with WidgetsBindingObserver {
  static const store=FlutterSecureStorage();
  final auth=LocalAuthentication();
  final pinInput=TextEditingController(),pinAgain=TextEditingController();
  DateTime touched=DateTime.now();Timer? checkTimer;
  bool locked=false,settingUp=false,checkingRelease=true,saveLogin=true,optionalVisible=false;
  int pinFailures=0;String? requiredUrl,optionalUrl,versionMessage;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_load();
    checkTimer=Timer.periodic(const Duration(seconds:15),(_)=>_checkIdle());}
  @override void dispose(){checkTimer?.cancel();pinInput.dispose();pinAgain.dispose();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)_checkIdle();
  }
  Future<void> _load()async{
    final prefs=await SharedPreferences.getInstance();saveLogin=prefs.getBool('v11_save_login')??true;
    final pin=await store.read(key:'v11_pin_${widget.user.uid}');
    if(!mounted)return;
    setState((){settingUp=pin==null;locked=pin!=null&&prefs.getBool('v11_lock_on_launch')==true;});
    await _release();
  }
  Future<void> _release()async{
    try{
      final token=await widget.user.getIdToken();final info=await PackageInfo.fromPlatform();
      final build=int.tryParse(info.buildNumber)??0;
      final client=HttpClient()..connectionTimeout=const Duration(seconds:12);
      try{
        final req=await client.getUrl(Uri.parse('$v11Url/v1/v11/update/manifest'));
        req.headers.set('Authorization','Bearer $token');req.headers.set('X-Sarmaya-Build','$build');
        final res=await req.close().timeout(const Duration(seconds:15));
        if(res.statusCode==200){final body=jsonDecode(await utf8.decoder.bind(res).join()) as Map;
          final minimum=(body['min_build'] as num?)?.toInt()??0;
          final latest=(body['latest_build'] as num?)?.toInt()??0;
          final url='${body['apk_url']??''}';
          if(mounted)setState((){
            requiredUrl=minimum>build&&url.startsWith('https://')?url:null;
            optionalUrl=latest>build&&url.startsWith('https://')?url:null;
            optionalVisible=optionalUrl!=null&&requiredUrl==null;
            versionMessage='New release ${body['latest_version']} — ${body['notes']??''}';
          });
        }
      }finally{client.close(force:true);}
    }catch(_){/* Keep signed-in user functional if manifest service is offline. Server still enforces required versions. */}
    finally{if(mounted)setState(()=>checkingRelease=false);}
  }
  void _checkIdle(){if(!mounted||locked||settingUp)return;
    if(DateTime.now().difference(touched)>=const Duration(minutes:15))setState(()=>locked=true);
  }
  String _pinDigest(String salt,String pin)=>hashing.sha256.convert(utf8.encode('$salt:$pin')).toString();
  Future<void> _createPin()async{
    final pin=pinInput.text.trim(),confirm=pinAgain.text.trim();
    if(!RegExp(r'^\d{6}$').hasMatch(pin)){v11Toast(context,'PIN must contain exactly six digits.');return;}
    if(confirm!=pin){v11Toast(context,'PINs did not match.');return;}
    final rnd=Random.secure(),salt=List.generate(16,(_)=>rnd.nextInt(256)).map((x)=>x.toRadixString(16).padLeft(2,'0')).join();
    await store.write(key:'v11_pin_${widget.user.uid}',value:'$salt:${_pinDigest(salt,pin)}');
    pinInput.clear();pinAgain.clear();
    if(mounted)setState((){settingUp=false;locked=false;touched=DateTime.now();});
  }
  Future<void> _unlockPin()async{
    final pin=pinInput.text.trim();pinInput.clear();if(pin.isEmpty)return;
    final saved=await store.read(key:'v11_pin_${widget.user.uid}');final parts=(saved??'').split(':');
    if(parts.length==2&&_pinDigest(parts[0],pin)==parts[1]){
      final prefs=await SharedPreferences.getInstance();await prefs.setBool('v11_lock_on_launch',false);
      if(mounted)setState((){pinFailures=0;locked=false;touched=DateTime.now();});
    }else{pinFailures++;if(mounted)v11Toast(context,'Incorrect PIN');
      if(pinFailures>=5){await FirebaseAuth.instance.signOut();}
    }
  }
  Future<void> _biometric()async{
    try{final allowed=await auth.canCheckBiometrics;
      if(!allowed){if(mounted)v11Toast(context,'Biometrics not available. Use your PIN.');return;}
      final good=await auth.authenticate(localizedReason:'Unlock Sarmaya Plus',
        options:const AuthenticationOptions(biometricOnly:true,stickyAuth:true));
      if(good&&mounted)setState((){locked=false;touched=DateTime.now();pinFailures=0;});
    }catch(e){if(mounted)v11Toast(context,'Use PIN: $e');}
  }
  Future<void> _openRelease(String? link)async{
    if(link==null||!link.startsWith('https://github.com/'))return;
    await launchUrl(Uri.parse(link),mode:LaunchMode.externalApplication);
  }
  @override Widget build(BuildContext context){
    Widget? blocking;
    if(checkingRelease)blocking=const Material(child:Center(child:CircularProgressIndicator()));
    else if(requiredUrl!=null)blocking=Scaffold(appBar:AppBar(title:const Text('Update Required')),
      body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.system_update,size:64,color:v11Green),const SizedBox(height:18),
        Text(versionMessage??'A required update is available.',textAlign:TextAlign.center),
        const SizedBox(height:16),FilledButton(onPressed:()=>_openRelease(requiredUrl),child:const Text('Download New APK')),
        const SizedBox(height:12),const Text('Android will ask you to approve installation. Keep the same signing key.',textAlign:TextAlign.center),
      ]))));
    else if(settingUp||locked)blocking=Scaffold(appBar:AppBar(title:Text(settingUp?'Set Up App Lock':'Sarmaya Plus Locked')),
      body:Center(child:SingleChildScrollView(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:400),
      child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(settingUp?Icons.password:Icons.lock_outline,size:64,color:v11Green),const SizedBox(height:16),
        Text(settingUp?'Create your local six-digit PIN':'Locked after 15 minutes of inactivity'),
        const SizedBox(height:18),
        TextField(controller:pinInput,obscureText:true,keyboardType:TextInputType.number,
          maxLength:6,decoration:InputDecoration(labelText:settingUp?'Create PIN':'Enter App PIN')),
        if(settingUp)TextField(controller:pinAgain,obscureText:true,keyboardType:TextInputType.number,
          maxLength:6,decoration:const InputDecoration(labelText:'Repeat PIN')),
        FilledButton(onPressed:settingUp?_createPin:_unlockPin,child:Text(settingUp?'Set PIN':'Unlock with PIN')),
        if(!settingUp)OutlinedButton(onPressed:_biometric,child:const Text('Use Fingerprint / Biometrics')),
        TextButton(onPressed:()=>FirebaseAuth.instance.signOut(),child:const Text('Sign Out')),
      ]))))));
    return Listener(onPointerDown:(_){if(!locked&&!settingUp)touched=DateTime.now();},
      behavior:HitTestBehavior.translucent,child:Stack(children:[
        widget.child,
        if(optionalVisible&&!locked&&!settingUp&&!checkingRelease&&requiredUrl==null)
          Align(alignment:Alignment.topCenter,child:SafeArea(child:MaterialBanner(
            content:Text(versionMessage??'Optional update available'),
            actions:[TextButton(onPressed:()=>setState(()=>optionalVisible=false),child:const Text('Later')),
              TextButton(onPressed:()=>_openRelease(optionalUrl),child:const Text('Update'))],))),
        if(blocking!=null)Positioned.fill(child:blocking),
      ]));
  }
}

class V11HubPage extends StatefulWidget {
  const V11HubPage({super.key,required this.request,required this.owner});
  final V11Request request;final bool owner;
  @override State<V11HubPage> createState()=>_V11HubPageState();
}
class _V11HubPageState extends State<V11HubPage>{
 String language='en';bool loading=true;String role='customer';
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{try{final r=await widget.request('GET','/v1/remit/access');
  final p=await widget.request('GET','/v1/v11/preferences');if(mounted)setState((){
    role='${r['role']??'customer'}';language='${p['preferences']?['language']??'en'}';loading=false;});
 }catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'Sync: $e');}}}
 String t(String en,String ur)=>language=='ur'?ur:en;
 void open(Widget w)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>w)).then((_)=>refresh());
 Widget tile(String en,String ur,IconData i,Widget page)=>Card(child:ListTile(
  leading:Icon(i,color:v11Green),title:Text(t(en,ur)),trailing:const Icon(Icons.chevron_right),onTap:()=>open(page)));
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Sarmaya Plus v11','سرمایہ پلس v11')),
  actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),
  body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(15),children:[
   Card(color:v11Pale,child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(t('Recordkeeping & Calculations','حساب اور ریکارڈ'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    Text('${t('Role','کردار')}: $role'),
    Text(t('Bank and Binance transactions take place outside this app.','بینک اور بائنانس کا لین دین ایپ سے باہر ہوگا۔')),
   ]))),
   if(widget.owner)...[
    tile('Accounts — Banks & Binance','بینک اور بائنانس اکاؤنٹس',Icons.account_balance,V11AccountsPage(request:widget.request)),
    tile('USDT Trading — Multi-Lot Sales','USDT خرید و فروخت',Icons.swap_horiz,V11TradingPage(request:widget.request)),
    tile('Investment Plans & Funding','انویسٹمنٹ پلان اور فنڈنگ',Icons.wallet,V11PlansPage(request:widget.request,owner:true)),
    tile('Profit Reports & PDF','منافع رپورٹ اور پی ڈی ایف',Icons.bar_chart,V11ReportsPage(request:widget.request)),
    tile('Backup / Import / Reset','بیک اپ، درآمد اور ری سیٹ',Icons.backup,V11AdminToolsPage(request:widget.request)),
   ],
   if(!widget.owner)tile('My Investment Terms','میری سرمایہ کاری',Icons.trending_up,V11PlansPage(request:widget.request,owner:false)),
   tile('Language & Preferences','زبان اور ترتیبات',Icons.settings,V11PreferencesPage(request:widget.request)),
  ]));
}

class V11AccountsPage extends StatefulWidget {const V11AccountsPage({super.key,required this.request});final V11Request request;
 @override State<V11AccountsPage> createState()=>_V11AccountsPageState();}
class _V11AccountsPageState extends State<V11AccountsPage>{
 bool loading=true;List<Map<String,dynamic>> accounts=[];
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{try{final r=await widget.request('GET','/v1/v11/accounts');if(mounted)setState((){accounts=v11List(r['accounts']);loading=false;});}
 catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'$e');}}}
 Future<void> add()async{
  final label=await v11Prompt(context,'Account Nickname');if(label==null||label.isEmpty)return;
  final kind=await v11Choose(context,'Account Type',['bank','binance','wallet','cash','other']);if(kind==null)return;
  final cur=await v11Choose(context,'Currency',['AED','PKR','USDT']);if(cur==null)return;
  final holder=await v11Prompt(context,'Account Holder Name');if(holder==null)return;
  final ref=await v11Prompt(context,'Masked Reference (e.g. ****1234)');if(ref==null)return;
  try{await widget.request('POST','/v1/v11/accounts',{'label':label,'kind':kind,'currency':cur,'holder_name':holder,'masked_reference':ref});await refresh();}
  catch(e){if(mounted)v11Toast(context,'$e');}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Bank & Binance Accounts')),
  body:ListView(padding:const EdgeInsets.all(14),children:[
  FilledButton.icon(onPressed:add,icon:const Icon(Icons.add),label:const Text('Add Account')),
  if(loading)const LinearProgressIndicator(),
  ...accounts.map((a)=>Card(child:ListTile(leading:const Icon(Icons.account_balance,color:v11Green),
   title:Text('${a['label']} • ${a['currency']}'),subtitle:Text('${a['kind']} • ${a['holder_name']} • ${a['masked_reference']}')))),
  const Padding(padding:EdgeInsets.all(10),child:Text('Account references are bookkeeping identifiers. Do not enter passwords or API keys.')),
  ]));
}

class V11TradingPage extends StatefulWidget{const V11TradingPage({super.key,required this.request});final V11Request request;
 @override State<V11TradingPage> createState()=>_V11TradingPageState();}
class _V11TradingPageState extends State<V11TradingPage>{
 bool loading=true,busy=false;String search='';List<Map<String,dynamic>> lots=[],sales=[],accounts=[];Map<String,dynamic> summary={};
 final selected=<String,TextEditingController>{};
 @override void initState(){super.initState();refresh();}
 @override void dispose(){for(final c in selected.values){c.dispose();}super.dispose();}
 Future<void> refresh()async{try{
  final r=await Future.wait([widget.request('GET','/v1/v11/trades/summary'),widget.request('GET','/v1/v11/accounts')]);
  if(mounted)setState((){summary=r[0];lots=v11List(r[0]['lots']);sales=v11List(r[0]['sales']);accounts=v11List(r[1]['accounts']);loading=false;});
 }catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'Trading sync: $e');}}}
 Future<void> buy()async{
  final cur=await v11Choose(context,'Buy USDT using',['AED','PKR']);if(cur==null)return;
  final paid=await v11Prompt(context,'Amount paid ($cur)');if(paid==null)return;
  final qty=await v11Prompt(context,'USDT received');if(qty==null)return;
  final fee=await v11Prompt(context,'Buying fee',initial:'0');if(fee==null)return;
  final payment=await _account('Paying Account',cur);if(payment=='CANCEL')return;
  final receipt=await _account('Receiving Crypto Account','USDT');if(receipt=='CANCEL')return;
  final counter=await v11Prompt(context,'P2P Counterparty (optional)');if(counter==null)return;
  final reference=await v11Prompt(context,'Reference / Order ID');if(reference==null)return;
  final executedAt=await v11Prompt(context,'Buying Date & Time (UTC ISO)',initial:v11Now());if(executedAt==null)return;
  final isTest=await v11Confirm(context,'Test Entry?','Choose Confirm to label this as TEST data. Cancel means record as REAL.');
  if(!mounted)return;
  try{setState(()=>busy=true);await widget.request('POST','/v1/v11/trades/buy',{
   'buy_currency':cur,'spent':paid,'bought_usdt':qty,'fee':fee,'paying_account_id':payment,
   'receiving_account_id':receipt,'counterparty':counter,'reference':reference,'executed_at':executedAt,'is_test':isTest,
  });await refresh();if(mounted)v11Toast(context,'Purchase recorded');}
  catch(e){if(mounted)v11Toast(context,'Purchase failed: $e');}finally{if(mounted)setState(()=>busy=false);}
 }
 Future<String?> _account(String title,String currency)async{
  final choices=accounts.where((a)=>a['currency']==currency&&a['is_active']==1).toList();
  final item=await v11Choose(context,title,['None',...choices.map((a)=>'${a['id']} | ${a['label']}')]);
  if(item==null)return 'CANCEL';return item=='None'?null:item.split(' | ').first;
 }
 int get sumMicros{int n=0;for(final e in selected.entries){
  final m=RegExp(r'^(\d+)(?:\.(\d{1,6}))?$').firstMatch(e.value.text.trim());
  if(m!=null)n+=int.parse(m.group(1)!)*1000000+int.parse((m.group(2)??'').padRight(6,'0'));
 }return n;}
 String get sumUnits=>v11Format(sumMicros,'USDT');
 Future<void> sell()async{
  if(sumMicros<=0){v11Toast(context,'Select quantities from one or more lots.');return;}
  final items=<Map<String,dynamic>>[];
  for(final lot in lots){final id='${lot['id']}',c=selected[id];if(c==null||c.text.trim().isEmpty)continue;
    final n=double.tryParse(c.text.trim())??0;
    if(n<=0)continue;final available=NumberSafe.available(lot['remaining_usdt_micros']);
    if(n>available){v11Toast(context,'Quantity exceeds available USDT in one lot.');return;}
    items.add({'lot_id':id,'quantity':c.text.trim()});
  }
  if(items.isEmpty)return;
  final cur=await v11Choose(context,'Sell USDT for',['AED','PKR']);if(cur==null)return;
  final received=await v11Prompt(context,'Total amount received ($cur)');if(received==null)return;
  final fee=await v11Prompt(context,'Selling fee ($cur)',initial:'0');if(fee==null)return;
  final bank=await _account('Bank / Receiving Account',cur);if(bank=='CANCEL')return;
  final binance=await _account('Binance / Sending Account','USDT');if(binance=='CANCEL')return;
  final ref=await v11Prompt(context,'Bank / Binance Reference');if(ref==null)return;
  final counter=await v11Prompt(context,'Counterparty (optional)');if(counter==null)return;
  final executedAt=await v11Prompt(context,'Selling Date & Time (UTC ISO)',initial:v11Now());if(executedAt==null)return;
  final mixed=lots.any((lot)=>items.any((a)=>a['lot_id']==lot['id'])&&lot['buy_currency']!=cur);
  String? valuation;
  if(mixed){valuation=await v11Prompt(context,'AED to PKR Valuation Rate (optional)',label:'Rate for cross-currency profit calculation');
    if(valuation==null)return;}
  final isTest=await v11Confirm(context,'Label this Sale as TEST?',
    'Confirm means TEST data. Cancel means a REAL record.');
  if(!mounted)return;
  final ok=await v11Confirm(context,'Review Multi-Lot Sale',
    'Selling: $sumUnits\nLots selected: ${items.length}\nReceive: $received $cur\nFee: $fee $cur\nReference: $ref\n\nThis records a sale; no money or cryptocurrency is transferred.');
  if(!ok)return;
  try{setState(()=>busy=true);await widget.request('POST','/v1/v11/trades/sell',{
    'allocations':items,'total_usdt':v11Format(sumMicros,'USDT').split(' ').first,
    'sell_currency':cur,'received':received,'fee':fee,'receiving_account_id':bank,
    'sending_account_id':binance,'reference':ref,'counterparty':counter,'valuation_rate':valuation,'executed_at':executedAt,'is_test':isTest,
  });
   for(final c in selected.values){c.clear();}
   await refresh();if(mounted)v11Toast(context,'Combined sale recorded.');
  }catch(e){if(mounted)v11Toast(context,'Sale not saved: $e');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> reverse(Map<String,dynamic> sale)async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;final reason=await v11Prompt(context,'Correction / Reversal Reason');if(reason==null||reason.length<3)return;
  if(!mounted||!await v11Confirm(context,'Reverse Sale?','Restore USDT inventory and preserve the original sale history?'))return;
  try{await widget.request('POST','/v1/v11/trades/reverse',{'sale_id':sale['id'],'reason':reason,'confirm':'REVERSE_SALE'});await refresh();}
  catch(e){if(mounted)v11Toast(context,'Reverse failed: $e');}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('USDT Trading — v11'),
  actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):
  ListView(padding:const EdgeInsets.all(14),children:[
    Card(color:v11Pale,child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[
      const Text('Total Available USDT',style:TextStyle(fontSize:14)),
      Text(v11Format(summary['available_usdt_micros'],'USDT'),style:const TextStyle(fontSize:25,fontWeight:FontWeight.bold,color:v11Green)),
      ...v11List(summary['inventory']).map((x){
        final available=NumberSafe.available(x['available_micros']);
        final cost=((x['remaining_cost_minor'] as num?)?.toDouble()??0)/100;
        final rate=available>0?cost/available:0.0;
        return Text('${x['buy_currency']}: ${v11Format(x['available_micros'],'USDT')} • Avg cost ${v11Amount(rate,4)} ${x['buy_currency']}/USDT');
      }),
    ]))),
    FilledButton.icon(onPressed:busy?null:buy,icon:const Icon(Icons.add),label:const Text('Record USDT Purchase')),
    const SizedBox(height:16),const Text('Select purchase lots and quantities to sell',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    ...lots.where((lot)=>NumberSafe.available(lot['remaining_usdt_micros'])>0).map((lot){
      final id='${lot['id']}';final ctrl=selected.putIfAbsent(id,()=>TextEditingController());
      return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Purchased ${v11Format(lot['bought_usdt_micros'],'USDT')} • ${lot['buy_currency']}'),
        Text('Paid: ${v11Format(lot['spent_minor'], '${lot['buy_currency']}')}   Fee: ${v11Format(lot['buy_fee_minor'], '${lot['buy_currency']}')}'),
        Text('Buy rate: ${v11Amount(((lot['spent_minor'] as num?)?.toDouble()??0)/100/NumberSafe.available(lot['bought_usdt_micros']),4)} ${lot['buy_currency']}/USDT'),
        Text('Available: ${v11Format(lot['remaining_usdt_micros'],'USDT')}'),
        TextField(controller:ctrl,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Sell from this lot (USDT)',hintText:'0.000000'),onChanged:(_)=>setState((){})),
      ])));
    }),
    const SizedBox(height:8),Text('Total selected: $sumUnits',style:const TextStyle(fontWeight:FontWeight.bold)),
    FilledButton.icon(onPressed:busy||sumMicros<=0?null:sell,icon:const Icon(Icons.sell),label:const Text('Sell Selected USDT in One Transaction')),
    const SizedBox(height:18),const Text('Combined Sales',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Search Reference / Currency / Counterparty'),
      onChanged:(v)=>setState(()=>search=v.trim().toLowerCase())),
    ...sales.where((s)=>search.isEmpty||
       '${s['external_reference']} ${s['counterparty']} ${s['sell_currency']} ${s['id']}'.toLowerCase().contains(search)
    ).map((s)=>Card(child:ListTile(
      title:Text('${v11Format(s['sold_usdt_micros'],'USDT')} → ${v11Format(s['received_minor'], '${s['sell_currency']}')}'),
      subtitle:Text('Sell rate: ${v11Amount(((s['received_minor'] as num?)?.toDouble()??0)/100/NumberSafe.available(s['sold_usdt_micros']),4)} ${s['sell_currency']}/USDT\nProfit: ${s['realized_profit_minor']==null?'Not valued':v11Format(s['realized_profit_minor'],'${s['sell_currency']}')}\nFee: ${v11Format(s['fee_minor'], '${s['sell_currency']}')}\nCost AED: ${v11Format(s['cost_aed_minor'],'AED')} • Cost PKR: ${v11Format(s['cost_pkr_minor'],'PKR')}\n${s['executed_at']}'),
      isThreeLine:true,trailing:IconButton(tooltip:'Reverse sale',icon:const Icon(Icons.undo),onPressed:()=>reverse(s)),
    ))),
    const Text('Profit is calculated per sale in its sell currency. Cross-currency profit needs a recorded AED/PKR valuation rate.'),
  ]));
}
class NumberSafe{static double available(dynamic micros)=>((micros is num?micros.toDouble():double.tryParse('$micros')??0)/1000000);}

class V11PlansPage extends StatefulWidget{
 const V11PlansPage({super.key,required this.request,required this.owner});
 final V11Request request;final bool owner;
 @override State<V11PlansPage> createState()=>_V11PlansPageState();
}
class _V11PlansPageState extends State<V11PlansPage>{
 bool loading=true;List<Map<String,dynamic>> plans=[],investments=[],funding=[],accounts=[];
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{try{
  final r=await Future.wait([widget.request('GET','/v1/v11/plans'),widget.request('GET','/v1/v11/investments/terms'),
   widget.request('GET','/v1/v11/funding'),if(widget.owner)widget.request('GET','/v1/v11/accounts')]);
  if(mounted)setState((){plans=v11List(r[0]['plans']);investments=v11List(r[1]['investments']);funding=v11List(r[2]['funding']);
   if(widget.owner)accounts=v11List(r[3]['accounts']);loading=false;});
 }catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'$e');}}}
 Future<void> createPlan()async{
  final title=await v11Prompt(context,'Investment Plan Name');if(title==null)return;
  final cur=await v11Choose(context,'Plan Currency',['AED','PKR','USDT']);if(cur==null)return;
  final min=await v11Prompt(context,'Minimum Investment',initial:'1000.00');if(min==null)return;
  final days=await v11Prompt(context,'Duration (days)',initial:'30');if(days==null)return;
  final percent=await v11Prompt(context,'Profit Weight Percentage (0-100)',initial:'20');if(percent==null)return;
  try{
   final p=double.parse(percent);final minMinor=(double.parse(min)*(cur=='USDT'?1000000:100)).round();
   if(p<0||p>100||int.tryParse(days)==null)throw const FormatException('Invalid plan values');
   await widget.request('POST','/v1/v11/plans',{'title':title,'currency':cur,'min_amount_minor':minMinor,
     'duration_days':int.parse(days),'profit_share_bps':(p*100).round()});await refresh();
  }catch(e){if(mounted)v11Toast(context,'$e');}
 }
 Future<void> updatePercentage(Map<String,dynamic> p)async{
  final current=(p['profit_share_bps'] is num?(p['profit_share_bps'] as num).toDouble()/100:0).toStringAsFixed(2);
  final value=await v11Prompt(context,'Set Profit Weight %',initial:current);if(value==null)return;
  try{final percent=double.parse(value);if(percent<0||percent>100)throw const FormatException('Percentage out of range');
   if(!mounted||!await v11Confirm(context,'Confirm New Plan Percentage',
    'Change ${p['title']} from $current% to $percent%?\nExisting investment terms remain locked.'))return;
   await widget.request('POST','/v1/v11/plans/percent',{'plan_id':p['plan_id'],'profit_share_bps':(percent*100).round()});await refresh();
  }catch(e){if(mounted)v11Toast(context,'$e');}
 }
 Future<void> lockTerms(Map<String,dynamic> i)async{
  final override=i['profit_share_bps']!=null;
  if(override&&!await v11Reauth(context))return;
  if(!mounted||!await v11Confirm(context,'Confirm Plan Percentage',override?
   'Apply the current plan percentage to this existing investment?':'Lock this investment to the current plan percentage?'))return;
  try{await widget.request('POST','/v1/v11/investments/terms',{'investment_id':i['investment_id'],'override':override});await refresh();}
  catch(e){if(mounted)v11Toast(context,'$e');}
 }
 Future<void> recordFunding(Map<String,dynamic> i)async{
  final cur='${i['currency']}';if(cur=='USDT'){v11Toast(context,'Select a bank-funded AED/PKR investment.');return;}
  final amount=await v11Prompt(context,'Received in Bank ($cur)');if(amount==null)return;
  final bankOptions=accounts.where((a)=>a['currency']==cur&&a['kind']=='bank').toList();
  final choice=await v11Choose(context,'Bank Account',['Not linked',...bankOptions.map((a)=>'${a['id']} | ${a['label']}')]);if(choice==null)return;
  final ref=await v11Prompt(context,'Bank Transfer Reference');if(ref==null)return;
  final date=v11Now();
  if(!mounted||!await v11Confirm(context,'Confirm Manual Bank Receipt',
    'Investment: ${i['investment_id']}\nAmount: $amount $cur\nBank: $choice\nReference: $ref\nDate: $date\n\nOnly a record is created.'))return;
  try{await widget.request('POST','/v1/v11/funding',{'investment_id':i['investment_id'],
    'amount':amount,'bank_account_id':choice=='Not linked'?null:choice.split(' | ').first,
    'reference':ref,'paid_at':date});await refresh();}catch(e){if(mounted)v11Toast(context,'$e');}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Investment Plans & Terms')),
  body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
   if(widget.owner)FilledButton.icon(onPressed:createPlan,icon:const Icon(Icons.add),label:const Text('Create Investment Plan')),
   const SizedBox(height:14),const Text('Investment Plans',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
   ...plans.map((p)=>Card(child:ListTile(title:Text('${p['title']} • ${p['currency']}'),
    subtitle:Text('Profit weight: ${p['profit_share_bps']==null?'Not configured':v11Amount((p['profit_share_bps'] as num).toDouble()/100)}%\nMinimum: ${v11Format(p['min_amount_minor'],'${p['currency']}')} • ${p['duration_days']} days'),
    trailing:widget.owner?IconButton(icon:const Icon(Icons.edit),onPressed:()=>updatePercentage(p)):null))),
   const SizedBox(height:14),const Text('Investment Terms',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
   ...investments.map((i)=>Card(child:Column(children:[ListTile(
    title:Text('${i['full_name']} • ${i['title']}'),
    subtitle:Text('Principal: ${v11Format(i['principal_minor'],'${i['currency']}')}\nLocked profit weight: ${i['profit_share_bps']==null?'Not set':v11Amount((i['profit_share_bps'] as num).toDouble()/100)}%'),
   ),if(widget.owner)Wrap(spacing:8,children:[
    TextButton(onPressed:()=>lockTerms(i),child:Text(i['profit_share_bps']==null?'Lock Plan Terms':'Update Locked Terms')),
    TextButton(onPressed:()=>recordFunding(i),child:const Text('Record Bank Receipt')),
   ])]))),
   const SizedBox(height:12),Text('Bank receipts logged: ${funding.length}'),
   if(widget.owner)const Text('Distribution uses the existing 50% customer pool. Plan percentages weight allocations by principal; they are not guaranteed daily returns.'),
  ]));
}

class V11ReportsPage extends StatefulWidget{const V11ReportsPage({super.key,required this.request});final V11Request request;
 @override State<V11ReportsPage> createState()=>_V11ReportsPageState();}
class _V11ReportsPageState extends State<V11ReportsPage>{
 String period='today';bool loading=true;Map<String,dynamic> report={};List<Map<String,dynamic>> profitPeriods=[];
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{
  try{final r=await Future.wait([widget.request('GET','/v1/v11/reports?period=$period'),widget.request('GET','/v1/pnl')]);
   if(mounted)setState((){report=r[0];profitPeriods=v11List(r[1]['periods']);loading=false;});
  }catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'Report: $e');}}
 }
 Future<void> distribute(Map<String,dynamic> p)async{
  if(!await v11Reauth(context))return;
  if(!mounted||!await v11Confirm(context,'Distribute Customer Profit Pool?',
   'Apply plan-weighted allocation only to the already verified 50% customer pool for this period? Existing allocations cannot be repeated.'))return;
  try{await widget.request('POST','/v1/v11/profit/distribute',{'period_id':p['period_id']});await refresh();}
  catch(e){if(mounted)v11Toast(context,'Distribution rejected: $e');}
 }
 Future<void> exportPdf()async{
  try{
   final doc=pw.Document();final a=report['by_currency'] is Map?report['by_currency'] as Map:{};
   doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(context)=>[
    pw.Header(level:0,text:'Sarmaya Plus v11 - Trading Record Report'),
    pw.Text('Period: $period   Timezone: Asia/Dubai'),
    pw.SizedBox(height:12),
    for(final currency in ['AED','PKR'])pw.Text('$currency realized profit/loss: ${v11Format(a[currency]?['realized_profit_minor'],currency)}'),
    pw.SizedBox(height:8),pw.Text('Profit includes cross-currency sales only when a valuation rate was saved.'),
    pw.Text('This is a bookkeeping statement, not proof of bank or cryptocurrency transfer.'),
   ]));
   await Printing.sharePdf(bytes:await doc.save(),filename:'Sarmaya_Plus_v11_${period}_report.pdf');
  }catch(e){if(mounted)v11Toast(context,'PDF unavailable: $e');}
 }
 @override Widget build(BuildContext context){final values=report['by_currency'] is Map?report['by_currency'] as Map:{};
  return Scaffold(appBar:AppBar(title:const Text('Profit & Loss Reports'),actions:[
   IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),
   body:ListView(padding:const EdgeInsets.all(14),children:[
    Wrap(spacing:6,children:['today','week','month','year','all'].map((p)=>ChoiceChip(label:Text(p),selected:period==p,
      onSelected:(_){setState((){period=p;loading=true;});refresh();})).toList()),
    if(loading)const LinearProgressIndicator(),
    ...['AED','PKR'].map((c)=>Card(color:v11Pale,child:ListTile(
      title:Text('Realized P/L • $c'),subtitle:Text('${values[c]?['trades']??0} valued sales'),
      trailing:Text(v11Format(values[c]?['realized_profit_minor'],c),style:const TextStyle(fontWeight:FontWeight.bold))))),
    const Text('Daily, weekly, monthly and yearly periods use Dubai local time. Currency totals are never mixed.'),
    FilledButton.icon(onPressed:exportPdf,icon:const Icon(Icons.picture_as_pdf),label:const Text('Export Report as PDF')),
    const SizedBox(height:16),const Text('Verified Profit Periods (50% Customers / 30% Owner / 20% Reserve)',
     style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    ...profitPeriods.map((p)=>Card(child:Column(children:[ListTile(
      title:Text('Period ${p['period_id']} • ${p['currency']}'),
      subtitle:Text('Net: ${v11Format(p['realized_net_minor'],'${p['currency']}')}\nCustomer pool: ${v11Format(p['users_share_minor'],'${p['currency']}')} • Allocated: ${v11Format(p['allocated_minor'],'${p['currency']}')}'),
    ),if((p['users_share_minor'] as num? ?? 0)>0&&(p['allocated_minor'] as num? ?? 0)==0)
      TextButton(onPressed:()=>distribute(p),child:const Text('Distribute with Locked Plan Percentages'))]))),
   ]));
 }
}

class V11PreferencesPage extends StatefulWidget {const V11PreferencesPage({super.key,required this.request});final V11Request request;
 @override State<V11PreferencesPage> createState()=>_V11PreferencesPageState();}
class _V11PreferencesPageState extends State<V11PreferencesPage>{
 String language='en',theme='system';bool notifications=true,saveLogin=true,loading=true;
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{try{final r=await widget.request('GET','/v1/v11/preferences');
  final p=r['preferences'];final pref=await SharedPreferences.getInstance();
  if(mounted)setState((){language='${p['language']??'en'}';theme='${p['theme']??'system'}';notifications=p['notifications_enabled']==1;
   saveLogin=pref.getBool('v11_save_login')??true;loading=false;});
 }catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'$e');}}}
 Future<void> save()async{
  try{await widget.request('POST','/v1/v11/preferences',{'language':language,'theme':theme,'notifications_enabled':notifications});
   final p=await SharedPreferences.getInstance();await p.setBool('v11_save_login',saveLogin);
   if(!saveLogin){if(mounted)v11Toast(context,'Save Login disabled: signing out now.');await FirebaseAuth.instance.signOut();}
   else if(mounted)v11Toast(context,'Preferences saved');
  }catch(e){if(mounted)v11Toast(context,'$e');}
 }
 Future<void> resetPin()async{
  if(!await v11Reauth(context))return;
  final uid=FirebaseAuth.instance.currentUser?.uid;
  if(uid==null)return;
  await const FlutterSecureStorage().delete(key:'v11_pin_$uid');
  if(mounted)v11Toast(context,'App PIN reset. Sign out and back in to create a new PIN.');
 }
 Future<void> reset()async{
  if(!await v11Confirm(context,'Reset My Settings?','Reset only language, notification and theme settings; no money or account history changes.'))return;
  try{await widget.request('POST','/v1/v11/preferences/reset',{});
   final p=await SharedPreferences.getInstance();await p.setBool('v11_save_login',true);await refresh();}
  catch(e){if(mounted)v11Toast(context,'$e');}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Profile & App Settings')),
  body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
   DropdownButtonFormField<String>(value:language,decoration:const InputDecoration(labelText:'Language / زبان'),
    items:const [DropdownMenuItem(value:'en',child:Text('English')),DropdownMenuItem(value:'ur',child:Text('اردو'))],
    onChanged:(v)=>setState(()=>language=v??language)),const SizedBox(height:12),
   DropdownButtonFormField<String>(value:theme,decoration:const InputDecoration(labelText:'Theme'),
    items:const [DropdownMenuItem(value:'system',child:Text('System')),DropdownMenuItem(value:'light',child:Text('Light')),
     DropdownMenuItem(value:'dark',child:Text('Dark'))],onChanged:(v)=>setState(()=>theme=v??theme)),
   SwitchListTile(title:const Text('Notifications'),value:notifications,onChanged:(v)=>setState(()=>notifications=v)),
   SwitchListTile(title:const Text('Save Login Session'),subtitle:const Text('No password is stored. Turning off signs out.'),
    value:saveLogin,onChanged:(v)=>setState(()=>saveLogin=v)),
   FilledButton(onPressed:save,child:const Text('Save Settings')),
   OutlinedButton.icon(onPressed:reset,icon:const Icon(Icons.restart_alt),label:const Text('Reset Only My Settings')),
   OutlinedButton.icon(onPressed:resetPin,icon:const Icon(Icons.password),label:const Text('Reset App PIN After Password Confirmation')),
   const SizedBox(height:8),const Text('15-minute inactivity lock and fingerprint/PIN unlock are managed on this device. Account records remain in Cloudflare.'),
  ]));
}

class V11AdminToolsPage extends StatefulWidget {const V11AdminToolsPage({super.key,required this.request});final V11Request request;
 @override State<V11AdminToolsPage> createState()=>_V11AdminToolsPageState();}
class _V11AdminToolsPageState extends State<V11AdminToolsPage>{
 bool loading=true,busy=false;List<Map<String,dynamic>> approvals=[],devices=[],audit=[],staff=[],clients=[];
 Map<String,dynamic> policy={},release={};String? mostRecentBackupId;
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{
  try{final r=await Future.wait([
   widget.request('GET','/v1/v11/approvals'),widget.request('GET','/v1/v11/devices'),
   widget.request('GET','/v1/v11/audit'),widget.request('GET','/v1/v11/approvals/config'),
   widget.request('GET','/v1/v11/update/manifest'),widget.request('GET','/v1/remit/staff'),
   widget.request('GET','/v1/clients'),
  ]);
   if(mounted)setState((){approvals=v11List(r[0]['approvals']);devices=v11List(r[1]['devices']);audit=v11List(r[2]['events']);
    policy=r[3]['policy'] is Map?Map<String,dynamic>.from(r[3]['policy']):{};
    release=r[4];staff=v11List(r[5]['staff']);clients=v11List(r[6]['clients']);loading=false;});
  }catch(e){if(mounted){setState(()=>loading=false);v11Toast(context,'Admin sync: $e');}}
 }
 Future<void> run(Future<void> Function() fn)async{
  if(busy)return;setState(()=>busy=true);
  try{await fn();await refresh();if(mounted)v11Toast(context,'Saved / مکمل');}
  catch(e){if(mounted)v11Toast(context,'Operation failed: $e');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> exportBackup()async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;final password=await v11Prompt(context,'Backup Encryption Password (12+ chars)',secret:true);
  if(password==null||password.length<12){if(mounted)v11Toast(context,'Password must be 12+ characters.');return;}
  final confirm=await v11Prompt(context,'Repeat Backup Password',secret:true);if(confirm!=password){if(mounted)v11Toast(context,'Passwords do not match');return;}
  await run(()async{
   final result=await widget.request('POST','/v1/v11/backup/export',{'password':password});
   final data=result['encrypted'];if(data is! Map)throw Exception('Backup data missing');
   final dir=await getTemporaryDirectory();final id='${result['backup_id']}';
   final file=File('${dir.path}/SarmayaPlus_v11_Encrypted_Backup_$id.json');
   await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data),flush:true);
   mostRecentBackupId=id;
   await Share.shareXFiles([XFile(file.path)],text:'Encrypted Sarmaya Plus v11 backup. Store privately; keep password separately.');
  });
 }
 Future<void> importBackup()async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;
  final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json'],withData:true);
  if(picked==null||picked.files.isEmpty)return;
  final path=picked.files.single.path,bytes=picked.files.single.bytes;
  if(bytes==null&&path==null){v11Toast(context,'File cannot be read');return;}
  final content=bytes!=null?utf8.decode(bytes):await File(path!).readAsString();
  if(content.length>2200000){if(mounted)v11Toast(context,'Backup exceeds import limit. Use D1 restore.');return;}
  Map<String,dynamic> data;
  try{data=Map<String,dynamic>.from(jsonDecode(content) as Map);}catch(_){if(mounted)v11Toast(context,'Invalid backup JSON');return;}
  if(!mounted)return;final password=await v11Prompt(context,'Backup Password',secret:true);if(password==null)return;
  try{final preview=await widget.request('POST','/v1/v11/backup/preview',{'encrypted':data,'password':password});
   if(!mounted)return;
   final ok=await v11Confirm(context,'Preview — Import Backup',
     'Backup ID: ${preview['backup_id']}\nSections: ${preview['counts']}\n\n'
     'Choose Safe Merge (account directory/preferences) or Restore Trading (only into empty trading records). '
     'Other legacy customer and investment records require Cloudflare D1 full backup.\nContinue?');
   if(!ok)return;
   if(!mounted)return;
   final mode=await v11Choose(context,'Import Type',[
     'Safe Merge (Accounts / Preferences)','Restore Trading (Empty Workspace Only)'
   ]);
   if(mode==null)return;
   if(mode.startsWith('Safe')){
     await run(()async{await widget.request('POST','/v1/v11/backup/import',{'encrypted':data,'password':password,'mode':'merge'});});
   }else{
     if(!mounted||!await v11Confirm(context,'Restore USDT Trading?',
       'Trading workspace must contain zero purchases or sales. All archived trades will be restored with original lot allocations.'))return;
     await run(()async{await widget.request('POST','/v1/v11/backup/restore-trades',{
       'encrypted':data,'password':password,'confirm':'RESTORE_TRADING_FROM_BACKUP'
     });});
   }
  }catch(e){if(mounted)v11Toast(context,'Import failed: $e');}
 }
 Future<void> resetDevice(Map<String,dynamic> d)async{
  if(!await v11Reauth(context))return;
  if(!mounted||!await v11Confirm(context,'Reset Phone Limit',
   'Allow this registered device to create up to two new accounts again? Existing customer accounts remain.'))return;
  await run(()async{await widget.request('POST','/v1/v11/reset/device',{'device_hash':d['device_hash'],'confirm':'RESET_DEVICE'});});
 }
 Future<void> resetUser(String uid,String type)async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;
  final title=type=='customer'?'Hold and Unlink Customer':type=='roles'?'Reset Staff Role':'Disable Staff Account';
  if(!await v11Confirm(context,title,'Target: $uid\nFinancial history will not be deleted.'))return;
  final route=type=='customer'?'/v1/v11/reset/customer':type=='roles'?'/v1/v11/reset/roles':'/v1/v11/reset/staff';
  final body=type=='customer'?{'client_id':uid,'confirm':'RESET_CUSTOMER_ACCESS'}:
    type=='roles'?{'user_uid':uid,'confirm':'RESET_ROLES'}:{'user_uid':uid,'confirm':'DISABLE_STAFF'};
  await run(()async{await widget.request('POST',route,body);});
 }
 Future<void> resetTestTrades()async{
  if(mostRecentBackupId==null){v11Toast(context,'Export an encrypted backup first in this session.');return;}
  if(!await v11Reauth(context))return;
  if(!mounted||!await v11Confirm(context,'Delete Tagged Test Trades',
   'Only records explicitly tagged TEST in v11 will be deleted. v10 older purchases without a test tag will remain.\n'
   'Backup: $mostRecentBackupId\n\nThis is irreversible inside the app.'))return;
  await run(()async{await widget.request('POST','/v1/v11/reset/test-trades',{
    'confirm':'DELETE_TEST_TRADES','backup_id':mostRecentBackupId,
  });});
 }
 Future<void> resetAllTrading()async{
  if(mostRecentBackupId==null){v11Toast(context,'Export and save an encrypted backup first.');return;}
  if(!await v11Reauth(context))return;
  if(!mounted||!await v11Confirm(context,'CLEAR ALL USDT TRADING DATA',
    'This clears ALL recorded USDT purchases and sales, including old v10 test records, but keeps investor accounts and profile data.\n'
    'Backup: $mostRecentBackupId\n\nYou can later restore trades into an empty workspace from the saved encrypted backup.'))return;
  if(!mounted)return;final phrase=await v11Prompt(context,'Type CLEAR ALL TRADING');
  if(phrase!='CLEAR ALL TRADING'){v11Toast(context,'Confirmation phrase did not match.');return;}
  await run(()async{await widget.request('POST','/v1/v11/reset/all-trading',{
    'backup_id':mostRecentBackupId,'confirm':'CLEAR_ALL_TRADING',
  });});
 }
 Future<void> setApprovalPolicy()async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;
  final enabled=await v11Choose(context,'Staff Approval Policy',['Enabled','Disabled']);if(enabled==null)return;
  final a=await v11Prompt(context,'AED Approval Threshold',initial:v11Format(policy['threshold_aed_minor'],'AED').split(' ').first);if(a==null)return;
  final k=await v11Prompt(context,'PKR Approval Threshold',initial:v11Format(policy['threshold_pkr_minor'],'PKR').split(' ').first);if(k==null)return;
  await run(()async{await widget.request('POST','/v1/v11/approvals/config',{
    'enabled':enabled=='Enabled','threshold_aed':a,'threshold_pkr':k,
  });});
 }
 Future<void> decideApproval(Map<String,dynamic> a)async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;
  final status=await v11Choose(context,'Review Approval Request',['approved','rejected']);if(status==null)return;
  await run(()async{await widget.request('POST','/v1/v11/approvals/review',{'id':a['id'],'status':status});});
 }
 Future<void> publishRelease()async{
  if(!await v11Reauth(context))return;
  if(!mounted)return;
  final version=await v11Prompt(context,'Version Name',initial:'${release['latest_version']??'11.0.0'}');if(version==null)return;
  final build=await v11Prompt(context,'Latest APK Build Number',initial:'${release['latest_build']??0}');if(build==null)return;
  final link=await v11Prompt(context,'GitHub Release APK HTTPS URL',initial:'${release['apk_url']??''}');if(link==null)return;
  final kind=await v11Choose(context,'Update Type',['Optional','Required']);if(kind==null)return;
  final min=kind=='Required'?build:'0';
  final notes=await v11Prompt(context,'Release Notes',initial:'${release['notes']??''}');if(notes==null)return;
  if(!mounted||!await v11Confirm(context,'Publish App Update',
    'Version $version • Build $build\n$kind\nURL: $link\n\nRequired will block older app builds. Publish only after testing a downloadable, signed APK.'))return;
  await run(()async{await widget.request('POST','/v1/v11/update/publish',{
   'latest_version':version,'latest_build':int.parse(build),'min_build':int.parse(min),'apk_url':link,'notes':notes,
  });});
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Super Admin — Backup & Reset'),
  actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):
  ListView(padding:const EdgeInsets.all(14),children:[
   const Text('Encrypted Backup & Restore',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   const Text('Keep a full Cloudflare D1 backup separately. In-app Import supports account/settings merge or trading restore into an empty workspace.'),
   FilledButton.icon(onPressed:busy?null:exportBackup,icon:const Icon(Icons.download),label:const Text('Export Encrypted Backup')),
   OutlinedButton.icon(onPressed:busy?null:importBackup,icon:const Icon(Icons.upload_file),label:const Text('Import & Preview Backup')),
   const Divider(height:32),const Text('App Update Publishing',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ListTile(title:Text('${release['latest_version']??''} — build ${release['latest_build']??0}'),
    subtitle:Text('Minimum supported build: ${release['min_build']??0}')),
   FilledButton.icon(onPressed:busy?null:publishRelease,icon:const Icon(Icons.system_update),label:const Text('Publish Optional / Required Update')),
   const Divider(height:32),const Text('Staff Transaction Approvals',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ListTile(title:Text('Policy: ${policy['enabled']==1?'Enabled':'Disabled'}'),
    subtitle:Text('AED: ${v11Format(policy['threshold_aed_minor'],'AED')} • PKR: ${v11Format(policy['threshold_pkr_minor'],'PKR')}')),
   OutlinedButton(onPressed:busy?null:setApprovalPolicy,child:const Text('Set Approval Thresholds')),
   ...approvals.where((a)=>a['status']=='pending').map((a)=>Card(child:ListTile(
    title:Text('${a['kind']} — ${a['target_id']}'),subtitle:Text('${a['description']}\n${a['requested_by']}'),
    trailing:IconButton(icon:const Icon(Icons.task_alt),onPressed:()=>decideApproval(a))))),
   const Divider(height:32),const Text('Advanced Reset Center',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   const Text('Each action requires recent Super Admin authentication. Financial records are not deleted by customer/staff access resets.'),
   ...devices.map((d)=>Card(child:ListTile(
    title:Text("Device: ${d['device_hash'].toString().substring(0,12)}…"),subtitle:Text('Accounts created: ${d['registrations']}'),
    trailing:IconButton(icon:const Icon(Icons.restart_alt),tooltip:'Reset phone registration limit',onPressed:()=>resetDevice(d))))),
   ...staff.map((s)=>Card(child:ListTile(
    title:Text('Staff: ${s['display_name']}'),subtitle:Text('${s['email']} • ${s['role']}'),
    trailing:PopupMenuButton<String>(onSelected:(action)=>resetUser('${s['user_uid']}',action),
      itemBuilder:(_)=>const [PopupMenuItem(value:'staff',child:Text('Disable Staff')),
       PopupMenuItem(value:'roles',child:Text('Reset Role'))])))),
   ...clients.map((c)=>Card(child:ListTile(
    title:Text('${c['full_name']}'),subtitle:Text('Customer: ${c['id']}'),
    trailing:IconButton(icon:const Icon(Icons.person_off_outlined),tooltip:'Reset customer access',onPressed:()=>resetUser('${c['id']}','customer'))))),
   OutlinedButton.icon(onPressed:busy?null:resetTestTrades,icon:const Icon(Icons.cleaning_services),
    label:const Text('Reset All Tagged Test Trades')),
   OutlinedButton.icon(onPressed:busy?null:resetAllTrading,icon:const Icon(Icons.delete_sweep_outlined),
    label:const Text('Clear All USDT Trading Records (Backup Required)')),
   const Text('Reset All financial records is intentionally disabled in the app until a complete verified D1 restore path exists. Use Cloudflare D1 Time Travel for full database recovery.'),
   const Divider(height:32),const Text('Audit Log',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ...audit.take(30).map((e)=>ListTile(title:Text('${e['action']} • ${e['target_type']}'),
    subtitle:Text('${e['created_at']} • ${e['actor_uid']}'))),
  ]));
}

Future<void> v11ShareOrderPdf(Map<String,dynamic> order)async{
 final sender=order['sender'] is Map?order['sender'] as Map:{};
 final receiver=order['receiver'] is Map?order['receiver'] as Map:{};
 final doc=pw.Document();
 doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(context)=>[
   pw.Header(level:0,text:'SARMAYA PLUS - TRANSFER ORDER RECORD'),
   pw.Text('Reference: ${order['order_number']??''}'),
   pw.Text('Created: ${order['created_at']??''}'),
   pw.Text('Status: ${order['status']??''}'),
   pw.Divider(),
   pw.Text('Sender: ${sender['full_name']??''}'),
   pw.Text('Sender phone: ${sender['phone']??''}'),
   pw.Text('Receiver: ${receiver['full_name']??''}'),
   pw.Text('Receiver phone: ${receiver['phone']??''}'),
   pw.Text('Bank/wallet: ${receiver['bank_or_wallet_name']??''}'),
   pw.Text('Receiving reference: ${receiver['account_reference']??''}'),
   pw.Text('Send: ${v11Format(order['aed_minor'],'AED')}'),
   pw.Text('Receive: ${v11Format(order['pkr_minor'],'PKR')}'),
   pw.Text('Rate: ${order['published_rate']??''} PKR/AED'),
   pw.Text('Payment: ${order['payment_method']??''}'),
   pw.SizedBox(height:16),
   pw.Text('Recordkeeping document only. It is not bank receipt or proof of funds delivery.'),
 ]));
 await Printing.sharePdf(bytes:await doc.save(),filename:'Sarmaya_Order_${order['order_number']??'record'}.pdf');
}

Future<void> v11ShareCustomerStatementPdf(Map<String,dynamic> client,List<Map<String,dynamic>> entries)async{
 final currency='${client['currency']??'AED'}';final doc=pw.Document();
 doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(context)=>[
  pw.Header(level:0,text:'SARMAYA PLUS - CUSTOMER STATEMENT'),
  pw.Text('Customer: ${client['full_name']??''}'),
  pw.Text('Customer ID: ${client['id']??''}'),
  pw.Text('Recorded balance: ${v11Format(client['balance_minor'],currency)}'),
  pw.Text('Generated: ${DateTime.now().toUtc().toIso8601String()} UTC'),
  pw.SizedBox(height:12),
  pw.Table.fromTextArray(headers:['Date','Type','Amount','Note'],data:entries.take(100).map((e)=>[
   '${e['created_at']??''}','${e['kind']??''}',v11Format(e['amount_minor'],currency),'${e['note']??''}',
  ]).toList()),
  pw.SizedBox(height:12),pw.Text('Manual account statement; not a bank-generated transaction certificate.'),
 ]));
 await Printing.sharePdf(bytes:await doc.save(),filename:'Sarmaya_Customer_Statement.pdf');
}
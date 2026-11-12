import 'v11_features.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef V9ApiRequest = Future<Map<String, dynamic>> Function(
    String method, String path, [Map<String, dynamic>? body]);

const Color v9Green = Color(0xFF123F2B);
const Color v9Light = Color(0xFFEAF3EC);

List<Map<String, dynamic>> _v9Rows(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : <Map<String, dynamic>>[];
String _v9Value(dynamic v) => v == null ? '' : '$v';
String _v9Money(dynamic minor, String currency) {
  final value = (minor is num ? minor.toInt() : int.tryParse('$minor') ?? 0);
  final units = currency == 'USDT' ? 1000000 : 100;
  return '${value < 0 ? '-' : ''}${value.abs() ~/ units}.${(value.abs() % units).toString().padLeft(currency == 'USDT' ? 6 : 2, '0')} $currency';
}
String _v9Rate(dynamic n) => n is num ? (n / 10000).toStringAsFixed(4) : '—';
String _v9Number(double n) => n.isFinite ? n.toStringAsFixed(2) : '';
String _v9TradeOutcome(Map<String, dynamic> sale) {
  if (sale['same_currency_profit_minor'] != null) {
    return 'Recorded P/L: ${_v9Money(sale['same_currency_profit_minor'], _v9Value(sale['buy_currency']))}';
  }
  final rate = sale['implied_aed_to_pkr_rate'];
  return 'Implied AED→PKR Rate: ${rate is num ? rate.toStringAsFixed(4) : '—'}';
}


class TransferCustomerPage extends StatefulWidget {
  const TransferCustomerPage({super.key, required this.request});
  final V9ApiRequest request;
  @override
  State<TransferCustomerPage> createState() => _TransferCustomerPageState();
}

class _TransferCustomerPageState extends State<TransferCustomerPage> {
  final aed = TextEditingController(text: '360');
  final pkr = TextEditingController();
  double? rate;
  int rateVersion = 0;
  bool loading = true, busy = false;
  String? error;
  String inputCurrency = 'AED';
  List<Map<String, dynamic>> senders = [], receivers = [], orders = [];

  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { aed.dispose(); pkr.dispose(); super.dispose(); }
  void info(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final data = await Future.wait([
        widget.request('GET', '/v1/remit/rate'),
        widget.request('GET', '/v1/remit/senders'),
        widget.request('GET', '/v1/remit/receivers'),
        widget.request('GET', '/v1/remit/orders'),
      ]);
      if (!mounted) return;
      setState(() {
        rate = double.tryParse(_v9Value(data[0]['published_rate']));
        rateVersion = (data[0]['rate_version'] as num?)?.toInt() ?? 0;
        senders = _v9Rows(data[1]['senders']);
        receivers = _v9Rows(data[2]['receivers']);
        orders = _v9Rows(data[3]['orders']);
      });
      updateAmounts(inputCurrency == 'AED');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally { if (mounted) setState(() => loading = false); }
  }
  void updateAmounts(bool fromAed) {
    inputCurrency = fromAed ? 'AED' : 'PKR';
    final r = rate;
    if (r == null || r <= 0) return;
    if (fromAed) {
      final value = double.tryParse(aed.text.trim());
      pkr.text = value == null || value <= 0 ? '' : _v9Number(value * r);
    } else {
      final value = double.tryParse(pkr.text.trim());
      aed.text = value == null || value <= 0 ? '' : _v9Number(value / r);
    }
    if (mounted) setState(() {});
  }
  Future<String?> ask(String title, {String initial = '', String hint = ''}) async {
    final ctrl = TextEditingController(text: initial);
    try {
      return await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 1,
          decoration: InputDecoration(labelText: hint.isEmpty ? title : hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ));
    } finally { ctrl.dispose(); }
  }
  Future<String?> choose(String title, List<String> values) async =>
    showDialog<String>(context: context, builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: values.map((s) => SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, s),
        child: Padding(padding: const EdgeInsets.all(10), child: Text(s)),
      )).toList(),
    ));
  Future<bool> confirm(String title, String details) async =>
    await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title), content: SingleChildScrollView(child: Text(details)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Edit / Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Order')),
      ],
    )) ?? false;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try { await action(); await refresh(); info('Saved successfully / محفوظ ہوگیا'); }
    catch (e) { info('Not saved: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> senderForm([Map<String, dynamic>? current]) async {
    final name = TextEditingController(text: _v9Value(current?['full_name']));
    final phone = TextEditingController(text: _v9Value(current?['phone']));
    final country = TextEditingController(text: _v9Value(current?['country']).isEmpty ? 'UAE' : _v9Value(current?['country']));
    final address = TextEditingController(text: _v9Value(current?['address']));
    try {
      final data = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
        title: Text(current == null ? 'Add Sender' : 'Edit Sender'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Sender Full Name')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
          const SizedBox(height: 10),
          TextField(controller: country, decoration: const InputDecoration(labelText: 'Country')),
          const SizedBox(height: 10),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Address (optional)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'full_name': name.text.trim(), 'phone': phone.text.trim(),
            'country': country.text.trim(), 'address': address.text.trim(),
          }), child: const Text('Save')),
        ],
      ));
      if (data == null) return;
      if (data['full_name']!.length < 2 || data['phone']!.length < 5) { info('Enter valid sender name and phone.'); return; }
      await run(() async { await widget.request('POST', '/v1/remit/senders', {
        ...data, if (current != null) 'id': current['id'],
      }); });
    } finally { name.dispose(); phone.dispose(); country.dispose(); address.dispose(); }
  }

  Future<void> receiverForm([Map<String, dynamic>? current]) async {
    final name = TextEditingController(text: _v9Value(current?['full_name']));
    final phone = TextEditingController(text: _v9Value(current?['phone']));
    final country = TextEditingController(text: _v9Value(current?['country']).isEmpty ? 'Pakistan' : _v9Value(current?['country']));
    final bank = TextEditingController(text: _v9Value(current?['bank_or_wallet_name']));
    final account = TextEditingController(text: _v9Value(current?['account_reference']));
    String method = _v9Value(current?['method']).isEmpty ? 'bank' : _v9Value(current?['method']);
    try {
      final data = await showDialog<Map<String, String>>(context: context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: Text(current == null ? 'Add Receiver' : 'Edit Receiver'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Receiver Full Name')),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
            const SizedBox(height: 10),
            TextField(controller: country, decoration: const InputDecoration(labelText: 'Country')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: method,
              decoration: const InputDecoration(labelText: 'Receiving Method'),
              items: const [
                DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                DropdownMenuItem(value: 'wallet', child: Text('Mobile Wallet')),
                DropdownMenuItem(value: 'cash_pickup', child: Text('Cash Pickup')),
              ], onChanged: (v) { if (v != null) change(() => method = v); }),
            if (method != 'cash_pickup') ...[
              const SizedBox(height: 10),
              TextField(controller: bank, decoration: const InputDecoration(labelText: 'Bank / Wallet Name')),
              const SizedBox(height: 10),
              TextField(controller: account, decoration: const InputDecoration(labelText: 'Account / IBAN / Wallet Number')),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, {
              'full_name': name.text.trim(), 'phone': phone.text.trim(),
              'country': country.text.trim(), 'method': method,
              'bank_or_wallet_name': method == 'cash_pickup' ? '' : bank.text.trim(),
              'account_reference': method == 'cash_pickup' ? '' : account.text.trim(),
            }), child: const Text('Save')),
          ],
        ),
      ));
      if (data == null) return;
      if (data['full_name']!.length < 2 || data['phone']!.length < 5 ||
          (data['method'] != 'cash_pickup' && (data['bank_or_wallet_name']!.isEmpty || data['account_reference']!.isEmpty))) {
        info('Enter receiver name, phone and account details.'); return;
      }
      await run(() async { await widget.request('POST', '/v1/remit/receivers', {
        ...data, if (current != null) 'id': current['id'],
      }); });
    } finally { name.dispose(); phone.dispose(); country.dispose(); bank.dispose(); account.dispose(); }
  }

  Future<void> placeOrder() async {
    if (rate == null || rate! <= 0) { info('Published exchange rate is not available.'); return; }
    if (senders.isEmpty || receivers.isEmpty) { info('Add Sender and Receiver first.'); return; }
    final input = inputCurrency == 'AED' ? aed.text.trim() : pkr.text.trim();
    final amount = double.tryParse(input);
    if (amount == null || amount <= 0 || amount > 1000000000 || !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) {
      info('Enter a valid amount (maximum 2 decimal places).'); return;
    }
    final sid = await choose('Select Sender', senders.map((s) => '${s['id']}  •  ${s['full_name']}').toList());
    if (sid == null) return;
    final sender = senders.firstWhere((s) => sid.startsWith('${s['id']}'));
    final rid = await choose('Select Receiver', receivers.map((r) => '${r['id']}  •  ${r['full_name']}').toList());
    if (rid == null) return;
    final receiver = receivers.firstWhere((r) => rid.startsWith('${r['id']}'));
    final method = await choose('How will you pay AED?', ['cash', 'bank_transfer', 'cash_deposit']);
    if (method == null) return;
    final note = await ask('Order Note (optional)', hint: 'Message / reference');
    if (note == null) return;
    final isAed = inputCurrency == 'AED';
    final a = isAed ? amount : amount / rate!;
    final p = isAed ? amount * rate! : amount;
    final ok = await confirm('Review Sender & Receiver',
      'Sender: ${sender['full_name']}\nPhone: ${sender['phone']}\nCountry: ${sender['country']}\n\n'
      'Receiver: ${receiver['full_name']}\nPhone: ${receiver['phone']}\nMethod: ${receiver['method']}\n'
      'Bank / Wallet: ${receiver['bank_or_wallet_name']}\nAccount: ${receiver['account_reference']}\n\n'
      'Payment: $method\nSend: ${_v9Number(a)} AED\nReceive: ${_v9Number(p)} PKR\n'
      'Published rate: ${rate!.toStringAsFixed(4)} PKR per AED\n\n'
      'Confirm that sender, receiver, method and amounts are correct. This creates a request; it does not transfer money.');
    if (!ok) return;
    await run(() async {
      final result = await widget.request('POST', '/v1/remit/orders', {
        'sender_id': sender['id'], 'receiver_id': receiver['id'],
        'sender_revision': sender['revision'], 'receiver_revision': receiver['revision'],
        'payment_method': method, 'receiving_method': receiver['method'],
        'input_currency': inputCurrency, 'input_amount': input,
        'rate_version': rateVersion, 'note': note, 'confirm': true,
      });
      info('Order created: ${result['order_number']}');
    });
  }
  Future<void> setOrderStatus(Map<String, dynamic> order, String next) async {
    await run(() async { await widget.request('POST', '/v1/remit/orders/status', {
      'order_id': order['id'], 'status': next, 'note': next == 'payment_submitted' ? 'Payment submitted by customer' : 'Cancelled by customer',
    }); });
  }
  String orderReceipt(Map<String,dynamic> order) {
    final sender=order['sender'] is Map ? order['sender'] as Map : {};
    final receiver=order['receiver'] is Map ? order['receiver'] as Map : {};
    return 'SARMAYA PLUS — ORDER RECORD\n'
      'Reference: ${order['order_number']}\nDate: ${order['created_at']}\n'
      'Status: ${order['status']}\nSender: ${sender['full_name']} (${sender['phone']})\n'
      'Receiver: ${receiver['full_name']} (${receiver['phone']})\n'
      'Receiving: ${order['receiving_method']}\nBank/Wallet: ${receiver['bank_or_wallet_name']}\n'
      'Account: ${receiver['account_reference']}\n'
      'Payment: ${order['payment_method']}\n'
      'Send: ${_v9Money(order['aed_minor'],'AED')}\nReceive: ${_v9Money(order['pkr_minor'],'PKR')}\n'
      'Rate: ${order['published_rate']} PKR/AED\n'
      'This is an order status record; it is not proof that funds were delivered.';
  }
  Future<void> showHistory(Map<String, dynamic> order) async {
    try {
      final r = await widget.request('GET', '/v1/remit/orders/history?order_id=${order['id']}');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text('${order['order_number']} History'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          children: _v9Rows(r['history']).map((h) => ListTile(
            title: Text('${h['from_status'] ?? 'New'} → ${h['to_status']}'),
            subtitle: Text('${h['created_at']}  ${h['note'] ?? ''}'),
          )).toList())),
        actions: [
          TextButton(onPressed: () async {
            Navigator.pop(ctx);
            try{await v11ShareOrderPdf(order);}catch(e){info('PDF failed: $e');}
          },child:const Text('PDF Receipt')),
          TextButton(onPressed: () async {
            await Clipboard.setData(ClipboardData(text:orderReceipt(order)));
            if(ctx.mounted)Navigator.pop(ctx);
            info('Order details copied');
          }, child: const Text('Copy Order Record')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ));
    } catch (e) { info('$e'); }
  }
  Widget quoteView() => ListView(padding: const EdgeInsets.all(14), children: [
    const Text('AED → PKR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: v9Green)),
    const SizedBox(height: 10),
    Card(color: v9Light, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      const Text('Published Customer Rate'),
      const SizedBox(height: 5),
      Text(rate == null ? 'Not published yet' : '1 AED = ${rate!.toStringAsFixed(4)} PKR',
        style: const TextStyle(fontSize: 22, color: v9Green, fontWeight: FontWeight.bold)),
    ]))),
    const SizedBox(height: 14),
    TextField(controller: aed, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Send — AED', prefixIcon: Icon(Icons.currency_exchange)),
      onChanged: (_) => updateAmounts(true)),
    const SizedBox(height: 14),
    TextField(controller: pkr, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Receive — PKR', prefixIcon: Icon(Icons.payments_outlined)),
      onChanged: (_) => updateAmounts(false)),
    const SizedBox(height: 14),
    const Text('Change either amount. The other amount is calculated automatically.',
      style: TextStyle(color: Colors.black54)),
    const SizedBox(height: 18),
    FilledButton.icon(onPressed: busy || rate == null ? null : placeOrder,
      icon: const Icon(Icons.send), label: const Text('Continue / Create Order')),
    const SizedBox(height: 12),
    const Text('Only the rate published by the Admin is shown here. Quote is recalculated and locked when you confirm the order.'),
  ]);
  Widget peopleView(bool sender) {
    final list = sender ? senders : receivers;
    return ListView(padding: const EdgeInsets.all(14), children: [
      FilledButton.icon(onPressed: busy ? null : () => sender ? senderForm() : receiverForm(),
        icon: const Icon(Icons.person_add_alt), label: Text(sender ? 'Add Sender' : 'Add Receiver')),
      const SizedBox(height: 12),
      ...list.map((c) => Card(child: ListTile(
        leading: const Icon(Icons.person_outline, color: v9Green),
        title: Text('${c['full_name']}'),
        subtitle: Text('${c['phone']}\n${sender ? c['country'] : '${c['method']} • ${c['bank_or_wallet_name']}'}'),
        isThreeLine: true,
        trailing: IconButton(icon: const Icon(Icons.edit_outlined),
          onPressed: busy ? null : () => sender ? senderForm(c) : receiverForm(c)),
      ))),
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No saved profiles yet.')),
    ]);
  }
  Widget ordersView() => ListView(padding: const EdgeInsets.all(14), children: [
    ...orders.map((o) => Card(child: Column(children: [
      ListTile(title: Text('${o['order_number']}'),
        subtitle: Text('${o['status']}\n${o['created_at']}\n'
          '${_v9Money(o['aed_minor'], 'AED')} → ${_v9Money(o['pkr_minor'], 'PKR')}'),
        isThreeLine: true,
        onTap: () => showHistory(o),
        trailing: const Icon(Icons.history)),
      if (o['status'] == 'pending_payment') Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: busy ? null : () => setOrderStatus(o, 'payment_submitted'),
            child: const Text('Payment Submitted')),
          TextButton(onPressed: busy ? null : () => setOrderStatus(o, 'cancelled'), child: const Text('Cancel')),
        ])),
      if (o['status'] == 'payment_submitted') TextButton(onPressed: busy ? null : () => setOrderStatus(o, 'cancelled'),
        child: const Text('Request Cancellation')),
    ]))),
    if (orders.isEmpty) const Text('No orders yet.'),
    const SizedBox(height: 15),
    const Text('This page records requests and their statuses. It does not send funds.'),
  ]);
  @override
  Widget build(BuildContext context) => DefaultTabController(length: 4, child: Scaffold(
    appBar: AppBar(title: const Text('AED to PKR / Transfer'),
      actions: [IconButton(onPressed: loading ? null : refresh, icon: const Icon(Icons.refresh))],
      bottom: const TabBar(isScrollable: true, tabs: [
        Tab(text: 'Calculator'), Tab(text: 'Senders'), Tab(text: 'Receivers'), Tab(text: 'My Orders'),
      ])),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null
      ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min,
          children: [Text('Sync unavailable: $error'), const SizedBox(height: 12),
            FilledButton(onPressed: refresh, child: const Text('Retry'))])))
      : TabBarView(children: [quoteView(), peopleView(true), peopleView(false), ordersView()]),
  ));
}

class TransferAdminPage extends StatefulWidget {
  const TransferAdminPage({super.key, required this.request, required this.owner,
    this.openInvestors, this.openPersonal, this.openMode, this.openKyc});
  final V9ApiRequest request;
  final bool owner;
  final VoidCallback? openInvestors, openPersonal, openMode, openKyc;
  @override
  State<TransferAdminPage> createState() => _TransferAdminPageState();
}

class _TransferAdminPageState extends State<TransferAdminPage> {
  bool loading = true, busy = false;
  String? error, role;
  Map<String, dynamic> rateData = {};
  List<Map<String, dynamic>> lots = [], sales = [], orders = [], staff = [];
  @override
  void initState() { super.initState(); refresh(); }
  void info(String s) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final access = await widget.request('GET', '/v1/remit/access');
      final me = _v9Value(access['role']);
      if (me == 'customer') throw Exception('Staff access is not enabled for this account.');
      final data = await Future.wait([
        widget.request('GET', '/v1/remit/orders?scope=all'),
        if (widget.owner) widget.request('GET', '/v1/remit/rates/admin'),
        if (widget.owner) widget.request('GET', '/v1/remit/trades'),
        if (widget.owner) widget.request('GET', '/v1/remit/staff'),
      ]);
      if (!mounted) return;
      setState(() {
        role = me; orders = _v9Rows(data[0]['orders']);
        if (widget.owner) {
          rateData = data[1]; lots = _v9Rows(data[2]['lots']); sales = _v9Rows(data[2]['sales']);
          staff = _v9Rows(data[3]['staff']);
        }
      });
    } catch (e) { if(mounted) setState(() => error='$e'); }
    finally { if(mounted) setState(() => loading=false); }
  }
  Future<String?> prompt(String title, {String value = ''}) async {
    final ctrl = TextEditingController(text: value);
    try {
      return await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: Text(title), content: TextField(controller: ctrl, autofocus: true,
          decoration: InputDecoration(labelText: title)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Continue'))],
      ));
    } finally { ctrl.dispose(); }
  }
  Future<String?> choose(String title,List<String> values) async =>
    showDialog<String>(context: context, builder: (ctx) => SimpleDialog(
      title: Text(title), children: values.map((x) => SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, x),
        child: Padding(padding: const EdgeInsets.all(10), child: Text(x)),
      )).toList(),
    ));
  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy=true);
    try { await fn(); await refresh(); info('Updated / محفوظ ہوگیا'); }
    catch(e) { info('$e'); }
    finally { if(mounted) setState(() => busy=false); }
  }
  Future<void> publishRate() async {
    final value=await prompt('Publish AED → PKR Rate',value:_v9Value(rateData['rate']));
    if(value==null)return;
    final margin=await prompt('Suggested Margin (PKR per AED)',value:_v9Value(rateData['margin']));
    if(margin==null)return;
    await run(() async {await widget.request('POST','/v1/remit/rates/admin',{'published_rate':value,'margin':margin});});
  }
  Future<void> buyUsdt() async {
    final buyCurrency=await choose('USDT Buy Currency', ['AED','PKR']);
    if(buyCurrency==null)return;
    final amount=await prompt('$buyCurrency spent buying USDT');if(amount==null)return;
    final usdt=await prompt('USDT purchased');if(usdt==null)return;
    final fee=await prompt('$buyCurrency buying fee (0 if none)',value:'0');if(fee==null)return;
    final note=await prompt('Note (optional)');if(note==null)return;
    await run(()async{await widget.request('POST','/v1/remit/trades',{
      'buy_currency':buyCurrency,'spent':amount,'bought_usdt':usdt,'buy_fee':fee,'note':note,
    });});
  }
  Future<void> sellUsdt(Map<String,dynamic> lot) async {
    final sellCurrency=await choose('USDT Sell Currency',['AED','PKR']);
    if(sellCurrency==null)return;
    final usdt=await prompt('USDT sold (available: ${_v9Money(lot['remaining_usdt_micros'],'USDT')})');
    if(usdt==null)return;
    final amount=await prompt('$sellCurrency received from sale');if(amount==null)return;
    final fee=await prompt('$sellCurrency selling fee (0 if none)',value:'0');if(fee==null)return;
    final note=await prompt('Sale note (optional)');if(note==null)return;
    await run(()async{await widget.request('POST','/v1/remit/trades/sell',{
      'lot_id':lot['id'],'sell_currency':sellCurrency,'sold_usdt':usdt,
      'received':amount,'sell_fee':fee,'note':note,
    });});
  }
  Future<void> setStaff([Map<String,dynamic>? old]) async {
    final email = old == null ? await prompt('Staff verified Email') : '${old['email']}';
    if(email==null)return;
    final selected=await choose('Staff Role',['manager','cashier','processor','viewer']);
    if(selected==null)return;
    final action=await choose('Staff Access',['Enable','Disable']);if(action==null)return;
    await run(()async{await widget.request('POST','/v1/remit/staff',{
      'email':email,'role':selected,'enabled':action=='Enable',
    });});
  }
  List<String> allowedOrderStatuses(Map<String,dynamic> order) {
    final status='${order['status']}';
    if(role=='viewer')return [];
    if(role=='cashier')return status=='payment_submitted'?['payment_verified']:[];
    if(role=='processor') {
      if(status=='payment_verified')return ['processing'];
      if(status=='processing')return ['completed'];
      return [];
    }
    switch(status) {
      case 'pending_payment':return ['payment_submitted','cancelled','rejected'];
      case 'payment_submitted':return ['payment_verified','rejected','cancelled'];
      case 'payment_verified':return ['processing','refunded'];
      case 'processing':return ['completed','refunded'];
      default:return [];
    }
  }
  Future<void> updateOrder(Map<String,dynamic> order) async {
    final allowed=allowedOrderStatuses(order);
    if(allowed.isEmpty)return;
    final next=await choose('Update ${order['order_number']}',allowed);if(next==null)return;
    final note=await prompt('Reference / reason (optional)');if(note==null)return;
    await run(()async{await widget.request('POST','/v1/remit/orders/status',{
      'order_id':order['id'],'status':next,'note':note,
    });});
  }
  Future<void> orderDetails(Map<String,dynamic> order) async {
    final sender=order['sender'] is Map ? order['sender'] as Map : {};
    final receiver=order['receiver'] is Map ? order['receiver'] as Map : {};
    final details='Sender: ${sender['full_name']}\nPhone: ${sender['phone']}\n\n'
      'Receiver: ${receiver['full_name']}\nPhone: ${receiver['phone']}\n'
      'Receiving: ${receiver['method']}\nBank/Wallet: ${receiver['bank_or_wallet_name']}\n'
      'Account: ${receiver['account_reference']}\n\n'
      'Customer payment: ${order['payment_method']}\n'
      'Amount: ${_v9Money(order['aed_minor'],'AED')} → ${_v9Money(order['pkr_minor'],'PKR')}\n'
      'Rate: ${order['published_rate']}\nStatus: ${order['status']}';
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('${order['order_number']}'),
      content:SingleChildScrollView(child:Text(details)),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))],
    ));
  }
  Widget section(String heading) => Padding(padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(heading,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:v9Green)));
  Widget menuItem(IconData icon,String title,VoidCallback? action,String subtitle) => Card(child: ListTile(
    leading: Icon(icon,color:v9Green),title:Text(title),subtitle:Text(subtitle),
    trailing:const Icon(Icons.chevron_right),onTap:action));
  Widget overview() => ListView(padding:const EdgeInsets.all(14),children:[
    Card(color:v9Light,child:Padding(padding:const EdgeInsets.all(16),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Admin & Staff Dashboard',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),Text('Logged-in role: ${role??'unknown'}'),
        Text('Orders recorded: ${orders.length} (latest 120)'),
      ]))),
    if(widget.owner)...[
      section('Super Admin Tools'),
      menuItem(Icons.people_alt_outlined,'P2P Investors / Customers',widget.openInvestors,'Customer accounts and investment records'),
      menuItem(Icons.wallet_outlined,'Private Personal Ledger',widget.openPersonal,'Only Super Admin can access'),
      menuItem(Icons.toggle_on_outlined,'Application Mode',widget.openMode,'Personal / Multi-User switch'),
      menuItem(Icons.fact_check_outlined,'KYC & Users',widget.openKyc,'Existing admin review screen'),
    ],
    section('Order Processing'),
    const Text('View status, sender/receiver snapshots and transaction history in the Orders tab.'),
  ]);
  Widget rates() {
    final total=rateData['total'] is Map ? rateData['total'] as Map : {};
    final today=rateData['today'] is Map ? rateData['today'] as Map : {};
    String displayAvg(dynamic v) => v is num ? '${v.toStringAsFixed(4)} PKR' : 'No completed trades';
    final suggestion=rateData['suggested_rate'];
    return ListView(padding:const EdgeInsets.all(14),children:[
      section('Private Exchange Rate Manager'),
      Card(color:v9Light,child:ListTile(title:const Text('Customer Published Rate'),
        subtitle:Text('${rateData['rate'] ?? 'Not set'} PKR per AED'),
        trailing:const Icon(Icons.publish,color:v9Green))),
      Card(child:ListTile(title:const Text('All-Time Weighted Average'),subtitle:Text(displayAvg(total['average_rate'])))),
      Card(child:ListTile(title:const Text('Today Weighted Average (Dubai Time)'),subtitle:Text(displayAvg(today['average_rate'])))),
      Card(child:ListTile(title:const Text('Suggested Rate'),subtitle:Text(suggestion is num?'${suggestion.toStringAsFixed(4)} PKR':'No completed trades'))),
      const SizedBox(height:10),
      FilledButton.icon(onPressed:busy?null:publishRate,icon:const Icon(Icons.edit),label:const Text('Set / Publish Customer Rate')),
      const SizedBox(height:10),
      Text('Cross-currency AED↔PKR averages include both directions, weighted by implied AED/PKR value. Same-currency trade P/L is excluded. Suggested rate is average minus margin. Only the published rate is visible to customers.'),
      section('Buy/Sell Currency Breakdown'),
      ..._v9Rows(rateData['combinations']).map((x) => ListTile(
        title:Text('${x['buy_currency']} → ${x['sell_currency']}  •  ${x['trades']} trades'),
        subtitle:Text(x['same_currency_profit_minor'] != null
          ? 'Recorded P/L: ${_v9Money(x['same_currency_profit_minor'],_v9Value(x['buy_currency']))}'
          : 'Implied AED→PKR: ${x['implied_aed_to_pkr_rate'] is num ? (x['implied_aed_to_pkr_rate'] as num).toStringAsFixed(4) : '—'}'),
      )),
      section('Rate Change History'),
      ..._v9Rows(rateData['history']).map((h)=>ListTile(
        title:Text('${_v9Rate(h['old_rate_x10000'])} → ${_v9Rate(h['new_rate_x10000'])} PKR/AED'),
        subtitle:Text('${h['created_at']}'),
      )),
    ]);
  }
  Widget trades() => ListView(padding:const EdgeInsets.all(14),children:[
    section('USDT Buy & Sell — AED or PKR'),
    const Text('All 4 combinations: AED→AED, AED→PKR, PKR→AED, PKR→PKR. Choose buy and sell currencies independently.'),
    const SizedBox(height:10),
    FilledButton.icon(onPressed:busy?null:buyUsdt,icon:const Icon(Icons.add),label:const Text('Record New USDT Purchase')),
    Card(color:v9Light,child:ListTile(
      leading:const Icon(Icons.layers,color:v9Green),
      title:const Text('v11 — Multi-Lot Selling / Combined Inventory'),
      subtitle:const Text('Select USDT quantities from multiple purchases in one sale'),
      trailing:const Icon(Icons.chevron_right),
      onTap:()=>Navigator.push(context,MaterialPageRoute(
        builder:(_)=>V11TradingPage(request:widget.request))),
    )),
    section('USDT Buy Lots / Remaining Inventory'),
    ...lots.map((lot)=>Card(child:Column(children:[
      ListTile(title:Text('Bought: ${_v9Money(lot['bought_usdt_micros'],'USDT')}'),
        subtitle:Text('Paid: ${_v9Money(lot['spent_minor'],_v9Value(lot['buy_currency']))}'
          ' • Buy Fee: ${_v9Money(lot['buy_fee_minor'],_v9Value(lot['buy_currency']))}'
          '\nRemaining: ${_v9Money(lot['remaining_usdt_micros'],'USDT')}'),
        isThreeLine:true),
      if((lot['remaining_usdt_micros'] as num? ?? 0)>0)
        TextButton(onPressed:busy?null:()=>sellUsdt(lot),child:const Text('Record Sale (AED or PKR)')),
    ]))),
    section('Completed Sales / Selling History'),
    ...sales.map((sale)=>Card(child:ListTile(
      title:Text('${_v9Value(sale['buy_currency'])} → ${_v9Value(sale['sell_currency'])}  •  ${_v9Money(sale['sold_usdt_micros'],'USDT')}'),
      subtitle:Text('Received: ${_v9Money(sale['received_minor'],_v9Value(sale['sell_currency']))}'
        '\nSelling fee: ${_v9Money(sale['fee_minor'],_v9Value(sale['sell_currency']))}'
        '\nAllocated buy cost: ${_v9Money(sale['allocated_cost_minor'],_v9Value(sale['buy_currency']))}'
        '\n${_v9TradeOutcome(sale)}'
        '\n${sale['created_at']}'),
      isThreeLine:true,
    ))),
    if(lots.isEmpty)const Text('No manual trades recorded yet.'),
    const SizedBox(height:8),
    const Text('Same-currency trading shows recorded P/L. Cross-currency trading shows an implied AED/PKR rate, not a profit unless independently valued.'),
  ]);
  Widget ordersPage() => ListView(padding:const EdgeInsets.all(14),children:[
    section('All AED to PKR Orders'),
    ...orders.map((o)=>Card(child:Column(children:[
      ListTile(title:Text('${o['order_number']}  •  ${o['status']}'),
        subtitle:Text('${o['created_at']}\n${_v9Money(o['aed_minor'],'AED')} → ${_v9Money(o['pkr_minor'],'PKR')}\n'
          'Sender: ${o['sender']?['full_name']} → Receiver: ${o['receiver']?['full_name']}'),
        isThreeLine:true,onTap:()=>orderDetails(o)),
      if(allowedOrderStatuses(o).isNotEmpty)
        Padding(padding:const EdgeInsets.only(bottom:10),child:TextButton.icon(
          onPressed:busy?null:()=>updateOrder(o),icon:const Icon(Icons.edit_note),label:const Text('Update Status'))),
    ]))),
    if(orders.isEmpty)const Text('No transactions yet.'),
  ]);
  Widget staffPage() => ListView(padding:const EdgeInsets.all(14),children:[
    section('Staff Accounts & Permissions'),
    FilledButton.icon(onPressed:busy?null:()=>setStaff(),icon:const Icon(Icons.person_add),label:const Text('Link Verified Staff Email')),
    const Text('A staff member must sign up and verify their email first. Only Super Admin can assign roles.'),
    ...staff.map((s)=>Card(child:ListTile(
      title:Text('${s['display_name']}'),subtitle:Text('${s['email']}\n${s['role']} • ${s['enabled']==1?'Enabled':'Disabled'}'),
      trailing:IconButton(icon:const Icon(Icons.manage_accounts_outlined),onPressed:busy?null:()=>setStaff(s)),
    ))),
  ]);
  @override
  Widget build(BuildContext context) {
    final tabs=widget.owner?const ['Overview','Rates','USDT Trades','Orders','Staff']:const ['Overview','Orders'];
    final pages=widget.owner?<Widget>[overview(),rates(),trades(),ordersPage(),staffPage()]:<Widget>[overview(),ordersPage()];
    return DefaultTabController(length:tabs.length,child:Scaffold(
      appBar:AppBar(title:const Text('Admin & Staff'),actions:[
        IconButton(onPressed:loading?null:refresh,icon:const Icon(Icons.refresh)),
      ],bottom:TabBar(isScrollable:true,tabs:tabs.map((x)=>Tab(text:x)).toList())),
      body:loading?const Center(child:CircularProgressIndicator()):error!=null
        ?Center(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text('Sync error: $error'),FilledButton(onPressed:refresh,child:const Text('Retry')),
        ]))):TabBarView(children:pages),
    ));
  }
}
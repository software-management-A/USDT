import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OFFLINE DEMO STORE. This is not an authenticated, multi-device financial ledger.
/// Production financial actions MUST run atomically on a secured backend.
class SarmayaStore extends ChangeNotifier {
  static const _storageKey = 'sarmaya_demo_state_v1';
  bool urdu = true;
  bool referralEnabled = true;
  bool admittedRisk = false;
  String name = 'Demo Investor';
  String phone = '03000000000';
  String referralCode = 'SP-DEMO125';
  String withdrawalAccount = 'Easypaisa •••• 0000';
  String exitStatus = 'none';
  String activePlan = '';
  String exitRequestedAt = '';
  String lastWithdrawDay = '';
  String distributionStage = 'draft';
  double cashWallet = 4000;
  double referralWallet = 1000;
  double earningsWallet = 0;
  double lifetimeDeposit = 4000;
  double lifetimeReferral = 1000;
  double lifetimeEarnings = 0;
  double lifetimeWithdrawn = 0;
  double invested = 0;
  double investedReferral = 0;
  double investedCash = 0;
  double inventoryUsdt = 0;
  double inventoryCostPkr = 0;
  double profitReady = 0;
  double priorLossCarry = 0;
  double ownerAvailable = 0;
  double ownerLiabilities = 0;
  double reserveFund = 0;
  double referralFund = 2000; // DEMO seed; not a verified real fund.
  double reservePercent = 15; // of 100% profit; remainder of combined 20 is referral.
  List<Map<String, dynamic>> plans = [
    {'name':'Bronze','price':5000.0,'weight':1.0,'active':true,'referral':10.0},
    {'name':'Silver','price':10000.0,'weight':2.0,'active':true,'referral':20.0},
    {'name':'Gold','price':20000.0,'weight':3.0,'active':true,'referral':50.0},
    {'name':'Platinum','price':50000.0,'weight':4.0,'active':true,'referral':75.0},
    {'name':'Diamond','price':100000.0,'weight':5.0,'active':true,'referral':100.0},
  ];
  List<Map<String, dynamic>> activity = [];
  List<Map<String, dynamic>> deposits = [];
  List<Map<String, dynamic>> withdrawals = [];
  List<Map<String, dynamic>> referralHistory = [];
  List<Map<String, dynamic>> trades = [];
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> payroll = [];
  List<Map<String, dynamic>> staff = [
    {'name':'Owner (demo)','role':'Super Admin','active':true},
    {'name':'Finance (demo)','role':'Finance Manager','active':true},
  ];
  List<Map<String, dynamic>> tickets = [];
  List<Map<String, dynamic>> notices = [];
  List<Map<String, dynamic>> unmaturedEarnings = [];
  double get totalWallet => cashWallet + referralWallet + earningsWallet;
  double get withdrawable => cashWallet + earningsWallet;
  double get combinedInvestmentFunds => totalWallet;
  double get averageUsdtCost => inventoryUsdt > 0 ? inventoryCostPkr / inventoryUsdt : 0;
  double get referralPercent => 20 - reservePercent;
  String get today => DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String().substring(0, 10); // PKT
  String get timestamp => '${DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String().substring(0, 19).replaceFirst('T', ' ')} PKT';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      log('DEMO START','Initial sample balances only');
      return;
    }
    try {
      final d = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      urdu = d['urdu'] ?? urdu;
      referralEnabled = d['referralEnabled'] ?? referralEnabled;
      admittedRisk = d['admittedRisk'] ?? admittedRisk;
      name = d['name'] ?? name;
      phone = d['phone'] ?? phone;
      referralCode = d['referralCode'] ?? referralCode;
      withdrawalAccount = d['withdrawalAccount'] ?? withdrawalAccount;
      exitStatus = d['exitStatus'] ?? exitStatus;
      activePlan = d['activePlan'] ?? activePlan;
      exitRequestedAt = d['exitRequestedAt'] ?? exitRequestedAt;
      lastWithdrawDay = d['lastWithdrawDay'] ?? lastWithdrawDay;
      distributionStage = d['distributionStage'] ?? distributionStage;
      double read(String key, double fallback) => (d[key] as num?)?.toDouble() ?? fallback;
      cashWallet = read('cashWallet', cashWallet);
      referralWallet = read('referralWallet', referralWallet);
      earningsWallet = read('earningsWallet', earningsWallet);
      lifetimeDeposit = read('lifetimeDeposit', lifetimeDeposit);
      lifetimeReferral = read('lifetimeReferral', lifetimeReferral);
      lifetimeEarnings = read('lifetimeEarnings', lifetimeEarnings);
      lifetimeWithdrawn = read('lifetimeWithdrawn', lifetimeWithdrawn);
      invested = read('invested', invested);
      investedReferral = read('investedReferral', investedReferral);
      investedCash = read('investedCash', investedCash);
      inventoryUsdt = read('inventoryUsdt', inventoryUsdt);
      inventoryCostPkr = read('inventoryCostPkr', inventoryCostPkr);
      profitReady = read('profitReady', profitReady);
      priorLossCarry = read('priorLossCarry', priorLossCarry);
      ownerAvailable = read('ownerAvailable', ownerAvailable);
      ownerLiabilities = read('ownerLiabilities', ownerLiabilities);
      reserveFund = read('reserveFund', reserveFund);
      referralFund = read('referralFund', referralFund);
      reservePercent = read('reservePercent', reservePercent);
      List<Map<String,dynamic>> readList(String key, List<Map<String,dynamic>> fallback) =>
        (d[key] as List?)?.map((x)=>Map<String,dynamic>.from(x as Map)).toList() ?? fallback;
      plans = readList('plans', plans);
      activity = readList('activity', activity);
      deposits = readList('deposits', deposits);
      withdrawals = readList('withdrawals', withdrawals);
      referralHistory = readList('referralHistory', referralHistory);
      trades = readList('trades', trades);
      expenses = readList('expenses', expenses);
      payroll = readList('payroll', payroll);
      staff = readList('staff', staff);
      tickets = readList('tickets', tickets);
      notices = readList('notices', notices);
      unmaturedEarnings = readList('unmaturedEarnings', unmaturedEarnings);
      releaseEarnings();
      notifyListeners();
    } catch (e) {
      debugPrint('Local demo data unreadable, keeping fresh demo: $e');
    }
  }

  Future<void> save() async {
    final state = <String,dynamic>{
      'urdu':urdu,'referralEnabled':referralEnabled,'admittedRisk':admittedRisk,
      'name':name,'phone':phone,'referralCode':referralCode,'withdrawalAccount':withdrawalAccount,
      'exitStatus':exitStatus,'activePlan':activePlan,'exitRequestedAt':exitRequestedAt,
      'lastWithdrawDay':lastWithdrawDay,'distributionStage':distributionStage,
      'cashWallet':cashWallet,'referralWallet':referralWallet,'earningsWallet':earningsWallet,
      'lifetimeDeposit':lifetimeDeposit,'lifetimeReferral':lifetimeReferral,
      'lifetimeEarnings':lifetimeEarnings,'lifetimeWithdrawn':lifetimeWithdrawn,
      'invested':invested,'investedReferral':investedReferral,'investedCash':investedCash,
      'inventoryUsdt':inventoryUsdt,'inventoryCostPkr':inventoryCostPkr,'profitReady':profitReady,
      'priorLossCarry':priorLossCarry,'ownerAvailable':ownerAvailable,'ownerLiabilities':ownerLiabilities,
      'reserveFund':reserveFund,'referralFund':referralFund,'reservePercent':reservePercent,
      'plans':plans,'activity':activity,'deposits':deposits,'withdrawals':withdrawals,
      'referralHistory':referralHistory,'trades':trades,'expenses':expenses,
      'payroll':payroll,'staff':staff,'tickets':tickets,'notices':notices,
      'unmaturedEarnings':unmaturedEarnings,
    };
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(state));
  }

  void log(String type, String detail, {double amount=0}) {
    activity.insert(0, {'type':type,'detail':detail,'amount':amount,'at':timestamp});
  }
  void setLanguage(bool value) { urdu=value; save(); }
  void changeProfile(String n, String p) {
    name=n.trim(); phone=p.trim(); log('PROFILE','Updated demo profile'); save();
  }
  void recordRisk() { admittedRisk=true; log('RISK','Demo acknowledgment'); save(); }

  String? requestDeposit(double amount, String reference) {
    if (!amount.isFinite || amount <= 0 || reference.trim().isEmpty) return 'Valid amount and transaction ID required';
    if (deposits.any((x)=>x['reference'] == reference.trim())) return 'Duplicate transaction ID';
    deposits.insert(0, {'id':'DEP-${DateTime.now().microsecondsSinceEpoch}', 'amount':amount,
      'reference':reference.trim(),'status':'Pending','at':timestamp});
    log('DEPOSIT REQUEST','Ref: $reference',amount:amount);
    save(); return null;
  }
  void approveDeposit(String id, bool approve) {
    final d=deposits.firstWhere((x)=>x['id']==id);
    if(d['status']!='Pending') return;
    d['status']=approve?'Approved':'Rejected';
    if(approve) { final a=(d['amount'] as num).toDouble();cashWallet+=a;lifetimeDeposit+=a; }
    log('DEPOSIT ${approve?'APPROVED':'REJECTED'}', d['reference'].toString(), amount:(d['amount'] as num).toDouble()); save();
  }

  String? purchasePlan(Map<String,dynamic> plan) {
    if (!admittedRisk) return 'Please accept investment risk acknowledgment first';
    if(activePlan.isNotEmpty || invested>0 || exitStatus!='none') return 'Exit current plan before buying another';
    if(plan['active']!=true) return 'Plan is disabled';
    final price=(plan['price'] as num).toDouble();
    if(price<=0 || totalWallet+0.001<price) return 'Insufficient wallet balance';
    _deductForInvestment(price);
    activePlan=plan['name'].toString(); invested=price;
    log('PLAN PURCHASE',activePlan,amount:-price);save();return null;
  }
  void _deductForInvestment(double amount) {
    // Track source without altering lifetime deposit/referral totals.
    final fromCash=min(amount, cashWallet);cashWallet-=fromCash;
    final rest=amount-fromCash;
    final fromEarnings=min(rest, earningsWallet);earningsWallet-=fromEarnings;
    final fromReferral=rest-fromEarnings;
    referralWallet=max(0,referralWallet-fromReferral);
    investedCash+=fromCash+fromEarnings;
    investedReferral+=fromReferral;
  }
  String? upgradePlan(Map<String,dynamic> newPlan) {
    if(activePlan.isEmpty || exitStatus!='none') return 'No active plan or exit is underway';
    final price=(newPlan['price'] as num).toDouble();
    final diff=price-invested;
    if(diff<=0) return 'Downgrades are not allowed';
    if(totalWallet+0.001<diff) return 'Insufficient wallet balance for upgrade';
    if(newPlan['active']!=true) return 'Plan disabled';
    _deductForInvestment(diff); invested=price;activePlan=newPlan['name'].toString();
    log('PLAN UPGRADE',activePlan,amount:-diff);save();return null;
  }
  String? requestExit() {
    if(activePlan.isEmpty || invested<=0) return 'No active investment';
    if(exitStatus!='none') return 'Exit already requested';
    exitStatus='pending';exitRequestedAt=timestamp;
    log('EXIT REQUEST','Requested for $activePlan');save();return null;
  }
  String? cancelExit() {
    if(exitStatus!='pending' && exitStatus!='review') return 'Exit trading already started or no request';
    exitStatus='none'; exitRequestedAt=''; log('EXIT CANCEL','Self-cancel before trading');save();return null;
  }
  void reviewExit() {
    if(exitStatus=='pending') { exitStatus='review';log('EXIT REVIEW','Admin reviewing request');save(); }
  }
  void startExitTrade() {
    if(exitStatus=='pending'||exitStatus=='review') {
      exitStatus='trading';log('EXIT TRADING','Self-cancellation locked');save();
    }
  }
  String? settleExit(double actualProceeds) {
    if(exitStatus!='trading') return 'Start exit trade first';
    if(actualProceeds<0 || !actualProceeds.isFinite) return 'Invalid realized proceeds';
    final old=invested;
    // Only REALIZED proceeds; referral-origin principal becomes withdrawable after genuine exit.
    cashWallet+=actualProceeds;
    invested=0;investedCash=0;investedReferral=0;activePlan='';exitStatus='none';exitRequestedAt='';
    log('EXIT SETTLED','Realized ${actualProceeds.toStringAsFixed(2)} vs invested ${old.toStringAsFixed(2)}',amount:actualProceeds);
    save();return null;
  }

  String? requestWithdrawal(double amount) {
    if(!amount.isFinite || amount<=0 || amount>withdrawable+0.001) return 'Invalid or insufficient withdrawable balance';
    if(lastWithdrawDay==today) return 'Only one withdrawal request per PKT day';
    if(withdrawals.any((x)=>x['status']=='Pending')) return 'Existing withdrawal is pending';
    // Reserve by source: earnings first, then uninvested cash. Referral wallet excluded.
    final fromEarnings=min(earningsWallet,amount);
    earningsWallet-=fromEarnings;cashWallet-=amount-fromEarnings;
    withdrawals.insert(0,{'id':'WDR-${DateTime.now().microsecondsSinceEpoch}',
      'amount':amount,'earningsUsed':fromEarnings,'account':withdrawalAccount,
      'status':'Pending','at':timestamp});
    lastWithdrawDay=today;
    log('WITHDRAW REQUEST',withdrawalAccount,amount:-amount);save();return null;
  }
  void processWithdrawal(String id,bool approve) {
    final w=withdrawals.firstWhere((x)=>x['id']==id);
    if(w['status']!='Pending') return;
    w['status']=approve?'Paid':'Rejected';
    final amount=(w['amount'] as num).toDouble();
    if(approve) { lifetimeWithdrawn+=amount; }
    else {final e=(w['earningsUsed'] as num).toDouble();earningsWallet+=e;cashWallet+=amount-e;}
    log('WITHDRAW ${approve?'PAID':'REJECTED'}',id,amount:amount);save();
  }
  void changeWithdrawalAccount(String destination) {
    // DEMO ONLY: production requires 2FA and admin verified account change.
    withdrawalAccount=destination.trim();log('ACCOUNT','Demo payout destination updated');save();
  }

  String? grantReferral(String referred, double reward) {
    if(!referralEnabled) return 'Referral rewards are OFF';
    if(referred.trim().isEmpty || reward<=0 || !reward.isFinite) return 'Invalid referred user or amount';
    if(referralHistory.any((x)=>x['referred']==referred.trim())) return 'This demo referral already received a reward';
    if(referralFund+0.001<reward) return 'Insufficient verified referral fund: keep reward pending';
    referralFund-=reward;referralWallet+=reward;lifetimeReferral+=reward;
    referralHistory.insert(0,{'referred':referred.trim(),'amount':reward,'status':'Approved','at':timestamp});
    log('REFERRAL CREDIT',referred.trim(),amount:reward);save();return null;
  }
  void setReferrals(bool value) { referralEnabled=value;log('SETTINGS','Referrals ${value?'ON':'OFF'}');save(); }
  String? configureFundSplit(double reserve) {
    if(reserve<0 || reserve>20 || !reserve.isFinite) return 'Reserve % must be between 0 and 20';
    reservePercent=reserve;log('FUND SETTINGS','Reserve $reserve%, Referral ${20-reserve}%');save();return null;
  }
  void updatePlan(int index, double price, double weight, double referral, bool active) {
    if(index<0 || index>=plans.length || price<=0 || weight<=0 || referral<0) return;
    plans[index]={'name':plans[index]['name'],'price':price,'weight':weight,'referral':referral,'active':active};
    log('PLAN SETTINGS',plans[index]['name'].toString());save();
  }

  String? recordTrade({required bool buy,required double usdt,required double pkr,required String orderId,
      required String transferId,required String counterparty}) {
    if(usdt<=0 || pkr<=0 || !usdt.isFinite || !pkr.isFinite || orderId.trim().isEmpty || transferId.trim().isEmpty || counterparty.trim().isEmpty) {
      return 'USDT, actual PKR, order ID, transfer ID and counterparty are required';
    }
    if(trades.any((x)=>x['orderId']==orderId.trim())) return 'Duplicate Binance order ID';
    double pnl=0;
    if(buy) { inventoryUsdt+=usdt;inventoryCostPkr+=pkr; }
    else {
      if(usdt>inventoryUsdt+0.000001) return 'USDT inventory insufficient';
      final soldCost=averageUsdtCost*usdt;
      inventoryUsdt=max(0,inventoryUsdt-usdt);
      inventoryCostPkr=max(0,inventoryCostPkr-soldCost);
      pnl=pkr-soldCost;
      if(pnl>=0) { final offset=min(pnl,priorLossCarry);priorLossCarry-=offset;profitReady+=pnl-offset; }
      else {priorLossCarry+=-pnl;}
    }
    trades.insert(0,{'type':buy?'BUY':'SELL','usdt':usdt,'pkr':pkr,
      'rate':pkr/usdt,'pnl':pnl,'orderId':orderId.trim(),'transferId':transferId.trim(),
      'counterparty':counterparty.trim(),'at':timestamp});
    log(buy?'P2P BUY':'P2P SELL',orderId,amount:pnl);save();return null;
  }
  void progressDistribution() {
    if(profitReady<=0 || activePlan.isEmpty) return;
    if(distributionStage=='draft') distributionStage='trading_checked';
    else if(distributionStage=='trading_checked') distributionStage='finance_checked';
    else if(distributionStage=='finance_checked') {
      final amount=profitReady;
      final userShare=amount*.50;
      ownerAvailable+=amount*.30;
      reserveFund+=amount*reservePercent/100;
      referralFund+=amount*(20-reservePercent)/100;
      lifetimeEarnings+=userShare;
      final availableDate=DateTime.now().toUtc().add(const Duration(hours:5, days:1)).toIso8601String().substring(0,10);
      unmaturedEarnings.insert(0,{'amount':userShare,'availableOn':availableDate,'at':timestamp});
      profitReady=0;
      distributionStage='draft';
      log('PROFIT DISTRIBUTED','50% demo user, 30% owner, 20% combined',amount:amount);
    }
    save();
  }
  void releaseEarnings() {
    final ready=unmaturedEarnings.where((x)=>(x['availableOn'] as String).compareTo(today)<=0).toList();
    for(final x in ready) { earningsWallet+=(x['amount'] as num).toDouble();unmaturedEarnings.remove(x); }
    if(ready.isNotEmpty) { log('EARNINGS RELEASED','Next-day earnings available'); save(); }
  }
  double get earningsWaiting => unmaturedEarnings.fold(0.0,(a,x)=>a+(x['amount'] as num).toDouble());

  String? addExpense(String title,double amount) {
    if(title.trim().isEmpty || !amount.isFinite || amount<=0) return 'Expense and amount required';
    final paid=min(amount,ownerAvailable);
    ownerAvailable-=paid;ownerLiabilities+=amount-paid;
    expenses.insert(0,{'title':title.trim(),'amount':amount,'paid':paid,
      'status':paid>=amount?'Paid':'Unpaid / Part-paid','at':timestamp});
    log('OWNER EXPENSE',title.trim(),amount:-amount);save();return null;
  }
  String? addSalary(String employee,double amount) {
    if(employee.trim().isEmpty || !amount.isFinite || amount<=0) return 'Employee and amount required';
    final paid=min(amount,ownerAvailable);ownerAvailable-=paid;ownerLiabilities+=amount-paid;
    payroll.insert(0,{'employee':employee.trim(),'amount':amount,'paid':paid,
      'status':paid>=amount?'Paid':'Unpaid / Part-paid','at':timestamp});
    log('OWNER PAYROLL',employee.trim(),amount:-amount);save();return null;
  }
  String? addStaff(String staffName,String role) {
    if(staffName.trim().isEmpty) return 'Staff name required';
    if(staff.where((x)=>x['active']==true).length>=5) return 'Maximum 5 active staff';
    staff.add({'name':staffName.trim(),'role':role,'active':true});
    log('STAFF ADDED',staffName);save();return null;
  }
  void disableStaff(int index) {if(index>=0&&index<staff.length&&staff[index]['role']!='Super Admin'){
    staff[index]['active']=false;log('STAFF DISABLED',staff[index]['name'].toString());save();}}
  void addTicket(String subject,String text) {
    tickets.insert(0,{'subject':subject,'message':text,'status':'Open','at':timestamp});
    log('SUPPORT','New ticket $subject');save();
  }
  void notifyUser(String message) {
    notices.insert(0,{'text':message,'at':timestamp});save();
  }

  Future<void> resetDemo() async {
    final prefs=await SharedPreferences.getInstance();await prefs.remove(_storageKey);
    // A new store instance should be created via full restart after this.
  }
}

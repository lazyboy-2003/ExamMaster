import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const ExamMasterApp());

class ExamMasterApp extends StatelessWidget {
  const ExamMasterApp({super.key});
  Widget build(BuildContext c) => MaterialApp(
    debugShowCheckedModeBanner:false, title:'ExamMaster',
    theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.indigo),
    home:const HomePage());
}

class Question {
  final String text; final List<String> options; final int answer;
  const Question({required this.text,required this.options,required this.answer});
  factory Question.fromJson(Map<String,dynamic> j)=>Question(
    text:j['question'], options:List<String>.from(j['options']),
    answer:(j['answer_index'] as num).toInt());
}

class LocalDb {
  static Database? _db;
  static Future<Database> get db async {
    if(_db!=null)return _db!;
    _db=await openDatabase(join(await getDatabasesPath(),'exam_master.db'),version:1,
      onCreate:(d,v)=>d.execute(
        'CREATE TABLE results(id INTEGER PRIMARY KEY AUTOINCREMENT,exam TEXT,subject TEXT,total INTEGER,correct INTEGER,wrong INTEGER,skipped INTEGER,seconds INTEGER,created_at TEXT)'));
    return _db!;
  }
  static Future<void> save(String exam,String subject,int total,int correct,int wrong,int skipped,int seconds) async =>
    (await db).insert('results',{'exam':exam,'subject':subject,'total':total,'correct':correct,'wrong':wrong,'skipped':skipped,'seconds':seconds,'created_at':DateTime.now().toIso8601String()});
}

class ApiService {
  static const defaultBaseUrl='http://10.0.2.2:8000';
  static Future<List<Question>> generate(String exam,String subject,int count,String difficulty) async {
    final p=await SharedPreferences.getInstance();
    final base=p.getString('api_base_url')??defaultBaseUrl;
    final r=await http.post(Uri.parse(base+'/v1/tests/generate'),
      headers:{'Content-Type':'application/json'},
      body:jsonEncode({'exam':exam,'subject':subject,'question_count':count,'difficulty':difficulty}))
      .timeout(const Duration(seconds:45));
    if(r.statusCode!=200)throw Exception('Generation failed: '+r.statusCode.toString());
    final data=jsonDecode(r.body);
    return (data['questions'] as List).map((e)=>Question.fromJson(e)).toList();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  State<HomePage> createState()=>_HomePageState();
}
class _HomePageState extends State<HomePage> {
  String exam='SSC CGL',subject='General Awareness',difficulty='Mixed';
  int count=10; bool loading=false;
  final exams=['SSC CGL','SSC CHSL','RRB NTPC','RRB Group D','Banking','State Exams'];
  final subjects=['General Awareness','General Science','History','Geography','Polity','Economy','English','Mixed'];
  final diffs=['Easy','Medium','Hard','Mixed'];

  Future<void> start() async {
    setState(()=>loading=true);
    try {
      final q=await ApiService.generate(exam,subject,count,difficulty);
      if(!mounted)return;
      Navigator.push(context,MaterialPageRoute(builder:(_)=>TestPage(exam:exam,subject:subject,questions:q)));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not generate test: '+e.toString())));
    } finally {if(mounted)setState(()=>loading=false);}
  }

  Widget drop(String label,String value,List<String> items,ValueChanged<String?> f)=>Card(
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:16),
      child:DropdownButtonFormField<String>(
        initialValue:value,decoration:InputDecoration(labelText:label,border:InputBorder.none),
        items:items.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:f)));

  Widget build(BuildContext c)=>Scaffold(
    appBar:AppBar(title:const Text('ExamMaster',style:TextStyle(fontWeight:FontWeight.bold)),
      actions:[IconButton(icon:const Icon(Icons.history),onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const HistoryPage())))]),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('AI Mock Test',style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),const Text('A fresh AI-generated test every time.'),
      const SizedBox(height:20),drop('Exam',exam,exams,(v)=>setState(()=>exam=v!)),
      drop('Subject',subject,subjects,(v)=>setState(()=>subject=v!)),
      drop('Difficulty',difficulty,diffs,(v)=>setState(()=>difficulty=v!)),
      Card(child:ListTile(title:const Text('Questions'),subtitle:Text(count.toString()+' questions'),
        trailing:DropdownButton<int>(value:count,items:[10,20,30,50].map((n)=>DropdownMenuItem(value:n,child:Text(n.toString()))).toList(),onChanged:(v)=>setState(()=>count=v!)))),
      const SizedBox(height:16),
      FilledButton.icon(onPressed:loading?null:start,
        icon:loading?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_awesome),
        label:Text(loading?'Generating…':'Generate New Test'),
        style:FilledButton.styleFrom(padding:const EdgeInsets.all(17)))
    ]));
}

class TestPage extends StatefulWidget {
  final String exam,subject; final List<Question> questions;
  const TestPage({super.key,required this.exam,required this.subject,required this.questions});
  State<TestPage> createState()=>_TestPageState();
}
class _TestPageState extends State<TestPage> {
  int index=0,seconds=600; final Map<int,int> selected={}; late Timer timer;
  void initState(){super.initState();timer=Timer.periodic(const Duration(seconds:1),(_){
    if(seconds<=0){timer.cancel();submit();}else if(mounted)setState(()=>seconds--);});}
  void dispose(){timer.cancel();super.dispose();}
  void submit(){
    if(!mounted)return;timer.cancel();int correct=0,wrong=0;
    for(int i=0;i<widget.questions.length;i++){final a=selected[i];if(a==null)continue;if(a==widget.questions[i].answer)correct++;else wrong++;}
    final skipped=widget.questions.length-correct-wrong;
    Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>ResultPage(
      exam:widget.exam,subject:widget.subject,total:widget.questions.length,correct:correct,wrong:wrong,skipped:skipped,spent:600-seconds)));
  }
  Widget build(BuildContext c){
    final q=widget.questions[index];
    final mm=(seconds~/60).toString().padLeft(2,'0'),ss=(seconds%60).toString().padLeft(2,'0');
    return Scaffold(appBar:AppBar(title:Text(mm+':'+ss)),body:Column(children:[
      LinearProgressIndicator(value:(index+1)/widget.questions.length),
      Expanded(child:ListView(padding:const EdgeInsets.all(20),children:[
        Text('Question '+(index+1).toString()+' of '+widget.questions.length.toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:16),Text(q.text,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700)),
        const SizedBox(height:18),...List.generate(q.options.length,(i)=>Card(child:RadioListTile<int>(
          value:i,groupValue:selected[index],title:Text(q.options[i]),onChanged:(v)=>setState(()=>selected[index]=v!))))
      ])),
      Padding(padding:const EdgeInsets.all(16),child:Row(children:[
        if(index>0)Expanded(child:OutlinedButton(onPressed:()=>setState(()=>index--),child:const Text('Previous'))),
        if(index>0)const SizedBox(width:10),
        Expanded(child:FilledButton(onPressed:index==widget.questions.length-1?submit:()=>setState(()=>index++),
          child:Text(index==widget.questions.length-1?'Submit':'Next')))
      ]))
    ]));
  }
}

class ResultPage extends StatelessWidget {
  final String exam,subject;final int total,correct,wrong,skipped,spent;
  const ResultPage({super.key,required this.exam,required this.subject,required this.total,required this.correct,required this.wrong,required this.skipped,required this.spent});
  Widget build(BuildContext c){
    LocalDb.save(exam,subject,total,correct,wrong,skipped,spent);
    final pct=correct/total*100;
    return Scaffold(appBar:AppBar(title:const Text('Result')),body:Center(child:Padding(padding:const EdgeInsets.all(24),
      child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        const Icon(Icons.emoji_events,size:72),const SizedBox(height:12),
        const Text('Test Completed',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
        const SizedBox(height:18),Text(correct.toString()+'/'+total.toString(),style:const TextStyle(fontSize:44,fontWeight:FontWeight.w800)),
        Text(pct.toStringAsFixed(1)+'% accuracy'),const SizedBox(height:18),
        Text('Correct: '+correct.toString()+'   Wrong: '+wrong.toString()+'   Skipped: '+skipped.toString()),
        const SizedBox(height:30),FilledButton(onPressed:()=>Navigator.popUntil(c,(r)=>r.isFirst),child:const Text('Back to Home'))
      ])));
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Test History')),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:LocalDb.db.then((d)=>d.query('results',orderBy:'id DESC')),builder:(c,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      if(s.data!.isEmpty)return const Center(child:Text('No tests yet'));
      return ListView.builder(itemCount:s.data!.length,itemBuilder:(c,i){
        final r=s.data![i];return ListTile(leading:const CircleAvatar(child:Icon(Icons.quiz)),
          title:Text(r['exam'].toString()+' • '+r['subject'].toString()),
          subtitle:Text(r['correct'].toString()+'/'+r['total'].toString()+' correct • '+r['created_at'].toString()));
      });}));
}

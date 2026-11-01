import 'package:flutter/widgets.dart';

mixin StateLogMixin on State<StatefulWidget> {
  void logState(String message) {
    debugPrint('[${widget.runtimeType}] $message');
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => CounterState();
}

class CounterState extends State<CounterPage> with StateLogMixin {
  int count = 0;

  void increment() {
    setState(() {
      count++;
    });
    logState('count = $count');
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// 아래 클래스는 State 계층이 아니므로 on 제약 위반으로 컴파일 오류가 난다.
// class BadHelper with StateLogMixin {}

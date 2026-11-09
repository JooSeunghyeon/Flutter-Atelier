import 'dart:async';
import 'dart:io';

class EventLog {
  final List<String> events = [];

  void add(String event) {
    events.add(event);
  }

  void clear() {
    events.clear();
  }

  @override
  String toString() => events.join(', ');
}

void checkSequence(List<String> actual, List<String> expected, String label) {
  if (actual.length != expected.length) {
    print('실패 ($label): 길이 불일치. 기대=${expected.length}, 실제=${actual.length}');
    print('  기대: ${expected.join(', ')}');
    print('  실제: ${actual.join(', ')}');
    exit(1);
  }
  for (int i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      print('실패 ($label): 위치 $i에서 불일치');
      print('  기대: ${expected.join(', ')}');
      print('  실제: ${actual.join(', ')}');
      exit(1);
    }
  }
}

Future<void> testCancelOnErrorFalse() async {
  print('\n=== cancelOnError: false (기본) ===');
  final log = EventLog();
  final controller = StreamController<int>(
    onCancel: () {
      log.add('onCancel');
    },
  );

  controller.stream.listen(
    (data) => log.add('data:$data'),
    onError: (e) => log.add('error:$e'),
    onDone: () => log.add('onDone'),
    cancelOnError: false,
  );

  controller.add(1);
  controller.addError('에러1');
  controller.add(2);
  controller.addError('에러2');
  controller.add(3);
  await controller.close();

  await Future.delayed(Duration.zero);

  print('이벤트: $log');
  final expected = [
    'data:1',
    'error:에러1',
    'data:2',
    'error:에러2',
    'data:3',
    'onCancel',
    'onDone',
  ];
  checkSequence(log.events, expected, 'cancelOnError: false');
  print('통과');
}

Future<void> testCancelOnErrorTrue() async {
  print('\n=== cancelOnError: true ===');
  final log = EventLog();
  final controller = StreamController<int>(
    onCancel: () {
      log.add('onCancel');
    },
  );

  controller.stream.listen(
    (data) => log.add('data:$data'),
    onError: (e) => log.add('error:$e'),
    onDone: () => log.add('onDone'),
    cancelOnError: true,
  );

  controller.add(1);
  controller.addError('에러1');
  controller.add(2);
  await controller.close();

  await Future.delayed(Duration.zero);

  print('이벤트: $log');
  final expected = [
    'data:1',
    'onCancel',
    'error:에러1',
  ];
  checkSequence(log.events, expected, 'cancelOnError: true');
  print('통과');
}

Future<void> testAwaitFor() async {
  print('\n=== await for ===');
  final log = EventLog();
  final controller = StreamController<int>(
    onCancel: () {
      log.add('onCancel');
    },
  );

  controller.add(1);
  controller.addError('에러1');
  controller.add(2);

  try {
    await for (final value in controller.stream) {
      log.add('data:$value');
    }
  } catch (e) {
    log.add('catch:$e');
  } finally {
    log.add('finally');
  }

  await controller.close();
  await Future.delayed(Duration.zero);

  print('이벤트: $log');
  final expected = [
    'data:1',
    'onCancel',
    'catch:에러1',
    'finally',
  ];
  checkSequence(log.events, expected, 'await for');
  print('통과');
}

Future<void> testHandleError() async {
  print('\n=== handleError ===');
  final log = EventLog();
  final controller = StreamController<int>();

  controller.stream
      .handleError(
        (e) => log.add('handled:$e'),
        test: (e) => e.toString() == '복구가능',
      )
      .listen(
        (data) => log.add('data:$data'),
        onError: (e) => log.add('error:$e'),
        onDone: () => log.add('onDone'),
      );

  controller.add(1);
  controller.addError('복구가능');
  controller.add(2);
  controller.addError('복구불가');
  controller.add(3);
  await controller.close();

  await Future.delayed(Duration.zero);

  print('이벤트: $log');
  final expected = [
    'data:1',
    'handled:복구가능',
    'data:2',
    'error:복구불가',
    'data:3',
    'onDone',
  ];
  checkSequence(log.events, expected, 'handleError');
  print('통과');
}

Future<void> testCloseAfterAdd() async {
  print('\n=== close() 후 add/addError ===');
  final log = EventLog();
  final controller = StreamController<int>();

  controller.stream.listen(
    (data) => log.add('data:$data'),
    onDone: () => log.add('onDone'),
  );

  controller.add(1);
  await controller.close();
  await Future.delayed(Duration.zero);

  if (!log.events.contains('data:1') || !log.events.contains('onDone')) {
    print('실패: close 전 이벤트 확인 실패');
    print('  실제: ${log.events.join(', ')}');
    exit(1);
  }

  bool addThrew = false;
  try {
    controller.add(2);
  } on StateError catch (e) {
    log.add('StateError(add):${e.message}');
    addThrew = true;
  }

  bool addErrorThrew = false;
  try {
    controller.addError('에러');
  } on StateError catch (e) {
    log.add('StateError(addError):${e.message}');
    addErrorThrew = true;
  }

  await Future.delayed(Duration.zero);

  print('이벤트: $log');
  if (!addThrew) {
    print('실패: close() 후 add가 StateError를 던지지 않음');
    exit(1);
  }
  if (!addErrorThrew) {
    print('실패: close() 후 addError가 StateError를 던지지 않음');
    exit(1);
  }
  if (log.events.contains('data:2')) {
    print('실패: close() 후 data:2가 추가되면 안 됨');
    exit(1);
  }
  print('통과');
}

void main() async {
  try {
    await testCancelOnErrorFalse();
    await testCancelOnErrorTrue();
    await testAwaitFor();
    await testHandleError();
    await testCloseAfterAdd();
    print('\nALL_CHECKS_PASSED');
  } catch (e, stackTrace) {
    print('\n실패 발생: $e');
    print(stackTrace);
    exit(1);
  }
}

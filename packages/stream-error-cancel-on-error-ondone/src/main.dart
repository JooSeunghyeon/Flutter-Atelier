import 'dart:async';

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

void check(bool condition, String message) {
  if (!condition) {
    print('실패: $message');
    throw Exception(message);
  }
}

Future<void> testCancelOnErrorFalse() async {
  print('\n=== cancelOnError: false (기본) ===');
  final log = EventLog();
  final controller = StreamController<int>();

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
  check(log.events.contains('data:1'), 'data:1이 있어야 함');
  check(log.events.contains('error:에러1'), 'error:에러1이 있어야 함');
  check(log.events.contains('data:2'), '에러 후 data:2가 있어야 함');
  check(log.events.contains('error:에러2'), 'error:에러2가 있어야 함');
  check(log.events.contains('data:3'), '에러 후 data:3이 있어야 함');
  check(log.events.contains('onDone'), 'onDone이 호출되어야 함');
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
  check(log.events.contains('data:1'), 'data:1이 있어야 함');
  check(log.events.contains('error:에러1'), 'error:에러1이 있어야 함');
  check(!log.events.contains('data:2'), '에러 후 data:2가 없어야 함');
  check(!log.events.contains('onDone'), 'onDone이 호출되지 않아야 함');
  check(log.events.contains('onCancel'), 'onCancel이 호출되어야 함');
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

  bool errorCaught = false;
  bool finallyRan = false;

  try {
    await for (final value in controller.stream) {
      log.add('data:$value');
    }
  } catch (e) {
    log.add('catch:$e');
    errorCaught = true;
  } finally {
    log.add('finally');
    finallyRan = true;
  }

  await controller.close();
  await Future.delayed(Duration.zero);

  print('이벤트: $log');
  check(log.events.contains('data:1'), 'data:1이 있어야 함');
  check(log.events.contains('catch:에러1'), 'catch:에러1이 있어야 함');
  check(!log.events.contains('data:2'), '에러 후 data:2가 없어야 함');
  check(log.events.contains('onCancel'), 'onCancel이 호출되어야 함');
  check(log.events.contains('finally'), 'finally가 실행되어야 함');
  check(errorCaught, '에러가 catch되어야 함');
  check(finallyRan, 'finally가 실행되어야 함');
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
  check(log.events.contains('data:1'), 'data:1이 있어야 함');
  check(log.events.contains('handled:복구가능'), '복구가능 에러가 처리되어야 함');
  check(log.events.contains('data:2'), '복구 후 data:2가 있어야 함');
  check(log.events.contains('error:복구불가'), '복구불가 에러가 전달되어야 함');
  check(log.events.contains('data:3'), '에러 후 data:3이 있어야 함');
  check(log.events.contains('onDone'), 'onDone이 호출되어야 함');
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

  check(log.events.contains('data:1'), 'data:1이 있어야 함');
  check(log.events.contains('onDone'), 'onDone이 호출되어야 함');

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
  check(addThrew, 'close() 후 add가 StateError를 던져야 함');
  check(addErrorThrew, 'close() 후 addError가 StateError를 던져야 함');
  check(!log.events.contains('data:2'), 'close() 후 data:2가 없어야 함');
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
  } catch (e) {
    print('\n실패 발생: $e');
    exit(1);
  }
}

void exit(int code) {
  throw _ExitException(code);
}

class _ExitException implements Exception {
  final int code;
  _ExitException(this.code);
}

import 'dart:io';
import 'listener_notifiers.dart';

void main() {
  print('=== Dart 리스너 알림 중 ConcurrentModificationError 비교 ===\n');
  bool allPassed = true;
  allPassed = compareAllImplementations() && allPassed;
  print('');
  allPassed = demonstrateDeferredSpecialCases() && allPassed;
  print('');
  if (allPassed) {
    print('ALL_CHECKS_PASSED');
    exit(0);
  } else {
    print('일부 검증 실패');
    exit(1);
  }
}

bool compareAllImplementations() {
  print('공통 시나리오: 리스너 A(자기 제거), B(C 제거 + D 추가), C\n');
  bool allPassed = true;
  allPassed = testImplementation('NaiveForInNotifier', NaiveForInNotifier()) && allPassed;
  print('');
  allPassed = testImplementation('IndexLoopNotifier', IndexLoopNotifier()) && allPassed;
  print('');
  allPassed = testImplementation('SnapshotNotifier', SnapshotNotifier()) && allPassed;
  print('');
  allPassed = testImplementation('DeferredRemovalNotifier', DeferredRemovalNotifier()) && allPassed;
  return allPassed;
}

bool testImplementation(String name, ListenerNotifier notifier) {
  print('$name:');
  final List<String> callLog = [];
  late VoidCallback listenerA;
  late VoidCallback listenerB;
  late VoidCallback listenerC;
  late VoidCallback listenerD;
  listenerA = () {
    callLog.add('A');
    notifier.removeListener(listenerA);
  };
  listenerB = () {
    callLog.add('B');
    notifier.removeListener(listenerC);
    notifier.addListener(listenerD);
  };
  listenerC = () {
    callLog.add('C');
  };
  listenerD = () {
    callLog.add('D');
  };
  notifier.addListener(listenerA);
  notifier.addListener(listenerB);
  notifier.addListener(listenerC);
  print('  리스너 등록: A(자기 제거), B(C 제거 + D 추가), C');
  print('  알림 전 listenerCount: ${notifier.listenerCount}');
  String? errorType;
  try {
    notifier.notifyListeners();
  } catch (e) {
    errorType = e.runtimeType.toString();
    if (e is ConcurrentModificationError) {
      errorType = 'ConcurrentModificationError';
    }
  }
  final List<String> round1Log = List.from(callLog);
  print('  첫 알림 호출 로그: $round1Log');
  if (errorType != null) {
    print('  오류 발생: $errorType');
  }
  print('  알림 후 listenerCount: ${notifier.listenerCount}');
  if (notifier is SnapshotNotifier) {
    print('  copiedElements: ${notifier.copiedElements}');
  }
  if (notifier is DeferredRemovalNotifier) {
    print('  compactions: ${notifier.compactions}');
  }
  List<String> round2Log = [];
  if (errorType == null) {
    callLog.clear();
    try {
      notifier.notifyListeners();
    } catch (e) {
      errorType = e.runtimeType.toString();
    }
    round2Log = List.from(callLog);
    print('  두 번째 알림 호출 로그: $round2Log');
    print('  알림 후 listenerCount: ${notifier.listenerCount}');
    if (notifier is SnapshotNotifier) {
      print('  copiedElements: ${notifier.copiedElements}');
    }
    if (notifier is DeferredRemovalNotifier) {
      print('  compactions: ${notifier.compactions}');
    }
  }
  if (name == 'NaiveForInNotifier') {
    if (errorType != 'ConcurrentModificationError') {
      print('  ✗ ConcurrentModificationError가 발생하지 않음');
      return false;
    }
    if (round1Log.isEmpty || round1Log.first != 'A') {
      print('  ✗ A가 호출되지 않음');
      return false;
    }
    print('  ✓ ConcurrentModificationError 발생, A만 호출됨');
  } else if (name == 'IndexLoopNotifier') {
    if (round1Log.length != 2 || round1Log[0] != 'A' || round1Log[1] != 'C') {
      print('  ✗ 첫 알림에서 B가 건너뛰어지지 않음 (예상: [A, C], 실제: $round1Log)');
      return false;
    }
    if (round2Log.length != 2 || round2Log[0] != 'B' || round2Log[1] != 'D') {
      print('  ✗ 두 번째 알림 (예상: [B, D], 실제: $round2Log)');
      return false;
    }
    print('  ✓ 첫 알림에서 B 건너뜀, 두 번째 알림에서 B와 D 호출됨');
  } else if (name == 'SnapshotNotifier') {
    if (round1Log.length != 3 || round1Log[0] != 'A' || round1Log[1] != 'B' || round1Log[2] != 'C') {
      print('  ✗ 첫 알림에서 C가 호출되지 않음 (예상: [A, B, C], 실제: $round1Log)');
      return false;
    }
    if (round2Log.length != 2 || round2Log[0] != 'B' || round2Log[1] != 'D') {
      print('  ✗ 두 번째 알림 (예상: [B, D], 실제: $round2Log)');
      return false;
    }
    if ((notifier as SnapshotNotifier).copiedElements != 3 + 2) {
      print('  ✗ copiedElements가 5가 아님 (실제: ${notifier.copiedElements})');
      return false;
    }
    print('  ✓ 제거된 C가 첫 알림에 호출됨, A는 자기 제거로 두 번째에 없음');
  } else if (name == 'DeferredRemovalNotifier') {
    if (round1Log.length != 2 || round1Log[0] != 'A' || round1Log[1] != 'B') {
      print('  ✗ 첫 알림에서 C가 호출되지 않아야 함 (예상: [A, B], 실제: $round1Log)');
      return false;
    }
    if (round2Log.length != 2 || round2Log[0] != 'B' || round2Log[1] != 'D') {
      print('  ✗ 두 번째 알림 (예상: [B, D], 실제: $round2Log)');
      return false;
    }
    if ((notifier as DeferredRemovalNotifier).compactions != 1) {
      print('  ✗ 압축 횟수가 1이 아님 (실제: ${notifier.compactions})');
      return false;
    }
    print('  ✓ 제거된 C 미호출, A는 자기 제거로 두 번째에 없음, 압축 1회');
  }
  return true;
}

bool demonstrateDeferredSpecialCases() {
  print('DeferredRemovalNotifier 전용 동작 검증\n');
  bool allPassed = true;
  allPassed = testReentrantNotify() && allPassed;
  print('');
  allPassed = testErrorCollection() && allPassed;
  print('');
  allPassed = testDisposeRejectsDuringNotify() && allPassed;
  print('');
  allPassed = testDisposeAfterNotify() && allPassed;
  return allPassed;
}

bool testReentrantNotify() {
  print('1. 재진입 notify (리스너 안에서 notifyListeners 호출)');
  final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
  final List<String> callLog = [];
  int reentrantDepth = 0;
  late VoidCallback listenerA;
  late VoidCallback listenerB;
  listenerA = () {
    callLog.add('A');
    if (reentrantDepth == 0) {
      reentrantDepth++;
      notifier.removeListener(listenerA);
      notifier.notifyListeners();
      reentrantDepth--;
    }
  };
  listenerB = () {
    callLog.add('B');
  };
  notifier.addListener(listenerA);
  notifier.addListener(listenerB);
  final int compactionsBefore = notifier.compactions;
  notifier.notifyListeners();
  print('   호출 로그: $callLog');
  print('   압축 횟수: ${notifier.compactions} (이전: $compactionsBefore)');
  if (callLog.length != 3 || callLog[0] != 'A' || callLog[1] != 'B' || callLog[2] != 'B') {
    print('   ✗ 재진입 호출 순서가 다름 (예상: [A, B, B], 실제: $callLog)');
    return false;
  }
  if (notifier.compactions != compactionsBefore + 1) {
    print('   ✗ 압축이 1회가 아님');
    return false;
  }
  print('   ✓ 재진입 시 안쪽 notify가 실행되고 압축은 가장 바깥 종료 시 1회');
  return true;
}

bool testErrorCollection() {
  print('2. 예외 수집 (리스너 예외를 errors에 모으고 계속 실행)');
  final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
  final List<String> callLog = [];
  notifier.addListener(() {
    callLog.add('A');
  });
  notifier.addListener(() {
    callLog.add('B');
    throw Exception('B 예외');
  });
  notifier.addListener(() {
    callLog.add('C');
    throw StateError('C 예외');
  });
  notifier.addListener(() {
    callLog.add('D');
  });
  notifier.notifyListeners();
  print('   호출 로그: $callLog');
  print('   errors.length: ${notifier.errors.length}');
  if (callLog.length != 4 || callLog[0] != 'A' || callLog[1] != 'B' || callLog[2] != 'C' || callLog[3] != 'D') {
    print('   ✗ 예외 발생 후에도 모든 리스너가 호출되어야 함 (실제: $callLog)');
    return false;
  }
  if (notifier.errors.length != 2) {
    print('   ✗ errors에 2개의 오류가 기록되어야 함 (실제: ${notifier.errors.length})');
    return false;
  }
  if (notifier.errors[0].$1 is! Exception || notifier.errors[1].$1 is! StateError) {
    print('   ✗ 오류 타입이 예상과 다름');
    return false;
  }
  if (notifier.errors[0].$2.toString().isEmpty) {
    print('   ✗ StackTrace가 비어있음');
    return false;
  }
  print('   ✓ 예외를 errors에 수집하고 나머지 리스너 계속 호출, StackTrace 기록됨');
  return true;
}

bool testDisposeRejectsDuringNotify() {
  print('3. 알림 중 dispose 거부');
  final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
  final List<String> callLog = [];
  bool disposeCaught = false;
  notifier.addListener(() {
    callLog.add('A');
    try {
      notifier.dispose();
    } catch (e) {
      if (e is StateError) {
        disposeCaught = true;
        callLog.add('dispose-error');
      }
    }
  });
  notifier.addListener(() {
    callLog.add('B');
  });
  notifier.notifyListeners();
  print('   호출 로그: $callLog');
  print('   dispose StateError 발생: $disposeCaught');
  print('   errors.length: ${notifier.errors.length}');
  if (!disposeCaught) {
    print('   ✗ 알림 중 dispose가 StateError를 던지지 않음');
    return false;
  }
  if (!callLog.contains('B')) {
    print('   ✗ dispose 거부 후 나머지 리스너가 호출되지 않음');
    return false;
  }
  if (notifier.errors.isNotEmpty) {
    print('   ✗ dispose StateError가 errors에 수집되지 않아야 함 (리스너가 잡음)');
    return false;
  }
  print('   ✓ 알림 중 dispose는 StateError를 던지고 나머지 리스너는 계속 호출됨');
  return true;
}

bool testDisposeAfterNotify() {
  print('4. dispose 후 StateError');
  final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
  notifier.addListener(() {});
  notifier.notifyListeners();
  notifier.dispose();
  bool addError = false;
  try {
    notifier.addListener(() {});
  } catch (e) {
    addError = e is StateError;
  }
  bool notifyError = false;
  try {
    notifier.notifyListeners();
  } catch (e) {
    notifyError = e is StateError;
  }
  print('   dispose 후 addListener StateError: $addError');
  print('   dispose 후 notifyListeners StateError: $notifyError');
  if (!addError || !notifyError) {
    print('   ✗ dispose 후 addListener/notifyListeners가 StateError를 던지지 않음');
    return false;
  }
  print('   ✓ dispose 후 addListener/notifyListeners는 StateError');
  return true;
}

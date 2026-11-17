import 'dart:io';
import 'listener_notifiers.dart';

void main() {
  print('=== Dart 리스너 알림 중 concurrent modification 비교 ===\n');
  bool allPassed = true;
  allPassed = demonstrateNaive() && allPassed;
  print('');
  allPassed = demonstrateIndexLoop() && allPassed;
  print('');
  allPassed = demonstrateSnapshot() && allPassed;
  print('');
  allPassed = demonstrateDeferred() && allPassed;
  print('');
  if (allPassed) {
    print('ALL_CHECKS_PASSED');
    exit(0);
  } else {
    print('일부 검증 실패');
    exit(1);
  }
}

bool demonstrateNaive() {
  print('1. NaiveForInNotifier (for-in 직접 순회)');
  print('   예상: 알림 중 제거 시 ConcurrentModificationError\n');
  final NaiveForInNotifier notifier = NaiveForInNotifier();
  final List<String> callLog = [];
  late VoidCallback listenerA;
  late VoidCallback listenerB;
  late VoidCallback listenerC;
  listenerA = () {
    callLog.add('A');
    notifier.removeListener(listenerA);
  };
  listenerB = () {
    callLog.add('B');
    notifier.removeListener(listenerC);
  };
  listenerC = () {
    callLog.add('C');
  };
  notifier.addListener(listenerA);
  notifier.addListener(listenerB);
  notifier.addListener(listenerC);
  print('   리스너 3개 등록 (A는 자기 제거, B는 C 제거)');
  print('   알림 전 listenerCount: ${notifier.listenerCount}');
  bool caughtError = false;
  try {
    notifier.notifyListeners();
  } catch (e) {
    if (e is ConcurrentModificationError) {
      caughtError = true;
      print('   ConcurrentModificationError 발생: $e');
    } else {
      print('   예상하지 못한 예외: $e');
      return false;
    }
  }
  print('   호출 로그: $callLog');
  print('   알림 후 listenerCount: ${notifier.listenerCount}');
  if (!caughtError) {
    print('   ✗ ConcurrentModificationError가 발생하지 않음');
    return false;
  }
  if (callLog.isEmpty || callLog.first != 'A') {
    print('   ✗ A가 호출되지 않았거나 순서가 다름');
    return false;
  }
  print('   ✓ 예상대로 ConcurrentModificationError 발생');
  return true;
}

bool demonstrateIndexLoop() {
  print('2. IndexLoopNotifier (인덱스 for 루프)');
  print('   예상: 알림 중 제거 시 다음 리스너 건너뜀\n');
  final IndexLoopNotifier notifier = IndexLoopNotifier();
  final List<String> callLog = [];
  late VoidCallback listenerA;
  late VoidCallback listenerB;
  late VoidCallback listenerC;
  listenerA = () {
    callLog.add('A');
    notifier.removeListener(listenerA);
  };
  listenerB = () {
    callLog.add('B');
  };
  listenerC = () {
    callLog.add('C');
  };
  notifier.addListener(listenerA);
  notifier.addListener(listenerB);
  notifier.addListener(listenerC);
  print('   리스너 3개 등록 (A는 자기 제거)');
  print('   알림 전 listenerCount: ${notifier.listenerCount}');
  notifier.notifyListeners();
  print('   첫 알림 호출 로그: $callLog');
  print('   알림 후 listenerCount: ${notifier.listenerCount}');
  if (callLog.length != 2 || callLog[0] != 'A' || callLog[1] != 'C') {
    print('   ✗ B가 건너뛰어지지 않음 (예상: [A, C], 실제: $callLog)');
    return false;
  }
  callLog.clear();
  notifier.notifyListeners();
  print('   두 번째 알림 호출 로그: $callLog');
  if (callLog.length != 2 || callLog[0] != 'B' || callLog[1] != 'C') {
    print('   ✗ 두 번째 알림에서 B가 호출되지 않음 (예상: [B, C], 실제: $callLog)');
    return false;
  }
  print('   ✓ 첫 알림에서 B 건너뜀, 두 번째 알림에서 B 호출됨');
  return true;
}

bool demonstrateSnapshot() {
  print('3. SnapshotNotifier (List.of로 복사 후 순회)');
  print('   예상: 오류 없음, 제거된 리스너 그 라운드에만 호출\n');
  final SnapshotNotifier notifier = SnapshotNotifier();
  final List<String> callLog = [];
  late VoidCallback listenerA;
  late VoidCallback listenerB;
  late VoidCallback listenerC;
  late VoidCallback listenerD;
  listenerA = () {
    callLog.add('A');
    notifier.removeListener(listenerC);
  };
  listenerB = () {
    callLog.add('B');
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
  print('   리스너 3개 등록 (A는 C 제거)');
  print('   알림 전 listenerCount: ${notifier.listenerCount}');
  print('   알림 전 snapshotCopies: ${notifier.snapshotCopies}, copiedElements: ${notifier.copiedElements}');
  notifier.notifyListeners();
  print('   첫 알림 호출 로그: $callLog');
  print('   알림 후 listenerCount: ${notifier.listenerCount}');
  print('   알림 후 snapshotCopies: ${notifier.snapshotCopies}, copiedElements: ${notifier.copiedElements}');
  if (callLog.length != 3 || callLog[0] != 'A' || callLog[1] != 'B' || callLog[2] != 'C') {
    print('   ✗ 첫 알림에서 C가 호출되지 않음 (예상: [A, B, C], 실제: $callLog)');
    return false;
  }
  callLog.clear();
  final VoidCallback newListenerB = () {
    callLog.add('B');
    notifier.addListener(listenerD);
  };
  notifier.removeListener(listenerB);
  notifier.addListener(newListenerB);
  notifier.notifyListeners();
  print('   두 번째 알림 (B가 D 추가) 호출 로그: $callLog');
  print('   알림 후 listenerCount: ${notifier.listenerCount}');
  print('   알림 후 snapshotCopies: ${notifier.snapshotCopies}, copiedElements: ${notifier.copiedElements}');
  if (callLog.contains('D')) {
    print('   ✗ 알림 중 추가된 D가 이번 라운드에 호출됨');
    return false;
  }
  callLog.clear();
  notifier.notifyListeners();
  print('   세 번째 알림 호출 로그: $callLog');
  if (!callLog.contains('D')) {
    print('   ✗ 다음 라운드에 D가 호출되지 않음');
    return false;
  }
  if (notifier.copiedElements != 2 + 3 + 3) {
    print('   ✗ copiedElements가 리스너 수 × 라운드 수와 다름 (예상: 8, 실제: ${notifier.copiedElements})');
    return false;
  }
  print('   ✓ 제거된 리스너는 그 라운드에 호출, 추가된 리스너는 다음 라운드부터 호출');
  return true;
}

bool demonstrateDeferred() {
  print('4. DeferredRemovalNotifier (지연 제거, ChangeNotifier 방식)');
  print('   예상: 제거된 리스너 미호출, 압축 1회, 예외 수집\n');
  final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
  final List<String> callLog = [];
  late VoidCallback listenerA;
  late VoidCallback listenerB;
  late VoidCallback listenerC;
  late VoidCallback listenerD;
  listenerA = () {
    callLog.add('A');
    notifier.removeListener(listenerA);
    notifier.removeListener(listenerC);
  };
  listenerB = () {
    callLog.add('B');
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
  print('   리스너 3개 등록 (A는 자기 자신과 C 제거)');
  print('   알림 전 listenerCount: ${notifier.listenerCount}');
  print('   알림 전 compactions: ${notifier.compactions}');
  notifier.notifyListeners();
  print('   첫 알림 호출 로그: $callLog');
  print('   알림 후 listenerCount: ${notifier.listenerCount}');
  print('   알림 후 compactions: ${notifier.compactions}');
  if (callLog.length != 2 || callLog[0] != 'A' || callLog[1] != 'B') {
    print('   ✗ C가 호출됨 (예상: [A, B], 실제: $callLog)');
    return false;
  }
  if (notifier.compactions != 1) {
    print('   ✗ 압축 횟수가 1이 아님 (실제: ${notifier.compactions})');
    return false;
  }
  callLog.clear();
  final DeferredRemovalNotifier reentrantNotifier = DeferredRemovalNotifier();
  int reentrantDepth = 0;
  late VoidCallback reentrantListenerA;
  late VoidCallback reentrantListenerB;
  reentrantListenerA = () {
    callLog.add('RA');
    if (reentrantDepth == 0) {
      reentrantDepth++;
      reentrantNotifier.removeListener(reentrantListenerA);
      reentrantNotifier.notifyListeners();
      reentrantDepth--;
    }
  };
  reentrantListenerB = () {
    callLog.add('RB');
  };
  reentrantNotifier.addListener(reentrantListenerA);
  reentrantNotifier.addListener(reentrantListenerB);
  final int compactionsBeforeReentrant = reentrantNotifier.compactions;
  reentrantNotifier.notifyListeners();
  print('   재진입 알림 호출 로그: $callLog');
  print('   알림 후 compactions: ${reentrantNotifier.compactions}');
  if (reentrantNotifier.compactions != compactionsBeforeReentrant + 1) {
    print('   ✗ 재진입 후 압축이 1회가 아님 (예상: ${compactionsBeforeReentrant + 1}, 실제: ${reentrantNotifier.compactions})');
    return false;
  }
  callLog.clear();
  final VoidCallback errorListener = () {
    callLog.add('error');
    throw Exception('리스너 예외');
  };
  notifier.addListener(errorListener);
  notifier.addListener(listenerD);
  bool caughtError = false;
  try {
    notifier.notifyListeners();
  } catch (e) {
    caughtError = true;
    print('   예외 발생: $e');
  }
  print('   예외 발생 후 호출 로그: $callLog');
  if (!caughtError) {
    print('   ✗ 리스너 예외가 전파되지 않음');
    return false;
  }
  if (!callLog.contains('D')) {
    print('   ✗ 예외 이후 리스너 D가 호출되지 않음');
    return false;
  }
  callLog.clear();
  notifier.dispose();
  bool disposedError = false;
  try {
    notifier.addListener(() {});
  } catch (e) {
    if (e is StateError) {
      disposedError = true;
    }
  }
  if (!disposedError) {
    print('   ✗ dispose 후 addListener가 StateError를 던지지 않음');
    return false;
  }
  print('   ✓ 지연 제거, 압축 1회, 예외 수집 후 계속, dispose 후 StateError');
  return true;
}

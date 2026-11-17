import 'dart:io';
import '../src/listener_notifiers.dart';

void main() {
  final List<String> allTests = [];
  final List<String> failedTests = [];
  void test(String name, void Function() body) {
    allTests.add(name);
    try {
      body();
    } catch (e, stack) {
      failedTests.add('$name: $e');
      print('✗ $name');
      print('  오류: $e');
      print('  스택: ${stack.toString().split('\n').take(3).join('\n  ')}');
    }
  }

  void expect(bool condition, String message) {
    if (!condition) {
      throw Exception(message);
    }
  }

  print('=== 리스너 알림 ConcurrentModificationError 테스트 ===\n');
  print('언어 동작 테스트\n');
  test('List for-in 중 remove는 ConcurrentModificationError', () {
    final List<int> list = [1, 2, 3];
    bool caught = false;
    try {
      for (final int item in list) {
        if (item == 2) {
          list.remove(item);
        }
      }
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, 'ConcurrentModificationError가 발생해야 함');
    print('✓ List for-in 중 remove는 ConcurrentModificationError');
  });
  test('List 마지막 원소 순회 중 removeLast는 다음 moveNext에서 ConcurrentModificationError', () {
    final List<int> list = [1, 2, 3];
    bool caught = false;
    try {
      final Iterator<int> iterator = list.iterator;
      while (iterator.moveNext()) {
        if (iterator.current == 3) {
          list.removeLast();
        }
      }
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, 'ConcurrentModificationError가 발생해야 함');
    print('✓ List 마지막 원소 순회 중 removeLast는 다음 moveNext에서 ConcurrentModificationError');
  });
  test('Map.keys 순회 중 기존 키 값 갱신은 오류 없음', () {
    final Map<String, int> map = {'a': 1, 'b': 2};
    for (final String key in map.keys) {
      map[key] = map[key]! + 10;
    }
    expect(map['a'] == 11 && map['b'] == 12, '값 갱신 성공');
    print('✓ Map.keys 순회 중 기존 키 값 갱신은 오류 없음');
  });
  test('Map.keys 순회 중 remove는 ConcurrentModificationError', () {
    final Map<String, int> map = {'a': 1, 'b': 2};
    bool caught = false;
    try {
      for (final String key in map.keys) {
        if (key == 'a') {
          map.remove(key);
        }
      }
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, 'ConcurrentModificationError가 발생해야 함');
    print('✓ Map.keys 순회 중 remove는 ConcurrentModificationError');
  });
  test('Set 순회 중 remove는 ConcurrentModificationError', () {
    final Set<int> set = {1, 2, 3};
    bool caught = false;
    try {
      for (final int item in set) {
        if (item == 2) {
          set.remove(item);
        }
      }
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, 'ConcurrentModificationError가 발생해야 함');
    print('✓ Set 순회 중 remove는 ConcurrentModificationError');
  });
  print('\n공통 시나리오 테스트 (A 자기제거, B가 C제거+D추가, C)\n');
  test('Naive: 공통 시나리오에서 ConcurrentModificationError, A만 호출', () {
    final NaiveForInNotifier notifier = NaiveForInNotifier();
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
    bool caught = false;
    try {
      notifier.notifyListeners();
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, 'ConcurrentModificationError가 발생해야 함');
    expect(callLog.length == 1 && callLog[0] == 'A', 'A만 호출되어야 함');
    print('✓ Naive: 공통 시나리오에서 ConcurrentModificationError, A만 호출');
  });
  test('IndexLoop: 공통 시나리오에서 첫 알림 [A, C], 두 번째 [B, D]', () {
    final IndexLoopNotifier notifier = IndexLoopNotifier();
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
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'A' && callLog[1] == 'C', '첫 알림에서 B 건너뜀');
    callLog.clear();
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'B' && callLog[1] == 'D', '두 번째 알림 [B, D]');
    print('✓ IndexLoop: 공통 시나리오에서 첫 알림 [A, C], 두 번째 [B, D]');
  });
  test('Snapshot: 공통 시나리오에서 첫 알림 [A, B, C], 두 번째 [B, D]', () {
    final SnapshotNotifier notifier = SnapshotNotifier();
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
    notifier.notifyListeners();
    expect(callLog.length == 3 && callLog[0] == 'A' && callLog[1] == 'B' && callLog[2] == 'C', '첫 알림 [A, B, C], C는 제거되었지만 호출됨');
    callLog.clear();
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'B' && callLog[1] == 'D', '두 번째 알림 [B, D]');
    print('✓ Snapshot: 공통 시나리오에서 첫 알림 [A, B, C], 두 번째 [B, D]');
  });
  test('Deferred: 공통 시나리오에서 첫 알림 [A, B], 두 번째 [B, D]', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
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
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'A' && callLog[1] == 'B', '첫 알림 [A, B], C는 제거되어 미호출');
    callLog.clear();
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'B' && callLog[1] == 'D', '두 번째 알림 [B, D]');
    print('✓ Deferred: 공통 시나리오에서 첫 알림 [A, B], 두 번째 [B, D]');
  });
  print('\nNaiveForInNotifier 테스트\n');
  test('Naive: 자기 제거 리스너에서 ConcurrentModificationError, 첫 리스너는 실행됨', () {
    final NaiveForInNotifier notifier = NaiveForInNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerA;
    listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerA);
    };
    final VoidCallback listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    bool caught = false;
    try {
      notifier.notifyListeners();
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, 'ConcurrentModificationError가 발생해야 함');
    expect(callLog.isNotEmpty && callLog.first == 'A', '첫 리스너 A는 실행되어야 함');
    print('✓ Naive: 자기 제거 리스너에서 ConcurrentModificationError, 첫 리스너는 실행됨');
  });
  test('Naive: 리스너 예외가 뒤 리스너 실행을 막음', () {
    final NaiveForInNotifier notifier = NaiveForInNotifier();
    final List<String> callLog = [];
    notifier.addListener(() {
      callLog.add('A');
      throw Exception('A 예외');
    });
    notifier.addListener(() {
      callLog.add('B');
    });
    bool caught = false;
    try {
      notifier.notifyListeners();
    } catch (e) {
      caught = true;
    }
    expect(caught, '예외가 전파되어야 함');
    expect(callLog.length == 1 && callLog[0] == 'A', 'A만 실행되고 B는 실행되지 않아야 함');
    print('✓ Naive: 리스너 예외가 뒤 리스너 실행을 막음');
  });
  test('Naive: 알림 중 add도 다음 moveNext에서 ConcurrentModificationError', () {
    final NaiveForInNotifier notifier = NaiveForInNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerB;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.addListener(listenerB);
    };
    listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    bool caught = false;
    try {
      notifier.notifyListeners();
    } catch (e) {
      caught = e is ConcurrentModificationError;
    }
    expect(caught, '알림 중 add도 ConcurrentModificationError가 발생해야 함');
    expect(callLog.length == 1 && callLog[0] == 'A', 'A만 실행되어야 함');
    print('✓ Naive: 알림 중 add도 다음 moveNext에서 ConcurrentModificationError');
  });
  print('\nIndexLoopNotifier 테스트\n');
  test('IndexLoop: 자기 제거 시 다음 리스너가 건너뛰어짐', () {
    final IndexLoopNotifier notifier = IndexLoopNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerA;
    listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerA);
    };
    final VoidCallback listenerB = () {
      callLog.add('B');
    };
    final VoidCallback listenerC = () {
      callLog.add('C');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.addListener(listenerC);
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'A' && callLog[1] == 'C', 'B가 건너뛰어져야 함');
    print('✓ IndexLoop: 자기 제거 시 다음 리스너가 건너뛰어짐');
  });
  test('IndexLoop: 다음 라운드에는 호출됨', () {
    final IndexLoopNotifier notifier = IndexLoopNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerA;
    listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerA);
    };
    final VoidCallback listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.notifyListeners();
    callLog.clear();
    notifier.notifyListeners();
    expect(callLog.length == 1 && callLog[0] == 'B', '다음 라운드에는 B가 호출되어야 함');
    print('✓ IndexLoop: 다음 라운드에는 호출됨');
  });
  test('IndexLoop: 알림 중 끝에 추가된 리스너가 같은 라운드에 호출됨 (길이 재평가)', () {
    final IndexLoopNotifier notifier = IndexLoopNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerB;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.addListener(listenerB);
    };
    listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'A' && callLog[1] == 'B', '같은 라운드에 B가 호출되어야 함');
    print('✓ IndexLoop: 알림 중 끝에 추가된 리스너가 같은 라운드에 호출됨 (길이 재평가)');
  });
  print('\nSnapshotNotifier 테스트\n');
  test('Snapshot: 오류 없음', () {
    final SnapshotNotifier notifier = SnapshotNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerA;
    listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerA);
    };
    notifier.addListener(listenerA);
    notifier.notifyListeners();
    expect(callLog.isNotEmpty, '오류 없이 실행되어야 함');
    print('✓ Snapshot: 오류 없음');
  });
  test('Snapshot: 앞 리스너가 제거한 뒤 리스너가 그 라운드에 호출됨 (오래된 호출)', () {
    final SnapshotNotifier notifier = SnapshotNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerC;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerC);
    };
    final VoidCallback listenerB = () {
      callLog.add('B');
    };
    listenerC = () {
      callLog.add('C');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.addListener(listenerC);
    notifier.notifyListeners();
    expect(callLog.length == 3 && callLog[2] == 'C', 'C가 그 라운드에 호출되어야 함 (스냅샷에 포함됨)');
    print('✓ Snapshot: 앞 리스너가 제거한 뒤 리스너가 그 라운드에 호출됨 (오래된 호출)');
  });
  test('Snapshot: 제거된 리스너는 다음 라운드엔 호출 안 됨', () {
    final SnapshotNotifier notifier = SnapshotNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerC;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerC);
    };
    listenerC = () {
      callLog.add('C');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerC);
    notifier.notifyListeners();
    callLog.clear();
    notifier.notifyListeners();
    expect(!callLog.contains('C'), '다음 라운드에는 C가 호출되지 않아야 함');
    print('✓ Snapshot: 제거된 리스너는 다음 라운드엔 호출 안 됨');
  });
  test('Snapshot: 알림 중 추가된 리스너는 다음 라운드부터', () {
    final SnapshotNotifier notifier = SnapshotNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerB;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.addListener(listenerB);
    };
    listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.notifyListeners();
    expect(!callLog.contains('B'), '이번 라운드에는 B가 호출되지 않아야 함');
    callLog.clear();
    notifier.notifyListeners();
    expect(callLog.contains('B'), '다음 라운드에는 B가 호출되어야 함');
    print('✓ Snapshot: 알림 중 추가된 리스너는 다음 라운드부터');
  });
  test('Snapshot: copiedElements가 리스너 수 × 라운드 수와 일치', () {
    final SnapshotNotifier notifier = SnapshotNotifier();
    notifier.addListener(() {});
    notifier.addListener(() {});
    notifier.notifyListeners();
    notifier.notifyListeners();
    notifier.notifyListeners();
    expect(notifier.copiedElements == 2 * 3, 'copiedElements는 2 × 3 = 6이어야 함');
    expect(notifier.snapshotCopies == 3, 'snapshotCopies는 3이어야 함');
    print('✓ Snapshot: copiedElements가 리스너 수 × 라운드 수와 일치');
  });
  print('\nDeferredRemovalNotifier 테스트\n');
  test('Deferred: 제거된 리스너 미호출', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerC;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerC);
    };
    final VoidCallback listenerB = () {
      callLog.add('B');
    };
    listenerC = () {
      callLog.add('C');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.addListener(listenerC);
    notifier.notifyListeners();
    expect(!callLog.contains('C'), 'C가 호출되지 않아야 함');
    print('✓ Deferred: 제거된 리스너 미호출');
  });
  test('Deferred: 자기 제거 OK', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerA;
    listenerA = () {
      callLog.add('A');
      notifier.removeListener(listenerA);
    };
    final VoidCallback listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.notifyListeners();
    expect(callLog.length == 2 && callLog[0] == 'A' && callLog[1] == 'B', 'A, B 모두 호출되어야 함');
    print('✓ Deferred: 자기 제거 OK');
  });
  test('Deferred: 알림 중 추가 리스너 다음 라운드부터', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerB;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.addListener(listenerB);
    };
    listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.notifyListeners();
    expect(!callLog.contains('B'), '이번 라운드에는 B가 호출되지 않아야 함');
    callLog.clear();
    notifier.notifyListeners();
    expect(callLog.contains('B'), '다음 라운드에는 B가 호출되어야 함');
    print('✓ Deferred: 알림 중 추가 리스너 다음 라운드부터');
  });
  test('Deferred: 알림 중 추가된 리스너를 같은 라운드에서 제거하면 한 번도 호출 안 됨', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerB;
    final VoidCallback listenerA = () {
      callLog.add('A');
      notifier.addListener(listenerB);
      notifier.removeListener(listenerB);
    };
    listenerB = () {
      callLog.add('B');
    };
    notifier.addListener(listenerA);
    notifier.notifyListeners();
    expect(!callLog.contains('B'), '이번 라운드에 B 호출 안 됨');
    final int countAfter = notifier.listenerCount;
    final int compactionsAfter = notifier.compactions;
    callLog.clear();
    notifier.notifyListeners();
    expect(!callLog.contains('B'), '다음 라운드에도 B 호출 안 됨');
    expect(countAfter == 1, 'listenerCount는 1 (A만)');
    expect(compactionsAfter == 1, '압축 1회');
    print('✓ Deferred: 알림 중 추가된 리스너를 같은 라운드에서 제거하면 한 번도 호출 안 됨');
  });
  test('Deferred: 재진입 notify 동작과 압축 1회', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final List<String> callLog = [];
    late VoidCallback listenerA;
    late VoidCallback listenerB;
    int reentrantDepth = 0;
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
    expect(notifier.compactions == compactionsBefore + 1, '압축은 1회만 발생해야 함');
    expect(callLog.length == 3 && callLog[0] == 'A' && callLog[1] == 'B' && callLog[2] == 'B', '재진입 호출 순서 확인');
    print('✓ Deferred: 재진입 notify 동작과 압축 1회');
  });
  test('Deferred: 알림 중 listenerCount 정확', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    late VoidCallback listenerA;
    late VoidCallback listenerC;
    late VoidCallback listenerD;
    listenerA = () {
      notifier.removeListener(listenerC);
      notifier.addListener(listenerD);
      expect(notifier.listenerCount == 3, '알림 중 listenerCount는 3이어야 함 (A, B, D)');
    };
    final VoidCallback listenerB = () {};
    listenerC = () {};
    listenerD = () {};
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.addListener(listenerC);
    notifier.notifyListeners();
    print('✓ Deferred: 알림 중 listenerCount 정확');
  });
  test('Deferred: 중복 add/remove 의미', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final List<String> callLog = [];
    final VoidCallback listener = () {
      callLog.add('L');
    };
    notifier.addListener(listener);
    notifier.addListener(listener);
    notifier.notifyListeners();
    expect(callLog.length == 2, '같은 리스너를 두 번 add하면 두 번 호출되어야 함');
    callLog.clear();
    notifier.removeListener(listener);
    notifier.notifyListeners();
    expect(callLog.length == 1, 'remove는 앞쪽 하나만 제거해야 함');
    print('✓ Deferred: 중복 add/remove 의미');
  });
  test('Deferred: 예외 수집 후 계속 (errors에 누적, notifyListeners는 던지지 않음)', () {
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
    });
    notifier.notifyListeners();
    expect(callLog.length == 3, 'A, B, C 모두 호출되어야 함');
    expect(notifier.errors.length == 1, 'errors에 1개의 오류가 기록되어야 함');
    expect(notifier.errors[0].$1 is Exception, '오류 타입이 Exception이어야 함');
    expect(notifier.errors[0].$2.toString().isNotEmpty, 'StackTrace가 비어있지 않아야 함');
    print('✓ Deferred: 예외 수집 후 계속 (errors에 누적, notifyListeners는 던지지 않음)');
  });
  test('Deferred: 두 리스너가 예외를 던지면 errors에 순서대로 2개', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    notifier.addListener(() {
      throw Exception('첫 예외');
    });
    notifier.addListener(() {
      throw StateError('두 번째 예외');
    });
    notifier.notifyListeners();
    expect(notifier.errors.length == 2, 'errors에 2개의 오류가 기록되어야 함');
    expect(notifier.errors[0].$1 is Exception, '첫 오류는 Exception');
    expect(notifier.errors[1].$1 is StateError, '두 번째 오류는 StateError');
    print('✓ Deferred: 두 리스너가 예외를 던지면 errors에 순서대로 2개');
  });
  test('Deferred: 재진입 안쪽 오류는 정확히 1번만 기록', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    int reentrantDepth = 0;
    notifier.addListener(() {
      if (reentrantDepth == 0) {
        reentrantDepth++;
        notifier.notifyListeners();
        reentrantDepth--;
      } else {
        throw Exception('안쪽 예외');
      }
    });
    notifier.notifyListeners();
    expect(notifier.errors.length == 1, 'errors에 1개만 기록되어야 함');
    expect(notifier.errors[0].$1.toString().contains('안쪽 예외'), '안쪽 예외가 기록되어야 함');
    print('✓ Deferred: 재진입 안쪽 오류는 정확히 1번만 기록');
  });
  test('Deferred: 등록 안 된 remove false', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    final VoidCallback listener = () {};
    final bool removed = notifier.removeListener(listener);
    expect(!removed, '등록 안 된 리스너 remove는 false를 반환해야 함');
    print('✓ Deferred: 등록 안 된 remove false');
  });
  test('Deferred: 리스너 0개 notify', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    notifier.notifyListeners();
    expect(notifier.listenerCount == 0, '리스너 0개일 때 notify는 오류 없이 실행되어야 함');
    print('✓ Deferred: 리스너 0개 notify');
  });
  test('Deferred: 알림 중 모든 리스너 제거 후 count 0', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    late VoidCallback listenerA;
    late VoidCallback listenerB;
    listenerA = () {
      notifier.removeListener(listenerA);
      notifier.removeListener(listenerB);
    };
    listenerB = () {};
    notifier.addListener(listenerA);
    notifier.addListener(listenerB);
    notifier.notifyListeners();
    expect(notifier.listenerCount == 0, '모든 리스너 제거 후 count는 0이어야 함');
    print('✓ Deferred: 알림 중 모든 리스너 제거 후 count 0');
  });
  test('Deferred: 알림 중 dispose는 StateError를 던지고 나머지 리스너 계속 호출', () {
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
        }
      }
    });
    notifier.addListener(() {
      callLog.add('B');
    });
    notifier.notifyListeners();
    expect(disposeCaught, '알림 중 dispose가 StateError를 던져야 함');
    expect(callLog.contains('B'), 'dispose 거부 후 나머지 리스너가 호출되어야 함');
    expect(notifier.errors.isEmpty, 'dispose StateError는 리스너가 잡았으므로 errors에 없어야 함');
    print('✓ Deferred: 알림 중 dispose는 StateError를 던지고 나머지 리스너 계속 호출');
  });
  test('Deferred: dispose 후 StateError', () {
    final DeferredRemovalNotifier notifier = DeferredRemovalNotifier();
    notifier.dispose();
    bool addError = false;
    try {
      notifier.addListener(() {});
    } catch (e) {
      addError = e is StateError;
    }
    expect(addError, 'dispose 후 addListener는 StateError를 던져야 함');
    bool notifyError = false;
    try {
      notifier.notifyListeners();
    } catch (e) {
      notifyError = e is StateError;
    }
    expect(notifyError, 'dispose 후 notifyListeners는 StateError를 던져야 함');
    print('✓ Deferred: dispose 후 StateError');
  });
  print('\n=== 테스트 결과 ===');
  print('전체: ${allTests.length}개');
  print('통과: ${allTests.length - failedTests.length}개');
  print('실패: ${failedTests.length}개');
  if (failedTests.isNotEmpty) {
    print('\n실패한 테스트:');
    for (final String failed in failedTests) {
      print('  - $failed');
    }
    exit(1);
  } else {
    print('\n모든 테스트 통과!');
    exit(0);
  }
}

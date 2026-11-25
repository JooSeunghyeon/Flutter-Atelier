import 'dart:io';

import '../src/lazy_iterable_probe.dart';
import '../src/memoized_iterable.dart';

Future<void> main() async {
  final List<String> allTests = [];
  final List<String> failedTests = [];

  Future<void> test(String name, Future<void> Function() body) async {
    allTests.add(name);
    try {
      await body();
      print('✓ $name');
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

  print('=== Iterable 지연 평가, 재평가, 스냅샷, 메모이즈 테스트 ===\n');

  print('지연성 테스트\n');

  await test('지연: map 생성 시점에는 콜백을 실행하지 않음', () async {
    CallCounter counter = CallCounter();
    [1, 2, 3].map(counter.wrap((int x) => x * 10));
    expect(counter.count == 0, 'map 생성 직후 콜백 호출 0회');
  });

  await test('지연: length 조회는 콜백을 실행하지 않음 (MappedListIterable)', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 2, 3].map(counter.wrap((int x) => x * 10));
    final int length = lazy.length;
    expect(length == 3, 'length는 3');
    expect(counter.count == 0, 'length 조회는 콜백을 실행하지 않음');
  });

  await test('지연: isEmpty 조회는 콜백을 실행하지 않음', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 2, 3].map(counter.wrap((int x) => x * 10));
    final bool empty = lazy.isEmpty;
    expect(!empty, 'isEmpty는 false');
    expect(counter.count == 0, 'isEmpty 조회는 콜백을 실행하지 않음');
  });

  print('\n재평가 테스트\n');

  await test('재평가: toList 호출마다 콜백을 다시 실행', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 2, 3].map(counter.wrap((int x) => x * 10));
    lazy.toList();
    expect(counter.count == 3, '첫 toList: 콜백 3회');
    lazy.toList();
    expect(counter.count == 6, '두 번째 toList: 콜백 총 6회');
  });

  await test('재평가: forEach 호출마다 콜백을 다시 실행', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 2, 3].map(counter.wrap((int x) => x * 10));
    lazy.forEach((int x) {});
    expect(counter.count == 3, '첫 forEach: 콜백 3회');
    lazy.forEach((int x) {});
    expect(counter.count == 6, '두 번째 forEach: 콜백 총 6회');
  });

  await test('재평가: iterator 순회마다 콜백을 다시 실행', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 2, 3].map(counter.wrap((int x) => x * 10));
    for (final int _ in lazy) {}
    expect(counter.count == 3, '첫 순회: 콜백 3회');
    for (final int _ in lazy) {}
    expect(counter.count == 6, '두 번째 순회: 콜백 총 6회');
  });

  print('\n스냅샷(toList) 테스트\n');

  await test('스냅샷: toList는 한 번 평가하여 독립적인 List 생성', () async {
    CallCounter counter = CallCounter();
    final List<int> src = [1, 2, 3];
    final Iterable<int> lazy = src.map(counter.wrap((int x) => x * 10));
    final List<int> snapshot = lazy.toList();
    expect(counter.count == 3, 'toList: 콜백 3회');
    expect(snapshot.toString() == '[10, 20, 30]', 'snapshot 내용');
    src.add(4);
    expect(snapshot.length == 3, '원본 변경 후에도 snapshot 길이는 3');
    expect(lazy.toList().length == 4, '지연 Iterable은 원본 변경 반영');
  });

  await test('스냅샷: 스냅샷은 원본과 독립적', () async {
    final List<int> src = [1, 2, 3];
    final Iterable<int> lazy = src.map((int x) => x * 10);
    final List<int> snapshot = lazy.toList();
    snapshot.add(100);
    expect(src.length == 3, '스냅샷 변경은 원본에 영향 없음');
    src.add(4);
    expect(snapshot.length == 4, '스냅샷에 add(100) 했으므로 길이 4');
  });

  print('\n메모이즈 테스트\n');

  await test('메모이즈: 콜백을 원소당 1회만 실행', () async {
    CallCounter counter = CallCounter();
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [1, 2, 3].map(counter.wrap((int x) => x * 10)),
    );
    memoized.toList();
    expect(counter.count == 3, '첫 toList: 콜백 3회');
    memoized.toList();
    expect(counter.count == 3, '두 번째 toList: 콜백 추가 호출 없음');
  });

  await test('메모이즈: 여러 순회에서도 콜백은 1회만', () async {
    CallCounter counter = CallCounter();
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [1, 2, 3].map(counter.wrap((int x) => x * 10)),
    );
    for (final int _ in memoized) {}
    expect(counter.count == 3, '첫 순회: 콜백 3회');
    for (final int _ in memoized) {}
    expect(counter.count == 3, '두 번째 순회: 콜백 추가 호출 없음');
  });

  await test('메모이즈: 부분 소비 후 다른 Iterator가 이어받음', () async {
    CallCounter counter = CallCounter();
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [1, 2, 3, 4, 5].map(counter.wrap((int x) => x * 10)),
    );
    final Iterator<int> iter1 = memoized.iterator;
    iter1.moveNext();
    iter1.moveNext();
    expect(counter.count == 2, '첫 Iterator 2개 소비: 콜백 2회');
    final Iterator<int> iter2 = memoized.iterator;
    iter2.moveNext();
    iter2.moveNext();
    iter2.moveNext();
    expect(counter.count == 3, '두 번째 Iterator 3개 소비: 콜백 1회 추가');
  });

  await test('메모이즈: 여러 Iterator 교차 순회', () async {
    CallCounter counter = CallCounter();
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [1, 2, 3, 4].map(counter.wrap((int x) => x * 10)),
    );
    final Iterator<int> iter1 = memoized.iterator;
    final Iterator<int> iter2 = memoized.iterator;
    iter1.moveNext();
    expect(counter.count == 1, 'iter1 1개: 콜백 1회');
    iter2.moveNext();
    iter2.moveNext();
    expect(counter.count == 2, 'iter2 2개: 콜백 1회 추가');
    iter1.moveNext();
    iter1.moveNext();
    expect(counter.count == 3, 'iter1 2개 더: 콜백 1회 추가');
  });

  print('\n예외 처리 테스트\n');

  await test('예외: 지연 Iterable은 소비 시점에 예외 발생', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 0, 2].map(counter.wrap((int x) => 10 ~/ x));
    expect(counter.count == 0, 'map 생성: 예외 없음');
    bool caught = false;
    try {
      lazy.toList();
    } catch (e) {
      caught = true;
      expect(e is UnsupportedError, '예외는 UnsupportedError');
    }
    expect(caught, 'toList에서 예외 발생');
  });

  await test('예외: first는 첫 원소만 평가하므로 예외 회피 가능', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [1, 0, 2].map(counter.wrap((int x) => 10 ~/ x));
    final int first = lazy.first;
    expect(first == 10, 'first는 10');
    expect(counter.count == 1, '콜백 1회만 호출');
  });

  await test('예외: 메모이즈는 예외 발생 시 캐시하지 않고 재시도', () async {
    int callCount = 0;
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [1, 0, 2].map((int x) {
        callCount++;
        return 10 ~/ x;
      }),
    );
    bool caught = false;
    try {
      memoized.toList();
    } catch (e) {
      caught = true;
    }
    expect(caught, '첫 번째 toList에서 예외 발생');
    final int firstCall = callCount;
    expect(firstCall >= 2, '첫 번째 호출에서 최소 2개 평가');
    caught = false;
    try {
      memoized.toList();
    } catch (e) {
      caught = true;
    }
    expect(caught, '두 번째 toList에서도 예외 발생');
    expect(callCount > firstCall, '예외 후 재시도 시 콜백 재실행');
  });

  print('\n조기 종료 테스트\n');

  await test('조기 종료: first는 첫 원소만 평가', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy =
        [1, 2, 3, 4, 5].map(counter.wrap((int x) => x * 10));
    final int first = lazy.first;
    expect(first == 10, 'first는 10');
    expect(counter.count == 1, '콜백 1회만 호출');
  });

  await test('조기 종료: any는 조건 만족 시 중단', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy =
        [1, 2, 3, 4, 5].map(counter.wrap((int x) => x * 10));
    final bool any = lazy.any((int x) => x == 30);
    expect(any, 'any는 true');
    expect(counter.count == 3, '콜백 3회 호출 (조기 종료)');
  });

  await test('조기 종료: take는 지정 개수만 평가', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy =
        [1, 2, 3, 4, 5].map(counter.wrap((int x) => x * 10));
    final List<int> taken = lazy.take(2).toList();
    expect(taken.toString() == '[10, 20]', 'take(2) 결과');
    expect(counter.count == 2, '콜백 2회만 호출');
  });

  await test('조기 종료: where + first는 조건 만족까지만 평가', () async {
    final List<int> seen = [];
    final Iterable<int> lazy = [1, 2, 3, 4, 5].where((int x) {
      seen.add(x);
      return x > 2;
    });
    final int first = lazy.first;
    expect(first == 3, 'first는 3');
    expect(seen.toString() == '[1, 2, 3]', '조건 만족까지만 평가');
  });

  print('\n경계 조건 테스트\n');

  await test('경계: 빈 입력', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = <int>[].map(counter.wrap((int x) => x * 10));
    final List<int> result = lazy.toList();
    expect(result.isEmpty, '빈 리스트');
    expect(counter.count == 0, '콜백 호출 없음');
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(<int>[]);
    expect(memoized.toList().isEmpty, '메모이즈도 빈 리스트');
  });

  await test('경계: 원소 1개', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> lazy = [5].map(counter.wrap((int x) => x * 10));
    final List<int> result = lazy.toList();
    expect(result.toString() == '[50]', '결과는 [50]');
    expect(counter.count == 1, '콜백 1회');
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [5].map((int x) => x * 10),
    );
    expect(memoized.toList().toString() == '[50]', '메모이즈도 [50]');
  });

  await test('경계: null 허용 원소', () async {
    final Iterable<int?> lazy = <int?>[1, null, 3].map((int? x) => x);
    final List<int?> result = lazy.toList();
    expect(result.length == 3, '길이 3');
    expect(result[1] == null, '두 번째 원소는 null');
    final MemoizedIterable<int?> memoized = MemoizedIterable<int?>(
      <int?>[1, null, 3],
    );
    expect(memoized.toList()[1] == null, '메모이즈도 null 처리');
  });

  print('\n원본 변경 테스트\n');

  await test('원본 변경: 지연 Iterable은 원본 변경을 반영', () async {
    final List<int> src = [1, 2];
    final Iterable<int> lazy = src.map((int x) => x * 10);
    expect(lazy.toList().length == 2, '초기 길이 2');
    src.add(3);
    expect(lazy.toList().length == 3, '원본 add 후 길이 3');
  });

  await test('원본 변경: 스냅샷은 원본 변경을 반영하지 않음', () async {
    final List<int> src = [1, 2];
    final Iterable<int> lazy = src.map((int x) => x * 10);
    final List<int> snapshot = lazy.toList();
    src.add(3);
    expect(snapshot.length == 2, '스냅샷 길이는 여전히 2');
  });

  await test('원본 변경: 메모이즈는 캐시 고정', () async {
    final List<int> src = [1, 2];
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      src.map((int x) => x * 10),
    );
    final List<int> cached = memoized.toList();
    src.add(3);
    expect(memoized.toList().length == 2, '메모이즈는 캐시된 길이 2 유지');
    expect(cached.toString() == memoized.toList().toString(), '결과 일치');
  });

  await test('원본 변경: 순회 중 원본 변경은 ConcurrentModificationError', () async {
    final List<int> src = [1, 2, 3];
    final Iterable<int> lazy = src.map((int x) => x * 10);
    bool caught = false;
    try {
      for (final int v in lazy) {
        if (v == 10) {
          src.add(4);
        }
      }
    } catch (e) {
      caught = true;
      expect(
          e is ConcurrentModificationError, '예외는 ConcurrentModificationError');
    }
    expect(caught, '순회 중 원본 변경 시 예외 발생');
  });

  print('\n체인 테스트\n');

  await test('체인: map → where 호출 횟수', () async {
    CallCounter counter = CallCounter();
    final Iterable<int> chain = [1, 2, 3, 4, 5]
        .map(counter.wrap((int x) => x * 10))
        .where((int x) => x > 20);
    final int length1 = chain.length;
    expect(length1 == 3, '결과 3개');
    expect(counter.count == 5, '첫 length: 콜백 5회');
    final int length2 = chain.length;
    expect(length2 == 3, '결과 여전히 3개');
    expect(counter.count == 10, '두 번째 length: 콜백 총 10회');
  });

  await test('체인: 메모이즈 체인은 호출 횟수 유지', () async {
    CallCounter counter = CallCounter();
    final MemoizedIterable<int> memoized = MemoizedIterable<int>(
      [1, 2, 3, 4, 5]
          .map(counter.wrap((int x) => x * 10))
          .where((int x) => x > 20),
    );
    memoized.toList();
    expect(counter.count == 5, '첫 toList: 콜백 5회');
    memoized.toList();
    expect(counter.count == 5, '두 번째 toList: 콜백 추가 호출 없음');
  });

  print('\n=== 테스트 결과 ===');
  print('전체: ${allTests.length}개');
  print('통과: ${allTests.length - failedTests.length}개');
  print('실패: ${failedTests.length}개');

  if (failedTests.isNotEmpty) {
    print('\n실패한 테스트:');
    for (final String failure in failedTests) {
      print('  - $failure');
    }
    exit(1);
  }

  print('\n모든 테스트 통과!');
  exit(0);
}

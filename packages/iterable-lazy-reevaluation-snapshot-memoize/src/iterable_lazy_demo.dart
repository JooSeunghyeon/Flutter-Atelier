import 'dart:io';

import 'lazy_iterable_probe.dart';
import 'memoized_iterable.dart';

void main() {
  bool allPassed = true;

  void check(bool condition, String message) {
    if (!condition) {
      print('✗ 실패: $message');
      allPassed = false;
    } else {
      print('✓ $message');
    }
  }

  print('=== Iterable 지연 평가, 재평가, 스냅샷, 메모이즈 비교 ===\n');

  print('1. 지연 평가: map 생성 시점에는 콜백을 실행하지 않는다\n');
  CallCounter counter1 = CallCounter();
  final List<int> src1 = [1, 2, 3, 4];
  final Iterable<int> lazy1 = src1.map(counter1.wrap((int x) => x * 10));
  check(counter1.count == 0, '   map 생성 직후 콜백 호출 0회');
  final int length1 = lazy1.length;
  check(length1 == 4 && counter1.count == 0,
      '   length 조회는 콜백을 실행하지 않음 (MappedListIterable 최적화)');

  print('\n2. 재평가: 지연 Iterable을 순회할 때마다 콜백을 다시 실행한다\n');
  CallCounter counter2 = CallCounter();
  final List<int> src2 = [1, 2, 3];
  final Iterable<int> lazy2 = src2.map(counter2.wrap((int x) => x * 10));
  final List<int> result2a = lazy2.toList();
  final int calls2a = counter2.count;
  check(calls2a == 3, '   첫 번째 toList(): 콜백 3회 호출');
  final List<int> result2b = lazy2.toList();
  final int calls2b = counter2.count;
  check(calls2b == 6, '   두 번째 toList(): 콜백 총 6회 호출 (3회 추가)');
  check(result2a.toString() == result2b.toString(), '   결과는 동일: $result2a');

  print('\n3. 스냅샷(toList): 한 번 평가하고 독립적인 List를 만든다\n');
  CallCounter counter3 = CallCounter();
  final List<int> src3 = [1, 2, 3];
  final Iterable<int> lazy3 = src3.map(counter3.wrap((int x) => x * 10));
  final List<int> snapshot3 = lazy3.toList();
  final int calls3a = counter3.count;
  check(calls3a == 3, '   toList(): 콜백 3회 호출');
  src3.add(4);
  final List<int> lazy3After = lazy3.toList();
  final int calls3b = counter3.count;
  check(calls3b == 7, '   원본 변경 후 lazy.toList(): 콜백 4회 추가 (총 7회)');
  check(snapshot3.length == 3, '   스냅샷은 원본 변경에 영향받지 않음: $snapshot3');
  check(lazy3After.length == 4, '   지연 Iterable은 원본 변경을 반영: $lazy3After');

  print('\n4. 메모이즈: 콜백을 원소당 1회만 실행하고 캐시한다\n');
  CallCounter counter4 = CallCounter();
  final List<int> src4 = [1, 2, 3];
  final MemoizedIterable<int> memoized4 = MemoizedIterable<int>(
    src4.map(counter4.wrap((int x) => x * 10)),
  );
  final List<int> result4a = memoized4.toList();
  final int calls4a = counter4.count;
  check(calls4a == 3, '   첫 번째 toList(): 콜백 3회 호출');
  final List<int> result4b = memoized4.toList();
  final int calls4b = counter4.count;
  check(calls4b == 3, '   두 번째 toList(): 콜백 추가 호출 없음 (메모이즈됨)');
  check(result4a.toString() == result4b.toString(), '   결과는 동일: $result4a');

  print('\n5. 예외 시점: 지연 Iterable은 소비 시점에 예외가 발생한다\n');
  CallCounter counter5 = CallCounter();
  final Iterable<int> div5 = [1, 0, 2].map(counter5.wrap((int x) => 10 ~/ x));
  check(counter5.count == 0, '   map 생성: 예외 없음');
  try {
    div5.toList();
    check(false, '   toList(): 예외가 발생해야 함');
  } catch (e) {
    check(e is UnsupportedError, '   toList(): UnsupportedError 발생');
  }
  counter5.reset();
  final int first5 = div5.first;
  check(first5 == 10 && counter5.count == 1, '   first: 첫 원소만 평가, 예외 없음 (10)');

  print('\n6. 조기 종료: first, any, take 등은 필요한 만큼만 평가한다\n');
  CallCounter counter6 = CallCounter();
  final Iterable<int> lazy6 =
      [1, 2, 3, 4, 5].map(counter6.wrap((int x) => x * 10));
  final int first6 = lazy6.first;
  check(first6 == 10 && counter6.count == 1, '   first: 콜백 1회만 호출');
  counter6.reset();
  final bool any6 = lazy6.any((int x) => x == 30);
  check(any6 && counter6.count == 3, '   any((x)=>x==30): 콜백 3회 호출 (조기 종료)');
  counter6.reset();
  final List<int> take6 = lazy6.take(2).toList();
  check(take6.length == 2 && counter6.count == 2,
      '   take(2).toList(): 콜백 2회만 호출');

  print('\n7. 체인: map → where 체인도 순회마다 모든 단계를 재실행한다\n');
  CallCounter counter7 = CallCounter();
  final Iterable<int> chain7 = [1, 2, 3, 4, 5]
      .map(counter7.wrap((int x) => x * 10))
      .where((int x) => x > 20);
  final int length7a = chain7.length;
  final int calls7a = counter7.count;
  check(length7a == 3 && calls7a == 5, '   첫 번째 length: 콜백 5회 호출, 결과 3개');
  final int length7b = chain7.length;
  final int calls7b = counter7.count;
  check(length7b == 3 && calls7b == 10, '   두 번째 length: 콜백 5회 추가 (총 10회)');

  print('\n8. 메모이즈 부분 소비: Iterator를 중간에 멈춰도 다음 Iterator가 이어받는다\n');
  CallCounter counter8 = CallCounter();
  final MemoizedIterable<int> memoized8 = MemoizedIterable<int>(
    [1, 2, 3, 4, 5].map(counter8.wrap((int x) => x * 10)),
  );
  final Iterator<int> iter8a = memoized8.iterator;
  iter8a.moveNext();
  iter8a.moveNext();
  check(counter8.count == 2, '   첫 Iterator 2개 소비: 콜백 2회');
  final Iterator<int> iter8b = memoized8.iterator;
  iter8b.moveNext();
  iter8b.moveNext();
  iter8b.moveNext();
  check(counter8.count == 3, '   두 번째 Iterator 3개 소비: 콜백 1회 추가 (총 3회)');

  print('\n9. 원본 변경 반영 차이\n');
  CallCounter counter9 = CallCounter();
  final List<int> src9 = [1, 2];
  final Iterable<int> lazy9 = src9.map(counter9.wrap((int x) => x * 10));
  final List<int> snapshot9 = lazy9.toList();
  final MemoizedIterable<int> memoized9 = MemoizedIterable<int>(
    src9.map((int x) => x * 10),
  );
  memoized9.toList();
  src9.add(3);
  final List<int> lazyAfter9 = lazy9.toList();
  final List<int> snapshotCheck9 = snapshot9.toList();
  final List<int> memoAfter9 = memoized9.toList();
  check(lazyAfter9.length == 3, '   A(지연): 원본 변경 반영됨 $lazyAfter9');
  check(snapshotCheck9.length == 2, '   B(스냅샷): 원본 변경 반영 안 됨 $snapshotCheck9');
  check(memoAfter9.length == 2, '   C(메모이즈): 캐시된 결과만 반환 $memoAfter9');

  print('\n10. elementAt과 contains 최적화 비교\n');
  CallCounter counter10a = CallCounter();
  final Iterable<int> lazy10a =
      [1, 2, 3, 4, 5].map(counter10a.wrap((int x) => x * 10));
  final int elem10a = lazy10a.elementAt(3);
  check(elem10a == 40 && counter10a.count == 1,
      '   lazy.elementAt(3): 콜백 1회 (MappedListIterable 최적화)');
  CallCounter counter10b = CallCounter();
  final Iterable<int> lazy10b =
      [1, 2, 3, 4, 5].map(counter10b.wrap((int x) => x * 10));
  final bool contains10b = lazy10b.contains(30);
  check(contains10b && counter10b.count == 3,
      '   lazy.contains(30): 콜백 3회 (조기 종료)');

  print('\n=== 설계 비교 요약 ===\n');
  print('| 설계 | 콜백 호출 | 예외 시점 | 원본 변경 | 메모리 |');
  print('|------|----------|----------|----------|--------|');
  print('| A(지연) | 순회마다 전체 | 소비 시점 | 반영됨 | 최소 |');
  print('| B(스냅샷) | 1회 | toList 시점 | 반영 안 됨 | 전체 복사 |');
  print('| C(메모이즈) | 원소당 1회 | 첫 소비 시점 | 캐시 고정 | 점진적 증가 |');

  print('');
  if (allPassed) {
    print('ALL_CHECKS_PASSED');
    exit(0);
  } else {
    print('일부 검증 실패');
    exit(1);
  }
}

import 'dart:io';

int _attempt = 0;

String flaky() {
  _attempt++;
  if (_attempt == 1) {
    throw Exception('첫 시도 실패');
  }
  return '성공($_attempt번째 시도)';
}

class LateFinalRetry {
  late final String value = flaky();
}

int _reentrantAttempt = 0;

class LateFinalReentrant {
  late final String value = _getValue();

  String _getValue() {
    _reentrantAttempt++;
    if (_reentrantAttempt == 1) {
      try {
        return value;
      } catch (e) {
        rethrow;
      }
    }
    return '완료';
  }
}

class LateFinalSelfCycle {
  late final int self = self + 1;
}

class LateFinalMutualCycleA {
  late final LateFinalMutualCycleB b = LateFinalMutualCycleB();
  late final int value = b.value + 1;
}

class LateFinalMutualCycleB {
  late final LateFinalMutualCycleA a = LateFinalMutualCycleA();
  late final int value = a.value + 1;
}

int _topAttempt = 0;

String topFlaky() {
  _topAttempt++;
  if (_topAttempt == 1) {
    throw Exception('최상위 첫 시도 실패');
  }
  return '최상위 성공($_topAttempt번째 시도)';
}

final topLevelValue = topFlaky();

class RememberFailureCache {
  Object? _cached;
  StackTrace? _stackTrace;
  bool _hasValue = false;
  bool _hasFailed = false;

  int callCount = 0;

  T get<T>(T Function() compute) {
    callCount++;
    if (_hasFailed) {
      Error.throwWithStackTrace(_cached!, _stackTrace!);
    }
    if (_hasValue) {
      return _cached as T;
    }
    try {
      final result = compute();
      _cached = result;
      _hasValue = true;
      return result;
    } catch (e, stackTrace) {
      _hasFailed = true;
      _cached = e;
      _stackTrace = stackTrace;
      rethrow;
    }
  }

  void reset() {
    _cached = null;
    _stackTrace = null;
    _hasValue = false;
    _hasFailed = false;
    callCount = 0;
  }
}

class RetryLimitCache {
  Object? _cached;
  bool _hasValue = false;
  int _failCount = 0;
  final int maxAttempts;

  int callCount = 0;

  RetryLimitCache(this.maxAttempts) {
    if (maxAttempts < 1) {
      throw ArgumentError('maxAttempts는 1 이상이어야 합니다: $maxAttempts');
    }
  }

  T get<T>(T Function() compute) {
    callCount++;
    if (_hasValue) {
      return _cached as T;
    }
    if (_failCount >= maxAttempts) {
      throw Exception('재시도 한도 초과($_failCount회 실패)');
    }
    try {
      final result = compute();
      _cached = result;
      _hasValue = true;
      return result;
    } catch (e) {
      _failCount++;
      rethrow;
    }
  }

  void reset() {
    _cached = null;
    _hasValue = false;
    _failCount = 0;
    callCount = 0;
  }
}

void checkEquals<T>(T actual, T expected, String label) {
  if (actual != expected) {
    print('실패 ($label): 기대=$expected, 실제=$actual');
    exit(1);
  }
}

void checkTrue(bool condition, String label) {
  if (!condition) {
    print('실패 ($label): 조건이 false');
    exit(1);
  }
}

void testLateFinalRetry() {
  print('\n=== late final 초기화 실패 후 재시도 ===');
  _attempt = 0;
  final obj = LateFinalRetry();

  bool firstAccessThrew = false;
  try {
    print('첫 접근 시도: ${obj.value}');
  } catch (e) {
    print('첫 접근 예외: $e');
    firstAccessThrew = true;
  }

  checkTrue(firstAccessThrew, '첫 접근은 예외를 던져야 함');
  checkEquals(_attempt, 1, '첫 접근 후 attempt는 1');

  final secondValue = obj.value;
  print('두 번째 접근: $secondValue');
  checkEquals(_attempt, 2, '두 번째 접근 후 attempt는 2');
  checkEquals(secondValue, '성공(2번째 시도)', '두 번째 접근 성공 값 확인');

  final thirdValue = obj.value;
  print('세 번째 접근: $thirdValue');
  checkEquals(_attempt, 2, '세 번째 접근 후에도 attempt는 2 (재실행 안 함)');
  checkEquals(thirdValue, '성공(2번째 시도)', '세 번째 접근도 같은 값');

  print('통과');
}

void testLateFinalReentrant() {
  print('\n=== late final 재진입 ===');
  _reentrantAttempt = 0;
  final obj = LateFinalReentrant();

  bool threw = false;
  String? errorMessage;
  try {
    print('재진입 시도: ${obj.value}');
  } catch (e) {
    print('재진입 예외: $e (${e.runtimeType})');
    threw = true;
    errorMessage = e.toString();
  }

  checkTrue(threw, '재진입은 예외를 던져야 함');
  checkTrue(
    errorMessage != null && errorMessage.contains('LateInitializationError'),
    '재진입 시 LateInitializationError 발생',
  );
  checkEquals(_reentrantAttempt, 2, '초기화식은 2번 실행됨 (바깥 + 안쪽 재진입)');

  final valueAfterError = obj.value;
  print('오류 후 필드 값: $valueAfterError');
  checkEquals(valueAfterError, '완료', '오류 후 필드는 안쪽 실행이 저장한 값을 가짐');
  checkEquals(_reentrantAttempt, 2, '오류 후 접근은 초기화식을 다시 실행하지 않음');

  print('통과');
}

void testLateFinalSelfCycle() {
  print('\n=== late final 자기 참조 순환 ===');
  final obj = LateFinalSelfCycle();

  bool threw = false;
  Object? error;
  try {
    print('자기 참조 시도: ${obj.self}');
  } catch (e) {
    print('자기 참조 예외: $e (${e.runtimeType})');
    threw = true;
    error = e;
  }

  checkTrue(threw, '자기 참조 순환은 예외를 던져야 함');
  checkTrue(error is StackOverflowError, '자기 참조 순환 시 StackOverflowError 발생');

  print('통과');
}

void testLateFinalMutualCycle() {
  print('\n=== late final 상호 참조 순환 ===');
  final objA = LateFinalMutualCycleA();

  bool threw = false;
  Object? error;
  try {
    print('상호 참조 시도: ${objA.value}');
  } catch (e) {
    print('상호 참조 예외: $e (${e.runtimeType})');
    threw = true;
    error = e;
  }

  checkTrue(threw, '상호 참조 순환은 예외를 던져야 함');
  checkTrue(error is StackOverflowError, '상호 참조 순환 시 StackOverflowError 발생');

  print('통과');
}

void testTopLevelRetry() {
  print('\n=== 최상위 final 초기화 실패 후 재시도 ===');

  _topAttempt = 0;
  final getter = () => topLevelValue;

  bool firstAccessThrew = false;
  try {
    print('첫 접근 시도: ${getter()}');
  } catch (e) {
    print('첫 접근 예외: $e');
    firstAccessThrew = true;
  }

  checkTrue(firstAccessThrew, '첫 접근은 예외를 던져야 함');
  checkEquals(_topAttempt, 1, '첫 접근 후 topAttempt는 1');

  final secondValue = getter();
  print('두 번째 접근: $secondValue');
  checkEquals(_topAttempt, 2, '두 번째 접근 후 topAttempt는 2');
  checkEquals(secondValue, '최상위 성공(2번째 시도)', '두 번째 접근 성공 값 확인');

  print('통과');
}

void testRememberFailureCache() {
  print('\n=== 실패 기억 캐시 ===');
  final cache = RememberFailureCache();
  int computeCallCount = 0;

  String compute() {
    computeCallCount++;
    if (computeCallCount == 1) {
      throw Exception('캐시 계산 실패');
    }
    return '캐시 성공($computeCallCount번째 호출)';
  }

  bool firstAccessThrew = false;
  try {
    final value = cache.get(compute);
    print('첫 접근: $value');
  } catch (e) {
    print('첫 접근 예외: $e');
    firstAccessThrew = true;
  }

  checkTrue(firstAccessThrew, '실패 기억 캐시 첫 접근은 예외를 던져야 함');
  checkEquals(cache.callCount, 1, '캐시 호출 횟수는 1');
  checkEquals(computeCallCount, 1, '계산 함수 호출 횟수는 1');

  bool secondAccessThrew = false;
  try {
    final value = cache.get(compute);
    print('두 번째 접근: $value');
  } catch (e) {
    print('두 번째 접근 예외: $e');
    secondAccessThrew = true;
  }

  checkTrue(secondAccessThrew, '실패 기억 캐시 두 번째 접근도 예외를 던져야 함');
  checkEquals(cache.callCount, 2, '캐시 호출 횟수는 2');
  checkEquals(computeCallCount, 1, '계산 함수 호출 횟수는 여전히 1 (재실행 안 함)');

  print('통과: 실패를 기억하여 재시도하지 않음');
}

void testRetryLimitCache() {
  print('\n=== 재시도 한도 캐시 ===');
  final cache = RetryLimitCache(3);
  int computeCallCount = 0;

  String compute() {
    computeCallCount++;
    if (computeCallCount <= 2) {
      throw Exception('캐시 계산 실패($computeCallCount번째)');
    }
    return '캐시 성공($computeCallCount번째 호출)';
  }

  bool firstAccessThrew = false;
  try {
    final value = cache.get(compute);
    print('첫 접근: $value');
  } catch (e) {
    print('첫 접근 예외: $e');
    firstAccessThrew = true;
  }

  checkTrue(firstAccessThrew, '재시도 한도 캐시 첫 접근은 예외를 던져야 함');
  checkEquals(cache.callCount, 1, '캐시 호출 횟수는 1');
  checkEquals(computeCallCount, 1, '계산 함수 호출 횟수는 1');

  bool secondAccessThrew = false;
  try {
    final value = cache.get(compute);
    print('두 번째 접근: $value');
  } catch (e) {
    print('두 번째 접근 예외: $e');
    secondAccessThrew = true;
  }

  checkTrue(secondAccessThrew, '재시도 한도 캐시 두 번째 접근도 예외를 던져야 함');
  checkEquals(cache.callCount, 2, '캐시 호출 횟수는 2');
  checkEquals(computeCallCount, 2, '계산 함수 호출 횟수는 2 (재시도됨)');

  final thirdValue = cache.get(compute);
  print('세 번째 접근: $thirdValue');
  checkEquals(cache.callCount, 3, '캐시 호출 횟수는 3');
  checkEquals(computeCallCount, 3, '계산 함수 호출 횟수는 3 (재시도됨)');
  checkEquals(thirdValue, '캐시 성공(3번째 호출)', '세 번째 접근 성공');

  final fourthValue = cache.get(compute);
  print('네 번째 접근: $fourthValue');
  checkEquals(cache.callCount, 4, '캐시 호출 횟수는 4');
  checkEquals(computeCallCount, 3, '계산 함수 호출 횟수는 여전히 3 (재실행 안 함)');
  checkEquals(fourthValue, '캐시 성공(3번째 호출)', '네 번째 접근도 같은 값');

  print('통과: 재시도 한도 내에서 재시도 후 성공하면 캐시됨');
}

void testRetryLimitExceeded() {
  print('\n=== 재시도 한도 초과 ===');
  final cache = RetryLimitCache(2);
  int computeCallCount = 0;

  String compute() {
    computeCallCount++;
    throw Exception('항상 실패($computeCallCount번째)');
  }

  for (int i = 1; i <= 2; i++) {
    bool threw = false;
    try {
      final value = cache.get(compute);
      print('$i번째 접근: $value');
    } catch (e) {
      print('$i번째 접근 예외: $e');
      threw = true;
    }
    checkTrue(threw, '$i번째 접근은 예외를 던져야 함');
  }

  checkEquals(computeCallCount, 2, '계산 함수는 2번 호출됨 (한도만큼)');

  bool thirdAccessThrew = false;
  String? thirdError;
  try {
    final value = cache.get(compute);
    print('세 번째 접근: $value');
  } catch (e) {
    print('세 번째 접근 예외: $e');
    thirdAccessThrew = true;
    thirdError = e.toString();
  }

  checkTrue(thirdAccessThrew, '세 번째 접근도 예외를 던져야 함');
  checkTrue(
    thirdError != null && thirdError.contains('재시도 한도 초과'),
    '세 번째 접근은 재시도 한도 초과 예외',
  );
  checkEquals(computeCallCount, 2, '계산 함수는 여전히 2번만 호출됨 (더 이상 재시도 안 함)');

  print('통과: 재시도 한도 초과 시 더 이상 재시도하지 않음');
}

void testCompareCallCounts() {
  print('\n=== 호출 횟수 비교 ===');

  int lateFinalAttempt = 0;
  late final String lateFinalValue = () {
    lateFinalAttempt++;
    if (lateFinalAttempt == 1) {
      throw Exception('late final 실패');
    }
    return 'late final 성공';
  }();

  try {
    print(lateFinalValue);
  } catch (e) {}
  print(lateFinalValue);
  print(lateFinalValue);

  print('late final 초기화 함수 호출 횟수: $lateFinalAttempt');

  final rememberCache = RememberFailureCache();
  int rememberComputeCount = 0;
  String rememberCompute() {
    rememberComputeCount++;
    if (rememberComputeCount == 1) {
      throw Exception('실패 기억 캐시 실패');
    }
    return '실패 기억 캐시 성공';
  }

  try {
    rememberCache.get(rememberCompute);
  } catch (e) {}
  try {
    rememberCache.get(rememberCompute);
  } catch (e) {}
  try {
    rememberCache.get(rememberCompute);
  } catch (e) {}

  print('실패 기억 캐시 초기화 함수 호출 횟수: $rememberComputeCount');
  print('실패 기억 캐시 get 호출 횟수: ${rememberCache.callCount}');

  final retryCache = RetryLimitCache(5);
  int retryComputeCount = 0;
  String retryCompute() {
    retryComputeCount++;
    if (retryComputeCount == 1) {
      throw Exception('재시도 한도 캐시 실패');
    }
    return '재시도 한도 캐시 성공';
  }

  try {
    retryCache.get(retryCompute);
  } catch (e) {}
  retryCache.get(retryCompute);
  retryCache.get(retryCompute);

  print('재시도 한도 캐시 초기화 함수 호출 횟수: $retryComputeCount');
  print('재시도 한도 캐시 get 호출 횟수: ${retryCache.callCount}');

  checkEquals(lateFinalAttempt, 2, 'late final은 2번 호출 (실패 후 재시도 성공)');
  checkEquals(rememberComputeCount, 1, '실패 기억 캐시는 1번만 호출 (실패 후 재시도 안 함)');
  checkEquals(retryComputeCount, 2, '재시도 한도 캐시는 2번 호출 (실패 후 재시도 성공)');

  print('통과: late final과 재시도 한도 캐시는 실패 후 재시도하지만, 실패 기억 캐시는 재시도하지 않음');
}

void main() {
  try {
    testLateFinalRetry();
    testLateFinalReentrant();
    testLateFinalSelfCycle();
    testLateFinalMutualCycle();
    testTopLevelRetry();
    testRememberFailureCache();
    testRetryLimitCache();
    testRetryLimitExceeded();
    testCompareCallCounts();
    print('\nALL_CHECKS_PASSED');
  } catch (e, stackTrace) {
    print('\n실패 발생: $e');
    print(stackTrace);
    exit(1);
  }
}

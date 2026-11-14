import 'dart:io';
import '../src/main.dart' hide main;

int _testAttempt = 0;

class TestLateFinalRetry {
  late final String value = _testCompute();

  String _testCompute() {
    _testAttempt++;
    if (_testAttempt == 1) {
      throw Exception('테스트 실패');
    }
    return '테스트 성공($_testAttempt)';
  }
}

int _testReentrantAttempt = 0;

class TestLateFinalReentrant {
  late final String value = _testGetValue();

  String _testGetValue() {
    _testReentrantAttempt++;
    if (_testReentrantAttempt == 1) {
      try {
        return value;
      } catch (e) {
        rethrow;
      }
    }
    return '테스트 완료';
  }
}

int _topTestAttempt = 0;

String topTestFlaky() {
  _topTestAttempt++;
  if (_topTestAttempt == 1) {
    throw Exception('최상위 테스트 실패');
  }
  return '최상위 테스트 성공($_topTestAttempt)';
}

final topTestValue = topTestFlaky();

void check(bool condition, String message) {
  if (!condition) {
    print('테스트 실패: $message');
    exit(1);
  }
}

void testLateFinalInitializerRetry() {
  print('테스트: late final 초기화 실패 후 재시도');
  _testAttempt = 0;
  final obj = TestLateFinalRetry();

  bool firstThrew = false;
  try {
    obj.value;
  } catch (e) {
    firstThrew = true;
  }

  check(firstThrew, '첫 접근은 예외를 던져야 함');
  check(_testAttempt == 1, '첫 접근 후 attempt는 1');

  final secondValue = obj.value;
  check(_testAttempt == 2, '두 번째 접근 후 attempt는 2');
  check(secondValue == '테스트 성공(2)', '두 번째 접근은 성공 값 반환');

  final thirdValue = obj.value;
  check(_testAttempt == 2, '세 번째 접근 후에도 attempt는 2');
  check(thirdValue == secondValue, '세 번째 접근은 같은 값 반환');

  print('  통과');
}

void testLateFinalInitializerReentrant() {
  print('테스트: late final 재진입');
  _testReentrantAttempt = 0;
  final obj = TestLateFinalReentrant();

  bool threw = false;
  Object? error;
  try {
    obj.value;
  } catch (e) {
    threw = true;
    error = e;
  }

  check(threw, '재진입은 예외를 던져야 함');
  check(
    error.toString().contains('LateInitializationError'),
    '재진입 시 LateInitializationError 발생',
  );
  check(_testReentrantAttempt == 2, '초기화식은 2번 실행됨 (바깥 + 안쪽 재진입)');

  final valueAfterError = obj.value;
  check(valueAfterError == '테스트 완료', '오류 후 필드는 안쪽 실행이 저장한 값을 가짐');
  check(_testReentrantAttempt == 2, '오류 후 접근은 초기화식을 다시 실행하지 않음');

  print('  통과');
}

void testLateFinalSelfCycleStack() {
  print('테스트: late final 자기 참조 순환');
  final obj = LateFinalSelfCycle();

  bool threw = false;
  Object? error;
  try {
    obj.self;
  } catch (e) {
    threw = true;
    error = e;
  }

  check(threw, '자기 참조 순환은 예외를 던져야 함');
  check(error is StackOverflowError, '자기 참조 순환 시 StackOverflowError');

  print('  통과');
}

void testLateFinalMutualCycleStack() {
  print('테스트: late final 상호 참조 순환');
  final objA = LateFinalMutualCycleA();

  bool threw = false;
  Object? error;
  try {
    objA.value;
  } catch (e) {
    threw = true;
    error = e;
  }

  check(threw, '상호 참조 순환은 예외를 던져야 함');
  check(error is StackOverflowError, '상호 참조 순환 시 StackOverflowError');

  print('  통과');
}

void testTopLevelInitializerRetry() {
  print('테스트: 최상위 final 초기화 실패 후 재시도');
  _topTestAttempt = 0;
  final getter = () => topTestValue;

  bool firstThrew = false;
  try {
    getter();
  } catch (e) {
    firstThrew = true;
  }

  check(firstThrew, '최상위 첫 접근은 예외를 던져야 함');
  check(_topTestAttempt == 1, '최상위 첫 접근 후 attempt는 1');

  final secondValue = getter();
  check(_topTestAttempt == 2, '최상위 두 번째 접근 후 attempt는 2');
  check(secondValue == '최상위 테스트 성공(2)', '최상위 두 번째 접근은 성공 값 반환');

  print('  통과');
}

void testRememberFailureCacheNoRetry() {
  print('테스트: 실패 기억 캐시는 재시도하지 않음');
  final cache = RememberFailureCache();
  int computeCount = 0;

  String compute() {
    computeCount++;
    if (computeCount == 1) {
      throw Exception('캐시 실패');
    }
    return '캐시 성공';
  }

  bool firstThrew = false;
  try {
    cache.get(compute);
  } catch (e) {
    firstThrew = true;
  }

  check(firstThrew, '첫 접근은 예외를 던져야 함');
  check(cache.callCount == 1, '캐시 callCount는 1');
  check(computeCount == 1, 'compute callCount는 1');

  bool secondThrew = false;
  try {
    cache.get(compute);
  } catch (e) {
    secondThrew = true;
  }

  check(secondThrew, '두 번째 접근도 예외를 던져야 함');
  check(cache.callCount == 2, '캐시 callCount는 2');
  check(computeCount == 1, 'compute callCount는 여전히 1 (재실행 안 함)');

  print('  통과');
}

void testRetryLimitCacheRetries() {
  print('테스트: 재시도 한도 캐시는 한도 내에서 재시도');
  final cache = RetryLimitCache(3);
  int computeCount = 0;

  String compute() {
    computeCount++;
    if (computeCount <= 2) {
      throw Exception('캐시 실패($computeCount)');
    }
    return '캐시 성공($computeCount)';
  }

  bool firstThrew = false;
  try {
    cache.get(compute);
  } catch (e) {
    firstThrew = true;
  }

  check(firstThrew, '첫 접근은 예외를 던져야 함');
  check(computeCount == 1, 'compute callCount는 1');

  bool secondThrew = false;
  try {
    cache.get(compute);
  } catch (e) {
    secondThrew = true;
  }

  check(secondThrew, '두 번째 접근도 예외를 던져야 함');
  check(computeCount == 2, 'compute callCount는 2 (재시도됨)');

  final thirdValue = cache.get(compute);
  check(computeCount == 3, 'compute callCount는 3 (재시도됨)');
  check(thirdValue == '캐시 성공(3)', '세 번째 접근은 성공');

  final fourthValue = cache.get(compute);
  check(computeCount == 3, 'compute callCount는 여전히 3 (재실행 안 함)');
  check(fourthValue == thirdValue, '네 번째 접근은 같은 값');

  print('  통과');
}

void testRetryLimitCacheExceeded() {
  print('테스트: 재시도 한도 캐시는 한도 초과 시 재시도 중단');
  final cache = RetryLimitCache(2);
  int computeCount = 0;

  String compute() {
    computeCount++;
    throw Exception('항상 실패');
  }

  for (int i = 1; i <= 2; i++) {
    bool threw = false;
    try {
      cache.get(compute);
    } catch (e) {
      threw = true;
    }
    check(threw, '$i번째 접근은 예외를 던져야 함');
  }

  check(computeCount == 2, 'compute callCount는 2 (한도만큼)');

  bool thirdThrew = false;
  String? thirdError;
  try {
    cache.get(compute);
  } catch (e) {
    thirdThrew = true;
    thirdError = e.toString();
  }

  check(thirdThrew, '세 번째 접근도 예외를 던져야 함');
  check(
    thirdError != null && thirdError.contains('재시도 한도 초과'),
    '세 번째 접근은 재시도 한도 초과 예외',
  );
  check(computeCount == 2, 'compute callCount는 여전히 2 (더 이상 재시도 안 함)');

  print('  통과');
}

class TestNoInitializer {
  late final String noInitializer;
}

void testBoundaryNoInitializer() {
  print('테스트: 경계 - 초기화식 없는 late final은 미초기화 시 LateError');

  final obj = TestNoInitializer();

  bool threw = false;
  Object? error;
  try {
    print(obj.noInitializer);
  } catch (e) {
    threw = true;
    error = e;
  }

  check(threw, '초기화식 없는 late final 접근은 예외를 던져야 함');
  check(
    error.toString().contains('LateInitializationError'),
    '초기화식 없는 late final은 LateInitializationError',
  );

  print('  통과');
}

void testBoundarySuccessOnFirstAccess() {
  print('테스트: 경계 - 첫 접근에서 성공하면 재시도 없음');
  int successAttempt = 0;

  late final String value = () {
    successAttempt++;
    return '첫 성공($successAttempt)';
  }();

  final firstValue = value;
  check(successAttempt == 1, '첫 접근 후 attempt는 1');
  check(firstValue == '첫 성공(1)', '첫 접근 성공 값');

  final secondValue = value;
  check(successAttempt == 1, '두 번째 접근 후에도 attempt는 1');
  check(secondValue == firstValue, '두 번째 접근은 같은 값');

  print('  통과');
}

void testBoundaryStateError() {
  print('테스트: 경계 - StateError를 던지면 실패 기억 캐시가 같은 인스턴스를 던짐');
  final cache = RememberFailureCache();
  int computeCount = 0;
  final stateError = StateError('테스트 상태 오류');

  String compute() {
    computeCount++;
    throw stateError;
  }

  Object? firstError;
  try {
    cache.get(compute);
  } catch (e) {
    firstError = e;
  }

  check(firstError == stateError, '첫 접근은 StateError를 던짐');
  check(computeCount == 1, 'compute는 1번 호출됨');

  Object? secondError;
  try {
    cache.get(compute);
  } catch (e) {
    secondError = e;
  }

  check(secondError == stateError, '두 번째 접근도 같은 StateError 인스턴스를 던짐');
  check(computeCount == 1, 'compute는 여전히 1번만 호출됨');

  print('  통과');
}

void testBoundaryNullResult() {
  print('테스트: 경계 - null 결과가 두 캐시 모두에서 1회만 계산됨');

  final rememberCache = RememberFailureCache();
  int rememberComputeCount = 0;
  String? rememberCompute() {
    rememberComputeCount++;
    return null;
  }

  final firstResult = rememberCache.get(rememberCompute);
  check(firstResult == null, '실패 기억 캐시: 첫 접근은 null 반환');
  check(rememberComputeCount == 1, '실패 기억 캐시: compute는 1번 호출됨');

  final secondResult = rememberCache.get(rememberCompute);
  check(secondResult == null, '실패 기억 캐시: 두 번째 접근도 null 반환');
  check(rememberComputeCount == 1, '실패 기억 캐시: compute는 여전히 1번만 호출됨');

  final retryCache = RetryLimitCache(3);
  int retryComputeCount = 0;
  String? retryCompute() {
    retryComputeCount++;
    return null;
  }

  final firstRetryResult = retryCache.get(retryCompute);
  check(firstRetryResult == null, '재시도 한도 캐시: 첫 접근은 null 반환');
  check(retryComputeCount == 1, '재시도 한도 캐시: compute는 1번 호출됨');

  final secondRetryResult = retryCache.get(retryCompute);
  check(secondRetryResult == null, '재시도 한도 캐시: 두 번째 접근도 null 반환');
  check(retryComputeCount == 1, '재시도 한도 캐시: compute는 여전히 1번만 호출됨');

  print('  통과');
}

void testBoundaryExceptionValue() {
  print('테스트: 경계 - Exception 인스턴스를 값으로 반환하면 재시도 한도 캐시가 캐시함');
  final cache = RetryLimitCache(3);
  int computeCount = 0;
  final exceptionValue = Exception('값으로 반환되는 예외');

  Exception compute() {
    computeCount++;
    return exceptionValue;
  }

  final firstResult = cache.get(compute);
  check(firstResult == exceptionValue, '첫 접근은 Exception 값을 반환');
  check(computeCount == 1, 'compute는 1번 호출됨');

  final secondResult = cache.get(compute);
  check(secondResult == exceptionValue, '두 번째 접근도 같은 Exception 값을 반환');
  check(computeCount == 1, 'compute는 여전히 1번만 호출됨 (재호출하지 않음)');

  print('  통과');
}

void testBoundaryMaxAttemptsZero() {
  print('테스트: 경계 - maxAttempts가 0이면 ArgumentError');

  bool threw = false;
  Object? error;
  try {
    RetryLimitCache(0);
  } catch (e) {
    threw = true;
    error = e;
  }

  check(threw, 'maxAttempts 0은 예외를 던져야 함');
  check(error is ArgumentError, 'maxAttempts 0은 ArgumentError를 던짐');

  print('  통과');
}

void main() {
  print('=== late final 초기화 동작 테스트 시작 ===\n');

  try {
    testLateFinalInitializerRetry();
    testLateFinalInitializerReentrant();
    testLateFinalSelfCycleStack();
    testLateFinalMutualCycleStack();
    testTopLevelInitializerRetry();
    testRememberFailureCacheNoRetry();
    testRetryLimitCacheRetries();
    testRetryLimitCacheExceeded();
    testBoundaryNoInitializer();
    testBoundarySuccessOnFirstAccess();
    testBoundaryStateError();
    testBoundaryNullResult();
    testBoundaryExceptionValue();
    testBoundaryMaxAttemptsZero();

    print('\n모든 테스트 통과');
  } catch (e, stackTrace) {
    print('\n테스트 중 예외 발생: $e');
    print(stackTrace);
    exit(1);
  }
}

import 'dart:io';
import 'dart:async';

import '../src/search_backend.dart';
import '../src/search_implementations.dart';

Future<void> main() async {
  final List<String> allTests = [];
  final List<String> failedTests = [];

  Future<void> test(String name, FutureOr<void> Function() body) async {
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

  print('=== 검색 입력 중 비동기 응답 순서 문제 테스트 ===\n');
  print('FakeSearchBackend 테스트\n');

  await test('Backend: 요청과 응답 관리', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    expect(backend.callCount == 0, '초기 callCount는 0');
    final Future<SearchResult> future = backend.search('test');
    expect(backend.callCount == 1, 'search 호출 후 callCount 증가');
    expect(backend.hasPendingRequest('test'), 'test 요청이 대기 중');
    backend.completeRequest('test', ['result1']);
    final SearchResult result = await future;
    expect(result.query == 'test', 'query는 test');
    expect(
      result.items.length == 1 && result.items[0] == 'result1',
      'items는 [result1]',
    );
    expect(!backend.hasPendingRequest('test'), '완료 후 대기 중 아님');
  });

  await test('Backend: 실패 처리', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final Future<SearchResult> future = backend.search('fail');
    backend.failRequest('fail', Exception('Network error'));
    bool caught = false;
    try {
      await future;
    } catch (e) {
      caught = true;
      expect(e is Exception, '예외는 Exception 타입');
    }
    expect(caught, '예외가 catchError로 전달됨');
  });

  await test('Backend: reset 후 상태 초기화', () {
    final FakeSearchBackend backend = FakeSearchBackend();
    backend.search('q1');
    backend.search('q2');
    expect(backend.callCount == 2, 'callCount는 2');
    backend.reset();
    expect(backend.callCount == 0, 'reset 후 callCount는 0');
  });

  await test('Backend: 같은 쿼리 여러 요청 처리', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final Future<SearchResult> future1 = backend.search('a');
    final Future<SearchResult> future2 = backend.search('a');
    expect(backend.callCount == 2, '같은 쿼리도 두 번 호출됨');
    backend.completeRequest('a', ['first']);
    final SearchResult result1 = await future1;
    expect(result1.items[0] == 'first', '첫 번째 요청 완료');
    backend.completeRequest('a', ['second']);
    final SearchResult result2 = await future2;
    expect(result2.items[0] == 'second', '두 번째 요청 완료');
  });

  print('\nNaiveSearch 테스트\n');

  await test('Naive: 순서 뒤바뀐 응답으로 최신 결과 덮어쓰기 버그 재현', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final NaiveSearch search = NaiveSearch(backend);
    search.search('a');
    search.search('ab');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '"ab" 응답이 먼저 도착하면 결과는 "ab"');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'a', '버그: 최신 쿼리는 "ab"인데 결과는 "a"');
  });

  await test('Naive: 늦게 도착한 응답이 최신 결과를 덮어씀', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final NaiveSearch search = NaiveSearch(backend);
    search.search('a');
    search.search('ab');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '"ab" 응답이 먼저 도착하면 결과는 "ab"');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'a', '늦게 도착한 "a" 응답이 덮어씀');
  });

  await test('Naive: 빈 쿼리는 결과 null', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final NaiveSearch search = NaiveSearch(backend);
    await search.search('');
    expect(search.currentResults == null, '빈 쿼리는 결과 null');
    expect(backend.callCount == 0, '빈 쿼리는 백엔드 호출 안 함');
  });

  await test('Naive: 에러 처리', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final NaiveSearch search = NaiveSearch(backend);
    search.search('fail');
    backend.failRequest('fail', Exception('Network error'));
    await Future<void>.delayed(Duration.zero);
    expect(search.hasError, '에러 발생');
    expect(search.currentResults == null, '에러 시 결과는 null');
  });

  await test('Naive: dispose 후 응답 무시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final NaiveSearch search = NaiveSearch(backend);
    search.search('a');
    search.dispose();
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, 'dispose 후 응답은 무시됨');
  });

  print('\nSequenceTokenSearch 테스트\n');

  await test('SequenceToken: latest-wins (늦게 도착한 응답 무시)', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    search.search('a');
    search.search('ab');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, '늦게 도착한 "a" 응답은 무시됨');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '최신 쿼리 "ab" 결과만 표시');
  });

  await test('SequenceToken: 정상 순서 응답', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    search.search('a');
    search.search('ab');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '"ab" 응답이 먼저 도착해도 결과는 "ab"');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '늦게 도착한 "a" 응답은 무시됨');
  });

  await test('SequenceToken: 늦게 도착한 에러 무시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    search.search('a');
    search.search('ab');
    backend.failRequest('a', Exception('Old request failed'));
    await Future<void>.delayed(Duration.zero);
    expect(!search.hasError, '늦게 도착한 에러는 무시됨');
    expect(search.currentResults == null, '아직 결과 없음');
  });

  await test('SequenceToken: 최신 요청 에러는 표시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    search.search('fail');
    backend.failRequest('fail', Exception('Latest request failed'));
    await Future<void>.delayed(Duration.zero);
    expect(search.hasError, '최신 요청의 에러는 표시됨');
    expect(search.currentResults == null, '에러 시 결과는 null');
  });

  await test('SequenceToken: 같은 쿼리 두 번 (두 번째가 최신)', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    search.search('a');
    search.search('a');
    expect(backend.callCount == 2, '같은 쿼리도 두 번 호출됨');
    backend.completeRequest('a', ['apple1']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, '첫 번째 "a" 응답은 무시됨');
    backend.completeRequest('a', ['apple2']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.items[0] == 'apple2', '두 번째 "a" 응답만 표시됨');
  });

  await test('SequenceToken: 빈 쿼리는 결과 null', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    await search.search('');
    expect(search.currentResults == null, '빈 쿼리는 결과 null');
    expect(backend.callCount == 0, '빈 쿼리는 백엔드 호출 안 함');
  });

  await test('SequenceToken: dispose 후 응답 무시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SequenceTokenSearch search = SequenceTokenSearch(backend);
    search.search('a');
    search.dispose();
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, 'dispose 후 응답은 무시됨');
  });

  print('\nSubscriptionCancelSearch 테스트\n');

  await test('SubscriptionCancel: latest-wins (이전 구독 취소)', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SubscriptionCancelSearch search = SubscriptionCancelSearch(backend);
    search.search('a');
    await Future<void>.delayed(Duration.zero);
    search.search('ab');
    await Future<void>.delayed(Duration.zero);
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, '취소된 구독의 "a" 응답은 무시됨');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '최신 쿼리 "ab" 결과만 표시');
    search.dispose();
  });

  await test('SubscriptionCancel: 백엔드 작업은 계속 진행됨 (취소는 응답 무시만)', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SubscriptionCancelSearch search = SubscriptionCancelSearch(backend);
    search.search('a');
    await Future<void>.delayed(Duration.zero);
    search.search('ab');
    await Future<void>.delayed(Duration.zero);
    expect(backend.callCount == 2, '두 요청 모두 백엔드에 전달됨');
    expect(backend.hasPendingRequest('a'), '"a" 요청은 여전히 대기 중 (취소되지 않음)');
    expect(backend.hasPendingRequest('ab'), '"ab" 요청도 대기 중');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, '구독 취소로 "a" 응답은 무시됨');
    search.dispose();
  });

  await test('SubscriptionCancel: dispose 후 응답 무시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SubscriptionCancelSearch search = SubscriptionCancelSearch(backend);
    search.search('a');
    await Future<void>.delayed(Duration.zero);
    search.dispose();
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, 'dispose 후 응답은 무시됨');
  });

  await test('SubscriptionCancel: 빈 쿼리는 결과 null', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final SubscriptionCancelSearch search = SubscriptionCancelSearch(backend);
    await search.search('');
    expect(search.currentResults == null, '빈 쿼리는 결과 null');
    expect(backend.callCount == 0, '빈 쿼리는 백엔드 호출 안 함');
    search.dispose();
  });

  print('\nDebounceSearch 테스트\n');

  await test('Debounce: 연속 입력으로 호출 횟수 감소', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceSearch search = DebounceSearch(
      backend,
      debounceDuration: Duration(milliseconds: 50),
    );
    search.search('a');
    search.search('ab');
    search.search('abc');
    expect(backend.callCount == 0, '디바운스 시간 전에는 호출 안 됨');
    await Future<void>.delayed(Duration(milliseconds: 100));
    expect(backend.callCount == 1, '디바운스 후 마지막 쿼리만 호출됨');
    expect(backend.hasPendingRequest('abc'), '마지막 쿼리 "abc"만 대기 중');
    search.dispose();
  });

  await test('Debounce: 단독 사용 시 순서 문제는 여전히 가능', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceSearch search = DebounceSearch(
      backend,
      debounceDuration: Duration(milliseconds: 10),
    );
    search.search('a');
    await Future<void>.delayed(Duration(milliseconds: 20));
    search.search('ab');
    await Future<void>.delayed(Duration(milliseconds: 20));
    expect(backend.callCount == 2, '두 요청이 모두 발생');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'a', '"a"가 먼저 완료되면 결과는 "a"');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '늦게 도착한 "ab" 응답이 덮어씀');
    search.dispose();
  });

  await test('Debounce: 빈 쿼리는 결과 null', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceSearch search = DebounceSearch(
      backend,
      debounceDuration: Duration(milliseconds: 10),
    );
    await search.search('');
    expect(search.currentResults == null, '빈 쿼리는 결과 null');
    expect(backend.callCount == 0, '빈 쿼리는 백엔드 호출 안 함');
    search.dispose();
  });

  await test('Debounce: dispose는 타이머 취소', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceSearch search = DebounceSearch(
      backend,
      debounceDuration: Duration(milliseconds: 50),
    );
    search.search('a');
    search.dispose();
    await Future<void>.delayed(Duration(milliseconds: 100));
    expect(backend.callCount == 0, 'dispose로 타이머 취소되어 호출 안 됨');
  });

  await test('Debounce: 대체된 호출은 완료됨 (타임아웃 없이)', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceSearch search = DebounceSearch(
      backend,
      debounceDuration: Duration(milliseconds: 10),
    );
    final Future<void> future1 = search.search('a');
    final Future<void> future2 = search.search('ab');
    bool future1Completed = false;
    bool future2Completed = false;
    future1.then((_) => future1Completed = true);
    future2.then((_) => future2Completed = true);
    await Future<void>.delayed(Duration(milliseconds: 20));
    expect(future1Completed, 'future1은 대체되어 즉시 완료됨');
    expect(backend.callCount == 1, '마지막 쿼리만 호출됨');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(future2Completed, 'future2도 완료됨');
    search.dispose();
  });

  await test('Debounce: dispose 후 응답 무시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceSearch search = DebounceSearch(
      backend,
      debounceDuration: Duration(milliseconds: 10),
    );
    search.search('a');
    await Future<void>.delayed(Duration(milliseconds: 20));
    search.dispose();
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, 'dispose 후 응답은 무시됨');
  });

  print('\nDebounceWithSequenceTokenSearch 테스트\n');

  await test(
    'DebounceWithSequenceToken: 연속 입력으로 호출 횟수 감소 + latest-wins',
    () async {
      final FakeSearchBackend backend = FakeSearchBackend();
      final DebounceWithSequenceTokenSearch search =
          DebounceWithSequenceTokenSearch(
            backend,
            debounceDuration: Duration(milliseconds: 50),
          );
      search.search('a');
      search.search('ab');
      search.search('abc');
      expect(backend.callCount == 0, '디바운스 시간 전에는 호출 안 됨');
      await Future<void>.delayed(Duration(milliseconds: 100));
      expect(backend.callCount == 1, '디바운스 후 마지막 쿼리만 호출됨');
      backend.completeRequest('abc', ['abandon', 'abstract']);
      await Future<void>.delayed(Duration.zero);
      expect(search.currentResults?.query == 'abc', '최신 쿼리 "abc" 결과 표시');
      search.dispose();
    },
  );

  await test('DebounceWithSequenceToken: 두 요청 겹칠 때 latest-wins', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceWithSequenceTokenSearch search =
        DebounceWithSequenceTokenSearch(
          backend,
          debounceDuration: Duration(milliseconds: 10),
        );
    search.search('a');
    await Future<void>.delayed(Duration(milliseconds: 20));
    search.search('ab');
    await Future<void>.delayed(Duration(milliseconds: 20));
    expect(backend.callCount == 2, '두 요청이 모두 발생');
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, '늦게 도착한 "a" 응답은 무시됨');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults?.query == 'ab', '최신 쿼리 "ab" 결과만 표시');
    search.dispose();
  });

  await test('DebounceWithSequenceToken: 빈 쿼리는 결과 null', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceWithSequenceTokenSearch search =
        DebounceWithSequenceTokenSearch(
          backend,
          debounceDuration: Duration(milliseconds: 10),
        );
    await search.search('');
    expect(search.currentResults == null, '빈 쿼리는 결과 null');
    expect(backend.callCount == 0, '빈 쿼리는 백엔드 호출 안 함');
    search.dispose();
  });

  await test('DebounceWithSequenceToken: dispose는 타이머 취소', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceWithSequenceTokenSearch search =
        DebounceWithSequenceTokenSearch(
          backend,
          debounceDuration: Duration(milliseconds: 50),
        );
    search.search('a');
    search.dispose();
    await Future<void>.delayed(Duration(milliseconds: 100));
    expect(backend.callCount == 0, 'dispose로 타이머 취소되어 호출 안 됨');
  });

  await test('DebounceWithSequenceToken: 대체된 호출은 완료됨 (타임아웃 없이)', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceWithSequenceTokenSearch search =
        DebounceWithSequenceTokenSearch(
          backend,
          debounceDuration: Duration(milliseconds: 10),
        );
    final Future<void> future1 = search.search('a');
    final Future<void> future2 = search.search('ab');
    bool future1Completed = false;
    bool future2Completed = false;
    future1.then((_) => future1Completed = true);
    future2.then((_) => future2Completed = true);
    await Future<void>.delayed(Duration(milliseconds: 20));
    expect(future1Completed, 'future1은 대체되어 즉시 완료됨');
    expect(backend.callCount == 1, '마지막 쿼리만 호출됨');
    backend.completeRequest('ab', ['abandon']);
    await Future<void>.delayed(Duration.zero);
    expect(future2Completed, 'future2도 완료됨');
    search.dispose();
  });

  await test('DebounceWithSequenceToken: dispose 후 응답 무시', () async {
    final FakeSearchBackend backend = FakeSearchBackend();
    final DebounceWithSequenceTokenSearch search =
        DebounceWithSequenceTokenSearch(
          backend,
          debounceDuration: Duration(milliseconds: 10),
        );
    search.search('a');
    await Future<void>.delayed(Duration(milliseconds: 20));
    search.dispose();
    backend.completeRequest('a', ['apple']);
    await Future<void>.delayed(Duration.zero);
    expect(search.currentResults == null, 'dispose 후 응답은 무시됨');
  });

  print('\n경계 조건 테스트\n');

  await test('경계: SearchResult equality', () {
    final SearchResult r1 = SearchResult(query: 'test', items: ['a', 'b']);
    final SearchResult r2 = SearchResult(query: 'test', items: ['a', 'b']);
    final SearchResult r3 = SearchResult(query: 'test', items: ['a', 'c']);
    expect(r1 == r2, '같은 query와 items는 equal');
    expect(r1 != r3, '다른 items는 not equal');
    expect(r1.hashCode == r2.hashCode, '같은 내용은 같은 hashCode');
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

import 'dart:io';
import 'dart:async';

import 'search_backend.dart';
import 'search_implementations.dart';

Future<void> main() async {
  print('=== 검색 입력 중 늦게 도착한 비동기 응답의 최신 결과 덮어쓰기 문제 시연 ===\n');
  bool allPassed = true;
  allPassed = await demonstrateNaiveRace() && allPassed;
  print('');
  allPassed = await demonstrateSequenceToken() && allPassed;
  print('');
  allPassed = await demonstrateSubscriptionCancel() && allPassed;
  print('');
  allPassed = await demonstrateDebounce() && allPassed;
  print('');
  allPassed = await demonstrateDebounceWithSequenceToken() && allPassed;
  print('');
  if (allPassed) {
    print('ALL_CHECKS_PASSED');
    exit(0);
  } else {
    print('일부 검증 실패');
    exit(1);
  }
}

Future<bool> demonstrateNaiveRace() async {
  print('1. NaiveSearch: 늦게 도착한 응답이 최신 결과를 덮어쓰는 문제');
  final FakeSearchBackend backend = FakeSearchBackend();
  final NaiveSearch search = NaiveSearch(backend);
  print('   시나리오: "a" 입력 → "ab" 입력 → "ab" 응답 → "a" 응답 순서로 완료');
  search.search('a');
  search.search('ab');
  print('   백엔드 호출 횟수: ${backend.callCount}');
  backend.completeRequest('ab', ['abandon', 'abstract']);
  await Future<void>.delayed(Duration.zero);
  print('   "ab" 응답 완료 후 currentResults: ${search.currentResults}');
  backend.completeRequest('a', ['apple']);
  await Future<void>.delayed(Duration.zero);
  print('   "a" 응답 완료 후 currentResults: ${search.currentResults}');
  final bool bugReproduced = search.currentResults?.query == 'a';
  print('   ✓ 버그 재현: ${bugReproduced ? "최신 쿼리 \"ab\"인데 결과는 \"a\"" : "예상과 다름"}');
  return bugReproduced;
}

Future<bool> demonstrateSequenceToken() async {
  print('2. SequenceTokenSearch: 요청 id로 늦게 도착한 응답 무시 (latest-wins)');
  final FakeSearchBackend backend = FakeSearchBackend();
  final SequenceTokenSearch search = SequenceTokenSearch(backend);
  print('   시나리오: "a" 입력 → "ab" 입력 → "a" 응답 → "ab" 응답 순서로 완료');
  search.search('a');
  search.search('ab');
  backend.completeRequest('a', ['apple']);
  await Future<void>.delayed(Duration.zero);
  print('   "a" 응답 완료 후 currentResults: ${search.currentResults}');
  backend.completeRequest('ab', ['abandon', 'abstract']);
  await Future<void>.delayed(Duration.zero);
  print('   "ab" 응답 완료 후 currentResults: ${search.currentResults}');
  final bool latestWins = search.currentResults?.query == 'ab';
  print('   ✓ latest-wins: ${latestWins ? "최신 쿼리 \"ab\" 결과만 표시" : "실패"}');
  return latestWins;
}

Future<bool> demonstrateSubscriptionCancel() async {
  print('3. SubscriptionCancelSearch: StreamSubscription 취소로 늦은 응답 무시');
  final FakeSearchBackend backend = FakeSearchBackend();
  final SubscriptionCancelSearch search = SubscriptionCancelSearch(backend);
  print('   시나리오: "a" 입력 → "ab" 입력 (구독 취소) → "a" 응답 → "ab" 응답');
  search.search('a');
  await Future<void>.delayed(Duration.zero);
  search.search('ab');
  await Future<void>.delayed(Duration.zero);
  backend.completeRequest('a', ['apple']);
  await Future<void>.delayed(Duration.zero);
  print('   "a" 응답 완료 후 currentResults: ${search.currentResults}');
  backend.completeRequest('ab', ['abandon', 'abstract']);
  await Future<void>.delayed(Duration.zero);
  print('   "ab" 응답 완료 후 currentResults: ${search.currentResults}');
  final bool latestWins = search.currentResults?.query == 'ab';
  print('   ✓ latest-wins: ${latestWins ? "최신 쿼리 \"ab\" 결과만 표시" : "실패"}');
  print('   주의: 구독 취소는 응답 무시만 하고 백엔드 작업은 계속 진행됨');
  search.dispose();
  return latestWins;
}

Future<bool> demonstrateDebounce() async {
  print('4. DebounceSearch: Timer 기반 디바운스 (단독 사용)');
  final FakeSearchBackend backend = FakeSearchBackend();
  final DebounceSearch search = DebounceSearch(
    backend,
    debounceDuration: Duration(milliseconds: 10),
  );
  print('   시나리오: 디바운스로 호출 횟수 감소, 하지만 순서 문제는 여전히 발생 가능');
  search.search('a');
  search.search('ab');
  search.search('abc');
  await Future<void>.delayed(Duration(milliseconds: 50));
  print('   백엔드 호출 횟수: ${backend.callCount} (디바운스로 감소)');
  print('   주의: 두 요청이 겹치면 순서 문제는 여전히 발생 가능');
  print('   ✓ 디바운스는 호출 횟수를 줄이지만 race condition 자체를 해결하지 않음');
  search.dispose();
  return true;
}

Future<bool> demonstrateDebounceWithSequenceToken() async {
  print('5. DebounceWithSequenceTokenSearch: 디바운스 + 시퀀스 토큰 조합');
  final FakeSearchBackend backend = FakeSearchBackend();
  final DebounceWithSequenceTokenSearch search =
      DebounceWithSequenceTokenSearch(
        backend,
        debounceDuration: Duration(milliseconds: 10),
      );
  print('   시나리오: 디바운스로 호출 횟수 감소 + 시퀀스 토큰으로 순서 문제 해결');
  search.search('a');
  search.search('ab');
  search.search('abc');
  await Future<void>.delayed(Duration(milliseconds: 50));
  print('   백엔드 호출 횟수: ${backend.callCount} (디바운스로 감소)');
  print('   ✓ 디바운스 + 시퀀스 토큰 조합으로 호출 최적화 + 순서 문제 해결');
  search.dispose();
  return true;
}

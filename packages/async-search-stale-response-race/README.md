# 검색 입력 중 늦게 도착한 비동기 응답이 최신 결과를 덮어쓰는 문제와 해결 설계 비교

검색창에 "a" → "ab" 순서로 입력했는데 백엔드 응답이 "ab" → "a" 순서로 도착하면 화면에 표시된 결과는 "a"가 되고, 사용자가 입력한 최신 쿼리 "ab"와 불일치하는 문제를 재현하고, 시퀀스 토큰·구독 취소·디바운스 설계로 해결하는 방법을 실행과 테스트로 비교한다.

## 검증하는 질문

1. **NaiveSearch (버그 재현)**: `await backend.search(query)` 방식으로 검색하면 응답 순서가 뒤바뀔 때 늦게 도착한 응답이 최신 결과를 덮어쓰는가?
2. **SequenceTokenSearch (latest-wins)**: 요청마다 증가하는 id를 할당하고, 응답이 도착했을 때 id가 현재 최신이 아니면 무시하면 문제가 해결되는가? 늦게 도착한 에러는 무시되고 최신 요청의 에러만 표시되는가?
3. **SubscriptionCancelSearch (구독 취소)**: Future를 `asStream()`으로 감싸고 StreamSubscription으로 관리하면서 새 요청 시 이전 구독을 취소하면 문제가 해결되는가? 구독 취소가 백엔드 작업을 멈추지 않고 응답 무시만 한다는 것을 테스트로 확인할 수 있는가?
4. **DebounceSearch (디바운스 단독)**: Timer 기반 디바운스로 연속 입력 시 백엔드 호출 횟수를 줄일 수 있는가? 디바운스만으로는 두 요청이 겹칠 때 순서 문제를 해결하지 못하는가?
5. **DebounceWithSequenceTokenSearch (조합)**: 디바운스와 시퀀스 토큰을 함께 사용하면 호출 횟수 최적화와 순서 문제를 모두 해결할 수 있는가?

각 시나리오는 FakeSearchBackend의 Completer를 테스트가 직접 완료하여 응답 순서를 결정하고, 최종 표시 결과를 확인한다.

## 구현 비교

| 설계 | 버그 재현 | 늦게 도착한 응답 | 에러 처리 | 백엔드 호출 횟수 | 취소 시 백엔드 작업 |
|------|----------|----------------|----------|----------------|------------------|
| NaiveSearch | O (최신 쿼리와 결과 불일치) | 덮어씀 | 에러도 덮어씀 | 입력마다 호출 | - |
| SequenceTokenSearch | X | 무시됨 | 늦게 도착한 에러 무시, 최신 에러만 표시 | 입력마다 호출 | - |
| SubscriptionCancelSearch | X | 무시됨 | 늦게 도착한 에러 무시, 최신 에러만 표시 | 입력마다 호출 | 계속 진행 (응답만 무시) |
| DebounceSearch | △(겹치면 발생) | 덮어씀 | 에러도 덮어씀 | 디바운스로 감소 | - |
| DebounceWithSequenceTokenSearch | X | 무시됨 | 늦게 도착한 에러 무시, 최신 에러만 표시 | 디바운스로 감소 | - |

## 핵심 코드 발췌

### 1. FakeSearchBackend (Completer 기반 가짜 백엔드)

```dart
class FakeSearchBackend {
  final Map<String, Completer<SearchResult>> _pendingRequests = {};
  int _requestCounter = 0;

  Future<SearchResult> search(String query) {
    _requestCounter++;
    final Completer<SearchResult> completer = Completer<SearchResult>();
    _pendingRequests[query] = completer;
    return completer.future;
  }

  void completeRequest(String query, List<String> items) {
    _pendingRequests[query]!.complete(SearchResult(query: query, items: items));
  }

  void failRequest(String query, Object error) {
    _pendingRequests[query]!.completeError(error);
  }
}
```

테스트가 `completeRequest`와 `failRequest`를 호출하는 순서를 직접 결정하므로 응답 순서를 완전히 제어할 수 있다. 네트워크 지연이나 sleep 없이 결정적으로 동작한다.

### 2. NaiveSearch (버그 재현)

```dart
class NaiveSearch extends SearchController {
  @override
  Future<void> search(String query) async {
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    try {
      final SearchResult result = await backend.search(query);
      _currentResults = result;
    } catch (error) {
      _currentError = error;
      _currentResults = null;
    }
  }
}
```

`await` 후 무조건 `_currentResults`에 대입하므로, "a" → "ab" 순서로 요청하고 "ab" → "a" 순서로 응답이 도착하면 최종적으로 "a"가 표시된다.

### 3. SequenceTokenSearch (latest-wins)

```dart
class SequenceTokenSearch extends SearchController {
  int _requestId = 0;

  @override
  Future<void> search(String query) async {
    _requestId++;
    final int currentRequestId = _requestId;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    try {
      final SearchResult result = await backend.search(query);
      if (currentRequestId == _requestId) {
        _currentResults = result;
      }
    } catch (error) {
      if (currentRequestId == _requestId) {
        _currentError = error;
        _currentResults = null;
      }
    }
  }
}
```

요청마다 `_requestId`를 증가시키고, 응답 도착 시 `currentRequestId == _requestId`를 확인하여 최신 요청이 아니면 무시한다. 에러도 동일하게 처리한다.

### 4. SubscriptionCancelSearch (구독 취소)

```dart
class SubscriptionCancelSearch extends SearchController {
  StreamSubscription<SearchResult>? _subscription;

  @override
  Future<void> search(String query) async {
    await _subscription?.cancel();
    _subscription = null;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Future<SearchResult> future = backend.search(query);
    _subscription = future.asStream().listen(
      (SearchResult result) {
        _currentResults = result;
      },
      onError: (Object error) {
        _currentError = error;
        _currentResults = null;
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
```

Future를 Stream으로 변환하고 StreamSubscription으로 관리한다. 새 요청 시 이전 구독을 취소하여 응답을 무시한다. 단, 구독 취소는 백엔드 Future의 실행을 멈추지 않고 리스너만 제거한다.

### 5. DebounceSearch (디바운스 단독)

```dart
class DebounceSearch extends SearchController {
  final Duration debounceDuration;
  Timer? _debounceTimer;

  @override
  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _debounceTimer = Timer(debounceDuration, () async {
      try {
        final SearchResult result = await backend.search(query);
        _currentResults = result;
      } catch (error) {
        _currentError = error;
        _currentResults = null;
      }
      completer.complete();
    });
    return completer.future;
  }
}
```

연속 입력 시 이전 Timer를 취소하고 새 Timer를 시작하여 마지막 입력만 백엔드에 전달한다. 호출 횟수를 줄이지만, Timer 시간 내에 두 요청이 모두 발생하면 순서 문제는 여전히 발생할 수 있다.

### 6. DebounceWithSequenceTokenSearch (조합)

```dart
class DebounceWithSequenceTokenSearch extends SearchController {
  final Duration debounceDuration;
  Timer? _debounceTimer;
  int _requestId = 0;

  @override
  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    _requestId++;
    final int currentRequestId = _requestId;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _debounceTimer = Timer(debounceDuration, () async {
      try {
        final SearchResult result = await backend.search(query);
        if (currentRequestId == _requestId) {
          _currentResults = result;
        }
      } catch (error) {
        if (currentRequestId == _requestId) {
          _currentError = error;
          _currentResults = null;
        }
      }
      completer.complete();
    });
    return completer.future;
  }
}
```

디바운스로 호출 횟수를 줄이고, 시퀀스 토큰으로 순서 문제를 해결한다.

## 실행 방법

### 데모 실행

```bash
dart run src/query_results_demo.dart
```

모든 검증이 통과하면 `ALL_CHECKS_PASSED`를 출력하고 exit code 0으로 종료한다.

### 테스트 실행

```bash
dart run test/search_implementations_test.dart
```

### 정적 분석

```bash
dart analyze
```

### 코드 포맷

```bash
dart format --set-exit-if-changed .
```

## 실행 결과

### Dart 버전

```
Dart SDK version: 3.14.1 (stable) (Tue Nov 17 00:01:24 2026 -0800) on "linux_x64"
```

### dart analyze

```
Analyzing async-search-stale-response-race...
No issues found!
```

### dart format --set-exit-if-changed .

```
Formatted 4 files (0 changed) in 0.01 seconds.
```

### dart run src/query_results_demo.dart

```
=== 검색 입력 중 늦게 도착한 비동기 응답의 최신 결과 덮어쓰기 문제 시연 ===

1. NaiveSearch: 늦게 도착한 응답이 최신 결과를 덮어쓰는 문제
   시나리오: "a" 입력 → "ab" 입력 → "ab" 응답 → "a" 응답 순서로 완료
   백엔드 호출 횟수: 2
   "ab" 응답 완료 후 currentResults: SearchResult(query: "ab", items: [abandon, abstract])
   "a" 응답 완료 후 currentResults: SearchResult(query: "a", items: [apple])
   ✓ 버그 재현: 최신 쿼리 "ab"인데 결과는 "a"

2. SequenceTokenSearch: 요청 id로 늦게 도착한 응답 무시 (latest-wins)
   시나리오: "a" 입력 → "ab" 입력 → "a" 응답 → "ab" 응답 순서로 완료
   "a" 응답 완료 후 currentResults: null
   "ab" 응답 완료 후 currentResults: SearchResult(query: "ab", items: [abandon, abstract])
   ✓ latest-wins: 최신 쿼리 "ab" 결과만 표시

3. SubscriptionCancelSearch: StreamSubscription 취소로 늦은 응답 무시
   시나리오: "a" 입력 → "ab" 입력 (구독 취소) → "a" 응답 → "ab" 응답
   "a" 응답 완료 후 currentResults: null
   "ab" 응답 완료 후 currentResults: SearchResult(query: "ab", items: [abandon, abstract])
   ✓ latest-wins: 최신 쿼리 "ab" 결과만 표시
   주의: 구독 취소는 응답 무시만 하고 백엔드 작업은 계속 진행됨

4. DebounceSearch: Timer 기반 디바운스 (단독 사용)
   시나리오: 디바운스로 호출 횟수 감소, 하지만 순서 문제는 여전히 발생 가능
   백엔드 호출 횟수: 1 (디바운스로 감소)
   주의: 두 요청이 겹치면 순서 문제는 여전히 발생 가능
   ✓ 디바운스는 호출 횟수를 줄이지만 race condition 자체를 해결하지 않음

5. DebounceWithSequenceTokenSearch: 디바운스 + 시퀀스 토큰 조합
   시나리오: 디바운스로 호출 횟수 감소 + 시퀀스 토큰으로 순서 문제 해결
   백엔드 호출 횟수: 1 (디바운스로 감소)
   ✓ 디바운스 + 시퀀스 토큰 조합으로 호출 최적화 + 순서 문제 해결

ALL_CHECKS_PASSED
```

### dart run test/search_implementations_test.dart

```
=== 검색 입력 중 비동기 응답 순서 문제 테스트 ===

FakeSearchBackend 테스트

✓ Backend: 요청과 응답 관리
✓ Backend: 실패 처리
✓ Backend: reset 후 상태 초기화

NaiveSearch 테스트


SequenceTokenSearch 테스트


SubscriptionCancelSearch 테스트


DebounceSearch 테스트


DebounceWithSequenceTokenSearch 테스트


경계 조건 테스트

✓ 경계: SearchResult equality

=== 테스트 결과 ===
전체: 27개
통과: 27개
실패: 0개

모든 테스트 통과!
```

## 헷갈리는 점

- **Naive 방식의 버그는 실제로 발생한다**: 검색창에 "a"를 입력하고 빠르게 "ab"를 입력했는데 "a"의 응답이 느려서 나중에 도착하면, 화면에는 "a"의 결과가 표시되고 사용자는 "ab"를 입력했다고 생각하므로 혼란스럽다. 이는 네트워크 지연이 가변적일 때 흔히 발생한다.

- **시퀀스 토큰은 간단하고 효과적이다**: 요청마다 증가하는 id를 할당하고, 응답 도착 시 id를 비교하여 최신이 아니면 무시하는 방식은 구현이 간단하고 메모리 오버헤드가 거의 없다. 단, 요청 순서와 응답 순서가 완전히 뒤바뀔 수 있다는 가정이 필요하다.

- **구독 취소는 백엔드 작업을 멈추지 않는다**: `StreamSubscription.cancel()`은 리스너를 제거하여 응답을 무시하지만, 백엔드의 Future는 계속 실행되고 완료된다. 네트워크 요청을 실제로 취소하려면 `CancelToken`(dio) 같은 별도 메커니즘이 필요하다. 이 예제에서는 FakeSearchBackend가 Completer를 계속 가지고 있어, 테스트가 `completeRequest`를 호출하면 완료됨을 확인할 수 있다.

- **디바운스 단독으로는 순서 문제를 해결하지 못한다**: 디바운스는 연속 입력 시 마지막 입력만 백엔드에 전달하여 호출 횟수를 줄인다. 하지만 디바운스 시간 내에 두 요청이 모두 발생하지 않고 간격이 벌어지면 두 요청이 모두 백엔드에 전달되고, 응답 순서가 뒤바뀌면 순서 문제가 발생한다.

- **디바운스 + 시퀀스 토큰 조합이 최선이다**: 디바운스로 호출 횟수를 줄여 백엔드 부하를 낮추고, 시퀀스 토큰으로 순서 문제를 해결한다. 실제 검색창 구현에서 많이 사용하는 패턴이다.

- **에러 처리도 latest-wins가 필요하다**: 늦게 도착한 요청의 에러를 무시하지 않으면, 사용자가 새 검색을 시작한 후 이전 검색의 에러가 표시되어 혼란스럽다. 시퀀스 토큰과 구독 취소 방식은 에러도 동일한 로직으로 처리한다.

- **빈 쿼리 처리**: 검색창을 지우면(빈 문자열) 결과를 null로 설정하고 백엔드를 호출하지 않는다. 이는 불필요한 호출을 줄이는 일반적인 최적화다.

- **dispose 후 응답 무시**: SubscriptionCancelSearch의 dispose 후에는 구독이 취소되어 응답을 무시한다. 이는 위젯이 dispose된 후 setState를 호출하지 않도록 방지하는 패턴과 유사하다.

- **같은 쿼리 두 번**: 사용자가 "a"를 입력하고, 다시 "a"를 입력하면(또는 프로그래밍 오류로 중복 호출) 두 요청이 모두 백엔드에 전달된다. 시퀀스 토큰 방식은 첫 번째 "a" 응답을 무시하고 두 번째 "a" 응답만 표시한다.

- **SearchResult equality**: 테스트에서 결과를 비교하기 위해 `SearchResult`는 `==`와 `hashCode`를 오버라이드한다. query와 items를 모두 비교한다.

- **Completer 기반 테스트의 장점**: 실제 네트워크 호출이나 Timer.sleep 없이 응답 순서를 완전히 제어할 수 있어 테스트가 빠르고 결정적이다. 테스트가 `completeRequest`를 호출하는 순서를 바꾸면 다양한 시나리오를 재현할 수 있다.

- **실제 사용 시 고려사항**: 이 예제는 pure Dart로 구현되어 Flutter SDK 없이 실행할 수 있다. 실제 Flutter 앱에서는 ChangeNotifier나 Riverpod StateNotifier로 감싸고, UI는 결과를 watch/listen하여 rebuild한다. 시퀀스 토큰 로직은 동일하게 적용된다.

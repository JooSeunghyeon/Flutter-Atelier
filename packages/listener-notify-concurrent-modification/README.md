# 리스너 알림 중 concurrent modification과 Flutter ChangeNotifier 지연 제거 비교

Dart에서 리스너 목록을 순회하며 알림을 보내는 도중 리스너가 자신/다른 리스너를 제거하거나 새 리스너를 추가할 때 생기는 문제(ConcurrentModificationError, 인덱스 루프의 조용한 건너뛰기, 스냅샷 복사의 '이미 제거된 리스너 호출')와 Flutter ChangeNotifier 방식의 지연 제거(slot을 null로 비우고 가장 바깥 notify가 끝난 뒤 압축) 설계를 실행·테스트로 비교한다.

## 검증하는 질문

1. **Naive for-in 순회**: 알림 중 리스너를 제거하면 `ConcurrentModificationError`가 발생하는가? 첫 리스너는 실행되는가? 리스너 예외가 뒤 리스너 실행을 막는가?
2. **인덱스 for 루프**: 자기 자신을 제거하는 리스너는 다음 리스너를 건너뛰게 하는가? 다음 알림에서는 정상 호출되는가?
3. **스냅샷 복사**: 알림마다 `List.of`로 복사하면 오류가 없는가? 앞 리스너가 제거한 뒤 리스너가 그 라운드에 호출되는가? 알림 중 추가된 리스너는 다음 라운드부터 호출되는가? 복사 원소 수는 리스너 수 × 알림 횟수인가?
4. **지연 제거 (Flutter ChangeNotifier 방식)**: 알림 중 제거된 리스너는 즉시 호출되지 않는가? 슬롯을 null로 비우고 가장 바깥 notify 종료 시 1회만 압축하는가? 재진입 notify 지원하는가? 리스너 예외를 수집하고 나머지 리스너를 계속 호출하는가? dispose 후 StateError를 던지는가?

각 시나리오는 호출 로그와 오류 타입으로 동작을 확인한다.

## 구현 비교

| 구현 | 알림 중 제거 | 제거된 리스너 호출 | 추가 리스너 호출 시점 | 알림당 복사 원소 수 | 예외 처리 |
|------|-------------|-------------------|---------------------|-------------------|-----------|
| NaiveForInNotifier | ConcurrentModificationError | N/A | N/A | 0 | 전파 (뒤 리스너 실행 중단) |
| IndexLoopNotifier | 다음 리스너 건너뜀 (조용한 버그) | N/A | N/A | 0 | 전파 (뒤 리스너 실행 중단) |
| SnapshotNotifier | 오류 없음 | 그 라운드에만 호출 | 다음 라운드부터 | 리스너 수 | 전파 (뒤 리스너 실행 중단) |
| DeferredRemovalNotifier | 오류 없음 | 호출 안 됨 | 다음 라운드부터 | 0 | 수집 후 계속 실행 |

## 핵심 코드 발췌

### 1. NaiveForInNotifier (for-in 직접 순회)

```dart
@override
void notifyListeners() {
  for (final VoidCallback listener in _listeners) {
    listener();
  }
}
```

알림 중 `_listeners`가 변경되면 `ConcurrentModificationError`가 발생한다.

### 2. IndexLoopNotifier (인덱스 for 루프)

```dart
@override
void notifyListeners() {
  for (var i = 0; i < _listeners.length; i++) {
    _listeners[i]();
  }
}
```

현재 리스너(인덱스 i)가 자기 자신을 제거하면 다음 리스너(원래 인덱스 i+1)가 인덱스 i로 이동하지만 루프는 i+1로 진행되어 건너뛴다.

### 3. SnapshotNotifier (List.of로 복사 후 순회)

```dart
@override
void notifyListeners() {
  final List<VoidCallback> snapshot = List.of(_listeners);
  snapshotCopies++;
  copiedElements += snapshot.length;
  for (final VoidCallback listener in snapshot) {
    listener();
  }
}
```

알림마다 리스너 목록을 복사하므로 오류는 없지만, 앞 리스너가 제거한 뒤 리스너도 스냅샷에 있어 그 라운드에 호출된다. 성능 비교를 위해 `snapshotCopies`와 `copiedElements`를 기록한다.

### 4. DeferredRemovalNotifier (지연 제거, ChangeNotifier 방식)

```dart
List<VoidCallback?> _listeners = [];
int _notificationDepth = 0;
int _removalsPending = 0;

@override
bool removeListener(VoidCallback listener) {
  for (int i = 0; i < _listeners.length; i++) {
    if (_listeners[i] == listener) {
      if (_notificationDepth > 0) {
        _listeners[i] = null;
        _removalsPending++;
      } else {
        _listeners.removeAt(i);
      }
      return true;
    }
  }
  return false;
}

@override
void notifyListeners() {
  if (_disposed) {
    throw StateError('Cannot notify listeners after dispose');
  }
  if (_listeners.isEmpty) {
    return;
  }
  _notificationDepth++;
  final int lengthAtStart = _listeners.length;
  final List<Object> errors = [];
  try {
    for (int i = 0; i < lengthAtStart; i++) {
      final VoidCallback? listener = _listeners[i];
      if (listener != null) {
        try {
          listener();
        } catch (error) {
          errors.add(error);
        }
      }
    }
  } finally {
    _notificationDepth--;
    if (_notificationDepth == 0 && _removalsPending > 0) {
      _compactListeners();
    }
  }
  if (errors.isNotEmpty) {
    throw errors.first;
  }
}

void _compactListeners() {
  _listeners = _listeners.where((VoidCallback? listener) => listener != null).cast<VoidCallback?>().toList();
  _removalsPending = 0;
  compactions++;
}
```

- 알림 중 `removeListener`는 슬롯을 null로 비우고 즉시 목록 길이를 변경하지 않는다
- 알림 시작 시점의 길이(`lengthAtStart`)까지만 순회하므로 알림 중 추가된 리스너는 이번 라운드에 호출되지 않는다
- 이미 제거된(null) 슬롯은 건너뛴다
- 재진입 notify(리스너 안에서 `notifyListeners` 호출)를 지원하며, 압축은 `_notificationDepth`가 0이 될 때(가장 바깥 라운드 종료 시) 1회만 발생한다
- 리스너 예외는 `errors` 리스트에 모으고 나머지 리스너 호출을 계속한다

## 실행 방법

### 데모 실행

```bash
dart run src/main.dart
```

모든 검증이 통과하면 `ALL_CHECKS_PASSED`를 출력하고 exit code 0으로 종료한다.

### 테스트 실행

```bash
dart run test/listener_notifiers_test.dart
```

### 정적 분석

```bash
dart analyze
```

## 실행 결과

### Dart 버전

```
Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "linux_x64"
```

### dart analyze

```
Analyzing listener-notify-concurrent-modification...
No issues found!
```

### dart run src/main.dart

```
=== Dart 리스너 알림 중 concurrent modification 비교 ===

1. NaiveForInNotifier (for-in 직접 순회)
   예상: 알림 중 제거 시 ConcurrentModificationError

   리스너 3개 등록 (A는 자기 제거, B는 C 제거)
   알림 전 listenerCount: 3
   ConcurrentModificationError 발생: Concurrent modification during iteration: Instance(length:2) of '_GrowableList'.
   호출 로그: [A]
   알림 후 listenerCount: 2
   ✓ 예상대로 ConcurrentModificationError 발생

2. IndexLoopNotifier (인덱스 for 루프)
   예상: 알림 중 제거 시 다음 리스너 건너뜀

   리스너 3개 등록 (A는 자기 제거)
   알림 전 listenerCount: 3
   첫 알림 호출 로그: [A, C]
   알림 후 listenerCount: 2
   두 번째 알림 호출 로그: [B, C]
   ✓ 첫 알림에서 B 건너뜀, 두 번째 알림에서 B 호출됨

3. SnapshotNotifier (List.of로 복사 후 순회)
   예상: 오류 없음, 제거된 리스너 그 라운드에만 호출

   리스너 3개 등록 (A는 C 제거)
   알림 전 listenerCount: 3
   알림 전 snapshotCopies: 0, copiedElements: 0
   첫 알림 호출 로그: [A, B, C]
   알림 후 listenerCount: 2
   알림 후 snapshotCopies: 1, copiedElements: 3
   두 번째 알림 (B가 D 추가) 호출 로그: [A, B]
   알림 후 listenerCount: 3
   알림 후 snapshotCopies: 2, copiedElements: 5
   세 번째 알림 호출 로그: [A, B, D]
   ✓ 제거된 리스너는 그 라운드에 호출, 추가된 리스너는 다음 라운드부터 호출

4. DeferredRemovalNotifier (지연 제거, ChangeNotifier 방식)
   예상: 제거된 리스너 미호출, 압축 1회, 예외 수집

   리스너 3개 등록 (A는 자기 자신과 C 제거)
   알림 전 listenerCount: 3
   알림 전 compactions: 0
   첫 알림 호출 로그: [A, B]
   알림 후 listenerCount: 1
   알림 후 compactions: 1
   재진입 알림 호출 로그: [RA, RB, RB]
   알림 후 compactions: 1
   예외 발생: Exception: 리스너 예외
   예외 발생 후 호출 로그: [B, error, D]
   ✓ 지연 제거, 압축 1회, 예외 수집 후 계속, dispose 후 StateError

ALL_CHECKS_PASSED
```

### dart run test/listener_notifiers_test.dart

```
=== 리스너 알림 concurrent modification 테스트 ===

언어 동작 테스트

✓ List for-in 중 remove는 ConcurrentModificationError
✓ List 마지막 원소 순회 중 removeLast는 다음 moveNext에서 ConcurrentModificationError
✓ Map.keys 순회 중 기존 키 값 갱신은 오류 없음
✓ Map.keys 순회 중 remove는 ConcurrentModificationError
✓ Set 순회 중 remove는 ConcurrentModificationError

NaiveForInNotifier 테스트

✓ Naive: 자기 제거 리스너에서 ConcurrentModificationError, 첫 리스너는 실행됨
✓ Naive: 리스너 예외가 뒤 리스너 실행을 막음

IndexLoopNotifier 테스트

✓ IndexLoop: 자기 제거 시 다음 리스너가 건너뛰어짐
✓ IndexLoop: 다음 라운드에는 호출됨

SnapshotNotifier 테스트

✓ Snapshot: 오류 없음
✓ Snapshot: 앞 리스너가 제거한 뒤 리스너가 그 라운드에 호출됨
✓ Snapshot: 제거된 리스너는 다음 라운드엔 호출 안 됨
✓ Snapshot: 알림 중 추가된 리스너는 다음 라운드부터
✓ Snapshot: copiedElements가 리스너 수 × 라운드 수와 일치

DeferredRemovalNotifier 테스트

✓ Deferred: 제거된 리스너 미호출
✓ Deferred: 자기 제거 OK
✓ Deferred: 알림 중 추가 리스너 다음 라운드부터
✓ Deferred: 재진입 notify 동작과 압축 1회
✓ Deferred: 알림 중 listenerCount 정확
✓ Deferred: 중복 add/remove 의미
✓ Deferred: 예외 수집 후 계속
✓ Deferred: 등록 안 된 remove false
✓ Deferred: 리스너 0개 notify
✓ Deferred: 알림 중 모든 리스너 제거 후 count 0
✓ Deferred: dispose 후 StateError

=== 테스트 결과 ===
전체: 25개
통과: 25개
실패: 0개

모든 테스트 통과!
```

## 헷갈리는 점

- **for-in은 컬렉션 변경에 민감하다**: Dart의 `for-in` 루프는 Iterator를 사용하며, 순회 중 컬렉션을 변경하면 `ConcurrentModificationError`가 발생한다. 이는 List, Set, Map.keys 모두에 적용된다. 단, Map.keys 순회 중 기존 키의 **값 갱신**은 키를 추가/제거하지 않으므로 오류가 발생하지 않는다.

- **인덱스 루프는 조용히 건너뛴다**: `for (var i = 0; i < list.length; i++)` 형태는 오류를 발생시키지 않지만, 현재 인덱스의 원소를 제거하면 다음 원소가 현재 인덱스로 이동하여 그 라운드에서 건너뛰어진다. 이는 발견하기 어려운 버그를 만든다.

- **스냅샷 복사는 제거된 리스너를 호출한다**: `List.of`로 복사하면 오류는 없지만, 앞 리스너가 제거한 뒤 리스너도 스냅샷에 포함되어 그 라운드에 호출된다. 이미 dispose된 리스너가 호출될 수 있다.

- **지연 제거는 제거된 리스너를 호출하지 않는다**: 알림 중 `removeListener`는 슬롯을 null로 비우므로, 같은 알림 라운드에서 그 리스너는 호출되지 않는다. dispose된 리스너가 호출되지 않음을 보장한다.

- **압축은 가장 바깥 notify 종료 시 1회만**: 재진입 notify(리스너 안에서 `notifyListeners` 호출)가 발생해도 압축은 `_notificationDepth`가 0이 될 때만 발생한다. 이는 압축 비용을 줄인다.

- **예외 수집 후 계속**: 리스너가 예외를 던져도 나머지 리스너는 계속 호출되며, 모든 예외는 `errors` 리스트에 수집된다. 첫 번째 예외만 알림 종료 후 전파된다.

- **같은 리스너를 여러 번 add 가능**: 같은 리스너를 두 번 add하면 두 번 호출되고, remove는 앞쪽 하나만 제거한다. Flutter ChangeNotifier와 동일한 동작이다.

- **알림 중 추가된 리스너는 다음 라운드부터**: 알림 시작 시점의 리스너 수(`lengthAtStart`)까지만 순회하므로, 알림 중 추가된 리스너는 다음 `notifyListeners` 호출부터 실행된다.

- **listenerCount는 null 슬롯 제외**: 알림 중에도 `listenerCount`는 null이 아닌 리스너만 세어 정확한 수를 반환한다.

- **dispose 후 addListener/notifyListeners는 StateError**: dispose된 notifier는 더 이상 사용할 수 없으며, 사용 시도는 `StateError`를 던진다.

- **복사 원소 수는 성능 지표**: SnapshotNotifier는 알림마다 리스너 목록을 복사하므로 `copiedElements`는 리스너 수 × 알림 횟수가 된다. DeferredRemovalNotifier는 복사하지 않으므로 복사 원소 수가 0이다. 리스너가 많고 알림이 빈번하면 복사 비용이 클 수 있다.

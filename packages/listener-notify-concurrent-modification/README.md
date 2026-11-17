# 리스너 알림 중 ConcurrentModificationError와 Flutter ChangeNotifier 지연 제거 비교

Dart에서 리스너 목록을 순회하며 알림을 보내는 도중 리스너가 자신/다른 리스너를 제거하거나 새 리스너를 추가할 때 생기는 문제(ConcurrentModificationError, 인덱스 루프의 조용한 건너뛰기, 스냅샷 복사의 '이미 제거된 리스너 호출')와 Flutter ChangeNotifier 방식의 지연 제거(slot을 null로 비우고 가장 바깥 notify가 끝난 뒤 압축) 설계를 실행·테스트로 비교한다.

## 검증하는 질문

1. **Naive for-in 순회**: 알림 중 리스너를 제거하면 `ConcurrentModificationError`가 발생하는가? 알림 중 추가도 다음 moveNext에서 ConcurrentModificationError가 발생하는가? 첫 리스너는 실행되는가? 리스너 예외가 뒤 리스너 실행을 막는가?
2. **인덱스 for 루프**: 자기 자신을 제거하는 리스너는 다음 리스너를 건너뛰게 하는가? 알림 중 끝에 추가된 리스너는 루프 조건이 길이를 재평가하여 같은 라운드에 호출되는가? 다음 알림에서는 정상 호출되는가?
3. **스냅샷 복사**: 알림마다 `List.of`로 복사하면 오류가 없는가? 앞 리스너가 제거한 뒤 리스너가 그 라운드에 호출되는가? 알림 중 추가된 리스너는 다음 라운드부터 호출되는가? 복사 원소 수는 리스너 수 × 알림 횟수인가?
4. **지연 제거 (Flutter ChangeNotifier 방식)**: 알림 중 제거된 리스너는 즉시 호출되지 않는가? 슬롯을 null로 비우고 가장 바깥 notify 종료 시 1회만 압축하는가? 재진입 notify 지원하는가? 리스너 예외를 errors에 수집하고 나머지 리스너를 계속 호출하는가? 알림 중 dispose는 StateError를 던지는가? dispose 후 StateError를 던지는가?

각 시나리오는 호출 로그와 오류 타입으로 동작을 확인한다.

**공통 시나리오 설명**: 리스너 A는 자기 자신을 제거하고, B는 C를 제거하고 D를 추가하며, C는 단순 로그만 남긴다. 첫 알림 후 A와 C가 제거되고 D가 추가된다. 두 번째 알림에서 B가 다시 실행되어 (이미 없는) C 제거를 시도하고 D를 또 추가하므로, 두 번째 알림 후 D가 두 번 등록되어 listenerCount는 3이 된다 (B, D, D).

## 구현 비교

| 구현 | 알림 중 제거 | 제거된 리스너 호출 | 추가 리스너 호출 시점 | 알림당 복사 원소 수 | 예외 처리 |
|------|-------------|-------------------|---------------------|-------------------|-----------|
| NaiveForInNotifier | ConcurrentModificationError | N/A | add도 다음 moveNext에서 ConcurrentModificationError | 0 | 전파 (뒤 리스너 실행 중단) |
| IndexLoopNotifier | 다음 리스너 건너뜀 (조용한 버그) | N/A | 같은 라운드 (끝에 추가되면 길이 재평가로 호출) | 0 | 전파 (뒤 리스너 실행 중단) |
| SnapshotNotifier | 오류 없음 | 그 라운드에만 호출 | 다음 라운드부터 | 매 알림마다 리스너 수만큼 복사 | 전파 (뒤 리스너 실행 중단) |
| DeferredRemovalNotifier | 오류 없음 | 호출 안 됨 | 다음 라운드부터 | 제거 없으면 0, 알림 중 제거 있으면 압축 시 남은 리스너 수 | errors에 누적, 계속 실행 |

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
final List<(Object, StackTrace)> errors = [];

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
  try {
    for (int i = 0; i < lengthAtStart; i++) {
      final VoidCallback? listener = _listeners[i];
      if (listener != null) {
        try {
          listener();
        } catch (error, stackTrace) {
          errors.add((error, stackTrace));
        }
      }
    }
  } finally {
    _notificationDepth--;
    if (_notificationDepth == 0 && _removalsPending > 0) {
      _compactListeners();
    }
  }
}

void _compactListeners() {
  _listeners = [for (final VoidCallback? listener in _listeners) if (listener != null) listener];
  _removalsPending = 0;
  compactions++;
}

void dispose() {
  if (_notificationDepth > 0) {
    throw StateError('Cannot dispose during notification');
  }
  _disposed = true;
  _listeners.clear();
}
```

- 알림 중 `removeListener`는 슬롯을 null로 비우고 즉시 목록 길이를 변경하지 않는다
- 알림 시작 시점의 길이(`lengthAtStart`)까지만 순회하므로 알림 중 추가된 리스너는 이번 라운드에 호출되지 않는다
- 이미 제거된(null) 슬롯은 건너뛴다
- 재진입 notify(리스너 안에서 `notifyListeners` 호출)를 지원하며, 압축은 `_notificationDepth`가 0이 될 때(가장 바깥 라운드 종료 시) 1회만 발생한다
- 리스너 예외는 `errors` 리스트에 `(Object, StackTrace)` 튜플로 수집하고 `notifyListeners`는 예외를 던지지 않는다. 나머지 리스너는 계속 호출된다
- 알림 중(_notificationDepth > 0) `dispose()`는 `StateError`를 던진다. 알림이 끝난 뒤에는 dispose가 허용된다

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
=== Dart 리스너 알림 중 ConcurrentModificationError 비교 ===

공통 시나리오: 리스너 A(자기 제거), B(C 제거 + D 추가), C

NaiveForInNotifier:
  리스너 등록: A(자기 제거), B(C 제거 + D 추가), C
  알림 전 listenerCount: 3
  첫 알림 호출 로그: [A]
  오류 발생: ConcurrentModificationError
  알림 후 listenerCount: 2
  ✓ ConcurrentModificationError 발생, A만 호출됨

IndexLoopNotifier:
  리스너 등록: A(자기 제거), B(C 제거 + D 추가), C
  알림 전 listenerCount: 3
  첫 알림 호출 로그: [A, C]
  알림 후 listenerCount: 2
  두 번째 알림 호출 로그: [B, D]
  알림 후 listenerCount: 2
  ✓ 첫 알림에서 B 건너뜀, 두 번째 알림에서 B와 D 호출됨

SnapshotNotifier:
  리스너 등록: A(자기 제거), B(C 제거 + D 추가), C
  알림 전 listenerCount: 3
  첫 알림 호출 로그: [A, B, C]
  알림 후 listenerCount: 2
  copiedElements: 3
  두 번째 알림 호출 로그: [B, D]
  알림 후 listenerCount: 3
  copiedElements: 5
  ✓ 제거된 C가 첫 알림에 호출됨, A는 자기 제거로 두 번째에 없음

DeferredRemovalNotifier:
  리스너 등록: A(자기 제거), B(C 제거 + D 추가), C
  알림 전 listenerCount: 3
  첫 알림 호출 로그: [A, B]
  알림 후 listenerCount: 2
  compactions: 1
  두 번째 알림 호출 로그: [B, D]
  알림 후 listenerCount: 3
  compactions: 1
  ✓ 제거된 C 미호출, A는 자기 제거로 두 번째에 없음, 압축 1회

DeferredRemovalNotifier 전용 동작 검증

1. 재진입 notify (리스너 안에서 notifyListeners 호출)
   호출 로그: [A, B, B]
   압축 횟수: 1 (이전: 0)
   ✓ 재진입 시 안쪽 notify가 실행되고 압축은 가장 바깥 종료 시 1회

2. 예외 수집 (리스너 예외를 errors에 모으고 계속 실행)
   호출 로그: [A, B, C, D]
   errors.length: 2
   ✓ 예외를 errors에 수집하고 나머지 리스너 계속 호출, StackTrace 기록됨

3. 알림 중 dispose 거부
   호출 로그: [A, dispose-error, B]
   dispose StateError 발생: true
   errors.length: 0
   ✓ 알림 중 dispose는 StateError를 던지고 나머지 리스너는 계속 호출됨

4. dispose 후 StateError
   dispose 후 addListener StateError: true
   dispose 후 notifyListeners StateError: true
   ✓ dispose 후 addListener/notifyListeners는 StateError

ALL_CHECKS_PASSED
```

### dart run test/listener_notifiers_test.dart

```
=== 리스너 알림 ConcurrentModificationError 테스트 ===

언어 동작 테스트

✓ List for-in 중 remove는 ConcurrentModificationError
✓ List 마지막 원소 순회 중 removeLast는 다음 moveNext에서 ConcurrentModificationError
✓ Map.keys 순회 중 기존 키 값 갱신은 오류 없음
✓ Map.keys 순회 중 remove는 ConcurrentModificationError
✓ Set 순회 중 remove는 ConcurrentModificationError

공통 시나리오 테스트 (A 자기제거, B가 C제거+D추가, C)

✓ Naive: 공통 시나리오에서 ConcurrentModificationError, A만 호출
✓ IndexLoop: 공통 시나리오에서 첫 알림 [A, C], 두 번째 [B, D]
✓ Snapshot: 공통 시나리오에서 첫 알림 [A, B, C], 두 번째 [B, D]
✓ Deferred: 공통 시나리오에서 첫 알림 [A, B], 두 번째 [B, D]

NaiveForInNotifier 테스트

✓ Naive: 자기 제거 리스너에서 ConcurrentModificationError, 첫 리스너는 실행됨
✓ Naive: 리스너 예외가 뒤 리스너 실행을 막음
✓ Naive: 알림 중 add도 다음 moveNext에서 ConcurrentModificationError

IndexLoopNotifier 테스트

✓ IndexLoop: 자기 제거 시 다음 리스너가 건너뛰어짐
✓ IndexLoop: 다음 라운드에는 호출됨
✓ IndexLoop: 알림 중 끝에 추가된 리스너가 같은 라운드에 호출됨 (길이 재평가)

SnapshotNotifier 테스트

✓ Snapshot: 오류 없음
✓ Snapshot: 앞 리스너가 제거한 뒤 리스너가 그 라운드에 호출됨 (오래된 호출)
✓ Snapshot: 제거된 리스너는 다음 라운드엔 호출 안 됨
✓ Snapshot: 알림 중 추가된 리스너는 다음 라운드부터
✓ Snapshot: copiedElements가 리스너 수 × 라운드 수와 일치

DeferredRemovalNotifier 테스트

✓ Deferred: 제거된 리스너 미호출
✓ Deferred: 자기 제거 OK
✓ Deferred: 알림 중 추가 리스너 다음 라운드부터
✓ Deferred: 알림 중 추가된 리스너를 같은 라운드에서 제거하면 한 번도 호출 안 됨
✓ Deferred: 재진입 notify 동작과 압축 1회
✓ Deferred: 알림 중 listenerCount 정확
✓ Deferred: 중복 add/remove 의미
✓ Deferred: 예외 수집 후 계속 (errors에 누적, notifyListeners는 던지지 않음)
✓ Deferred: 두 리스너가 예외를 던지면 errors에 순서대로 2개
✓ Deferred: 재진입 안쪽 오류는 정확히 1번만 기록
✓ Deferred: 등록 안 된 remove false
✓ Deferred: 리스너 0개 notify
✓ Deferred: 알림 중 모든 리스너 제거 후 count 0
✓ Deferred: 알림 중 dispose는 StateError를 던지고 나머지 리스너 계속 호출
✓ Deferred: dispose 후 StateError

=== 테스트 결과 ===
전체: 35개
통과: 35개
실패: 0개

모든 테스트 통과!
```

## 헷갈리는 점

- **for-in은 컬렉션 변경에 민감하다**: Dart의 `for-in` 루프는 Iterator를 사용하며, 순회 중 컬렉션을 변경하면 `ConcurrentModificationError`가 발생한다. 이는 List, Set, Map.keys 모두에 적용된다. 단, Map.keys 순회 중 기존 키의 **값 갱신**은 키를 추가/제거하지 않으므로 오류가 발생하지 않는다.

- **인덱스 루프는 조용히 건너뛴다**: `for (var i = 0; i < list.length; i++)` 형태는 오류를 발생시키지 않지만, 현재 인덱스의 원소를 제거하면 다음 원소가 현재 인덱스로 이동하여 그 라운드에서 건너뛰어진다. 이는 발견하기 어려운 버그를 만든다. 반대로 루프 조건이 매번 `list.length`를 재평가하므로 알림 중 끝에 원소를 추가하면 길이가 늘어나 같은 라운드에 그 원소도 순회된다.

- **스냅샷 복사는 제거된 리스너를 호출한다**: `List.of`로 복사하면 오류는 없지만, 앞 리스너가 제거한 뒤 리스너도 스냅샷에 포함되어 그 라운드에 호출된다. 이미 dispose된 리스너가 호출될 수 있다.

- **지연 제거는 제거된 리스너를 호출하지 않는다**: 알림 중 `removeListener`는 슬롯을 null로 비우므로, 같은 알림 라운드에서 그 리스너는 호출되지 않는다. dispose된 리스너가 호출되지 않음을 보장한다.

- **압축은 가장 바깥 notify 종료 시 1회만**: 재진입 notify(리스너 안에서 `notifyListeners` 호출)가 발생해도 압축은 `_notificationDepth`가 0이 될 때만 발생한다. 이는 압축 비용을 줄인다.

- **예외는 errors에 누적되고 notifyListeners는 던지지 않는다**: 리스너가 예외를 던져도 나머지 리스너는 계속 호출되며, 모든 예외는 `errors` 리스트에 `(Object, StackTrace)` 튜플로 수집된다. `notifyListeners`는 예외를 던지지 않으므로 Flutter의 보고 후 계속 실행하는 방식과 유사하다.

- **알림 중 dispose는 거부된다**: 알림 중(_notificationDepth > 0) `dispose()`는 `StateError`를 던진다. 이는 알림 중에 리스너 목록이 clear되어 `_listeners[i]` 접근 시 `RangeError`가 발생하는 것을 방지한다.

- **같은 리스너를 여러 번 add 가능**: 같은 리스너를 두 번 add하면 두 번 호출되고, remove는 앞쪽 하나만 제거한다. Flutter ChangeNotifier와 동일한 동작이다.

- **알림 중 추가된 리스너는 다음 라운드부터**: 알림 시작 시점의 리스너 수(`lengthAtStart`)까지만 순회하므로, 알림 중 추가된 리스너는 다음 `notifyListeners` 호출부터 실행된다.

- **알림 중 추가된 리스너를 같은 라운드에서 제거하면 한 번도 호출 안 됨**: 알림 중 추가된 리스너는 이번 라운드에 호출되지 않고, 같은 라운드에서 제거되면 null로 표시되어 다음 라운드에도 호출되지 않는다.

- **listenerCount는 null 슬롯 제외**: 알림 중에도 `listenerCount`는 null이 아닌 리스너만 세어 정확한 수를 반환한다.

- **dispose 후 addListener/notifyListeners는 StateError**: dispose된 notifier는 더 이상 사용할 수 없으며, 사용 시도는 `StateError`를 던진다.

- **복사 원소 수는 성능 지표**: SnapshotNotifier는 알림마다 리스너 목록을 복사하므로 `copiedElements`는 리스너 수 × 알림 횟수가 된다. DeferredRemovalNotifier는 알림 중 제거가 없으면 복사하지 않지만, 알림 중 제거가 있었으면 가장 바깥 notify 종료 시 압축 과정에서 남은 리스너 수만큼 새 리스트를 1회 만든다. 리스너가 많고 알림이 빈번하면 Snapshot의 복사 비용이 클 수 있다.

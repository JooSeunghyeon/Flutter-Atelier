# Iterable 지연 평가, 재평가, 스냅샷, 메모이즈 동작 비교

Dart `Iterable.map`과 `where`가 만든 지연 Iterable은 `toList()` 전까지 콜백을 실행하지 않고, 순회할 때마다 콜백을 다시 실행한다. 이 동작을 테스트로 고정하고, 세 가지 설계를 비교한다.

- **A. 지연 Iterable 그대로**: `map`/`where`가 반환한 Iterable을 여러 번 사용
- **B. 스냅샷(toList)**: 즉시 `toList()`로 평가하여 독립적인 List 생성
- **C. 메모이즈**: `MemoizedIterable` 구현으로 콜백을 원소당 1회만 실행하고 캐시

## 검증하는 질문

1. **지연성**: `map` 생성 시점에는 콜백을 실행하지 않는가? `length` 조회는 콜백을 실행하는가?
2. **재평가**: 지연 Iterable을 `toList()`나 `forEach`로 순회할 때마다 콜백을 다시 실행하는가?
3. **스냅샷 독립성**: `toList()`로 만든 List는 원본 컬렉션 변경에 영향받지 않는가?
4. **메모이즈 1회 평가**: `MemoizedIterable`은 콜백을 원소당 1회만 실행하는가? 여러 순회에서도 캐시를 재사용하는가?
5. **예외 시점**: 콜백에서 예외가 발생하면 `map` 생성이 아니라 소비 시점에 발생하는가?
6. **조기 종료**: `first`, `any`, `take` 등은 필요한 만큼만 평가하는가?
7. **원본 변경 반영**: 원본 List에 `add`로 원소를 추가하면 지연 Iterable, 스냅샷, 메모이즈가 각각 어떻게 동작하는가?
8. **순회 중 변경**: 순회 중 원본을 변경하면 `ConcurrentModificationError`가 발생하는가?
9. **체인 호출 횟수**: `map` → `where` 체인에서 `length`를 두 번 호출하면 콜백이 몇 회 실행되는가?

## 실행 방법

### 데모 실행

```bash
dart run src/iterable_lazy_demo.dart
```

모든 검증이 통과하면 `ALL_CHECKS_PASSED`를 출력하고 exit code 0으로 종료한다.

### 테스트 실행

```bash
dart run test/iterable_lazy_test.dart
```

28개 테스트를 실행한다.

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
Dart SDK version: 3.6.0 (stable) (Thu Dec 5 07:46:24 2024 -0800) on "linux_x64"
```

### dart analyze

```
Analyzing iterable-lazy-reevaluation-snapshot-memoize...
No issues found!
```

### dart format --set-exit-if-changed .

```
Formatted 4 files (0 changed) in 0.20 seconds.
```

### dart run src/iterable_lazy_demo.dart

```
=== Iterable 지연 평가, 재평가, 스냅샷, 메모이즈 비교 ===

1. 지연 평가: map 생성 시점에는 콜백을 실행하지 않는다

✓    map 생성 직후 콜백 호출 0회
✓    length 조회는 콜백을 실행하지 않음 (MappedListIterable 최적화)

2. 재평가: 지연 Iterable을 순회할 때마다 콜백을 다시 실행한다

✓    첫 번째 toList(): 콜백 3회 호출
✓    두 번째 toList(): 콜백 총 6회 호출 (3회 추가)
✓    결과는 동일: [10, 20, 30]

3. 스냅샷(toList): 한 번 평가하고 독립적인 List를 만든다

✓    toList(): 콜백 3회 호출
✓    원본 변경 후 lazy.toList(): 콜백 4회 추가 (총 7회)
✓    스냅샷은 원본 변경에 영향받지 않음: [10, 20, 30]
✓    지연 Iterable은 원본 변경을 반영: [10, 20, 30, 40]

4. 메모이즈: 콜백을 원소당 1회만 실행하고 캐시한다

✓    첫 번째 toList(): 콜백 3회 호출
✓    두 번째 toList(): 콜백 추가 호출 없음 (메모이즈됨)
✓    결과는 동일: [10, 20, 30]

5. 예외 시점: 지연 Iterable은 소비 시점에 예외가 발생한다

✓    map 생성: 예외 없음
✓    toList(): UnsupportedError 발생
✓    first: 첫 원소만 평가, 예외 없음 (10)

6. 조기 종료: first, any, take 등은 필요한 만큼만 평가한다

✓    first: 콜백 1회만 호출
✓    any((x)=>x==30): 콜백 3회 호출 (조기 종료)
✓    take(2).toList(): 콜백 2회만 호출

7. 체인: map → where 체인도 순회마다 모든 단계를 재실행한다

✓    첫 번째 length: 콜백 5회 호출, 결과 3개
✓    두 번째 length: 콜백 5회 추가 (총 10회)

8. 메모이즈 부분 소비: Iterator를 중간에 멈춰도 다음 Iterator가 이어받는다

✓    첫 Iterator 2개 소비: 콜백 2회
✓    두 번째 Iterator 3개 소비: 콜백 1회 추가 (총 3회)

9. 원본 변경 반영 차이

✓    A(지연): 원본 변경 반영됨 [10, 20, 30]
✓    B(스냅샷): 원본 변경 반영 안 됨 [10, 20]
✓    C(메모이즈): 캐시된 결과만 반환 [10, 20]

10. elementAt과 contains 최적화 비교

✓    lazy.elementAt(3): 콜백 1회 (MappedListIterable 최적화)
✓    lazy.contains(30): 콜백 3회 (조기 종료)

=== 설계 비교 요약 ===

| 설계 | 콜백 호출 | 예외 시점 | 원본 변경 | 메모리 |
|------|----------|----------|----------|--------|
| A(지연) | 순회마다 전체 | 소비 시점 | 반영됨 | 최소 |
| B(스냅샷) | 1회 | toList 시점 | 반영 안 됨 | 전체 복사 |
| C(메모이즈) | 원소당 1회 | 첫 소비 시점 | 캐시 고정 | 점진적 증가 |

ALL_CHECKS_PASSED
```

### dart run test/iterable_lazy_test.dart

```
=== Iterable 지연 평가, 재평가, 스냅샷, 메모이즈 테스트 ===

지연성 테스트

✓ 지연: map 생성 시점에는 콜백을 실행하지 않음
✓ 지연: length 조회는 콜백을 실행하지 않음 (MappedListIterable)
✓ 지연: isEmpty 조회는 콜백을 실행하지 않음

재평가 테스트

✓ 재평가: toList 호출마다 콜백을 다시 실행
✓ 재평가: forEach 호출마다 콜백을 다시 실행
✓ 재평가: iterator 순회마다 콜백을 다시 실행

스냅샷(toList) 테스트

✓ 스냅샷: toList는 한 번 평가하여 독립적인 List 생성
✓ 스냅샷: 스냅샷은 원본과 독립적

메모이즈 테스트

✓ 메모이즈: 콜백을 원소당 1회만 실행
✓ 메모이즈: 여러 순회에서도 콜백은 1회만
✓ 메모이즈: 부분 소비 후 다른 Iterator가 이어받음
✓ 메모이즈: 여러 Iterator 교차 순회

예외 처리 테스트

✓ 예외: 지연 Iterable은 소비 시점에 예외 발생
✓ 예외: first는 첫 원소만 평가하므로 예외 회피 가능
✓ 예외: 메모이즈는 예외 발생 시 캐시하지 않고 재시도

조기 종료 테스트

✓ 조기 종료: first는 첫 원소만 평가
✓ 조기 종료: any는 조건 만족 시 중단
✓ 조기 종료: take는 지정 개수만 평가
✓ 조기 종료: where + first는 조건 만족까지만 평가

경계 조건 테스트

✓ 경계: 빈 입력
✓ 경계: 원소 1개
✓ 경계: null 허용 원소

원본 변경 테스트

✓ 원본 변경: 지연 Iterable은 원본 변경을 반영
✓ 원본 변경: 스냅샷은 원본 변경을 반영하지 않음
✓ 원본 변경: 메모이즈는 캐시 고정
✓ 원본 변경: 순회 중 원본 변경은 ConcurrentModificationError

체인 테스트

✓ 체인: map → where 호출 횟수
✓ 체인: 메모이즈 체인은 호출 횟수 유지

=== 테스트 결과 ===
전체: 28개
통과: 28개
실패: 0개

모든 테스트 통과!
```

## 핵심 코드 발췌

### 1. CallCounter (콜백 호출 추적 헬퍼)

```dart
class CallCounter {
  int count = 0;

  int Function(int) wrap(int Function(int) fn) {
    return (int x) {
      count++;
      return fn(x);
    };
  }

  void reset() {
    count = 0;
  }
}
```

콜백을 감싸서 호출 횟수를 센다. 테스트와 데모에서 지연 평가와 재평가를 확인하는 데 사용한다.

### 2. MemoizedIterable (메모이즈 구현)

```dart
class MemoizedIterable<T> extends Iterable<T> {
  final Iterable<T> _source;
  final List<T> _cache = [];
  late final Iterator<T> _sourceIterator;
  bool _sourceExhausted = false;
  bool _iteratorInitialized = false;

  MemoizedIterable(this._source);

  @override
  Iterator<T> get iterator => _MemoizedIterator<T>(this);

  void _ensureIteratorInitialized() {
    if (!_iteratorInitialized) {
      _sourceIterator = _source.iterator;
      _iteratorInitialized = true;
    }
  }

  bool _fetchNext() {
    _ensureIteratorInitialized();
    if (_sourceExhausted) {
      return false;
    }
    final bool hasNext = _sourceIterator.moveNext();
    if (!hasNext) {
      _sourceExhausted = true;
      return false;
    }
    _cache.add(_sourceIterator.current);
    return true;
  }
}

class _MemoizedIterator<T> implements Iterator<T> {
  final MemoizedIterable<T> _parent;
  int _index = -1;

  _MemoizedIterator(this._parent);

  @override
  T get current {
    if (_index < 0 || _index >= _parent._cache.length) {
      throw StateError('No element');
    }
    return _parent._cache[_index];
  }

  @override
  bool moveNext() {
    final int nextIndex = _index + 1;
    if (nextIndex < _parent._cache.length) {
      _index = nextIndex;
      return true;
    }
    if (_parent._sourceExhausted) {
      return false;
    }
    final bool fetched = _parent._fetchNext();
    if (!fetched) {
      return false;
    }
    _index = nextIndex;
    return true;
  }
}
```

원본 Iterable을 감싸고, 각 Iterator가 다음 원소를 요청할 때 캐시에 있으면 캐시를 반환하고, 없으면 원본에서 가져와 캐시에 추가한다. 여러 Iterator가 순회하더라도 콜백은 원소당 1회만 실행된다.

**설계 선택**:
- `sync*` 제너레이터 사용 금지: 명시적으로 `Iterator` 클래스를 구현한다.
- 원본은 처음 필요할 때 `_sourceIterator`를 초기화하고, 필요한 만큼만 앞으로 읽는다.
- 콜백 예외 시: 예외가 발생하면 캐시에 추가하지 않고, 다음 순회 시 다시 시도한다. 이는 테스트 "예외: 메모이즈는 예외 발생 시 캐시하지 않고 재시도"로 확인한다.

## 설계 비교

| 설계 | 콜백 호출 횟수 | 예외 시점 | 원본 변경 반영 | 메모리 사용 | 사용 사례 |
|------|--------------|----------|--------------|-----------|---------|
| A. 지연 Iterable | 순회마다 전체 재실행 | 소비 시점 | 반영됨 | 최소 (원본만) | 콜백이 저렴하고, 한 번만 순회하거나, 원본 변경을 반영해야 할 때 |
| B. 스냅샷(toList) | 1회 | toList 시점 | 반영 안 됨 (독립) | 전체 복사 | 원본과 독립적인 복사본이 필요하거나, 원본 변경으로부터 보호해야 할 때 |
| C. 메모이즈 | 원소당 1회 | 첫 소비 시점 | 캐시 고정 (반영 안 됨) | 점진적 증가 | 콜백이 비싸고 여러 번 순회하지만, 전체를 한 번에 평가하고 싶지 않을 때 |

## 헷갈리는 점

- **MappedListIterable 최적화**: `List.map`은 `MappedListIterable`을 반환한다. 이 클래스는 `length`와 `elementAt`을 원본 List의 길이와 인덱스로 직접 계산하므로 콜백을 실행하지 않는다. 반면 `Iterable.map`의 일반적인 경우는 `length`도 순회가 필요하다. 이 최적화는 Dart 구현 세부사항이므로 의존하지 말고, 테스트에서 실제 동작만 확인한다.

- **where는 길이를 모른다**: `Iterable.where`는 `WhereIterable`을 반환하고, `length`를 조회하면 전체를 순회해야 한다. `map` → `where` 체인에서 `length`를 두 번 호출하면 map 콜백이 원소 수의 2배만큼 실행된다.

- **지연 Iterable은 뷰다**: 원본 List에 `add`로 원소를 추가하면 지연 Iterable의 다음 순회는 추가된 원소를 포함한다. 스냅샷과 메모이즈는 원본 변경을 반영하지 않는다.

- **순회 중 원본 변경**: 지연 Iterable을 `for-in`으로 순회하는 중에 원본 List를 변경하면 `ConcurrentModificationError`가 발생한다. 이는 Dart의 일관성 보장 메커니즘이다. 순회 중 원본을 변경해야 한다면 먼저 `toList()`로 복사하거나, 인덱스 기반 루프를 사용한다.

- **메모이즈는 원본을 한 번만 순회한다**: `MemoizedIterable`은 원본 Iterator를 처음 `moveNext` 호출 시 생성하고, 이후 모든 Iterator가 이를 공유한다. 원본은 필요할 때만 필요한 만큼 앞으로 읽으므로, `first` 호출은 원소 1개만 가져온다.

- **메모이즈 예외 정책**: 콜백에서 예외가 발생하면 캐시에 추가하지 않고, 다음 순회 시 다시 시도한다. 이 예제에서 테스트하는 `[1,0,2].map((x)=>10~/x)` 패턴은 원본이 List 기반 MappedListIterable이므로, 실패한 원소(두 번째, x=0) 위치에 머물러 재시도 시 같은 원소를 다시 평가하고 같은 예외를 던진다. 다른 원본 Iterator에서는 재시도 동작이 달라질 수 있다.

- **런타임 타입 이름**: `MappedListIterable<int, int>`, `WhereIterable<int>` 등은 Dart SDK 내부 클래스다. 런타임 타입을 단언하지 말고 참고용으로만 사용한다. 이 이름은 Dart 버전에 따라 바뀔 수 있다.

- **다루지 않는 것**: `Stream`, `Future`, 비동기, `sync*` 제너레이터, `List.unmodifiable`, 뷰 래퍼, Flutter 위젯은 범위 밖이다. 순수 Dart `dart:core`만 사용한다.

## 한계

- **단일 스레드**: 이 구현은 단일 스레드 환경을 가정한다. 멀티 스레드에서는 캐시 접근에 동기화가 필요하다.
- **원본 추가 변경 정책**: 메모이즈는 한 번 소비를 시작한 원본 Iterator를 끝까지 사용한다. 원본 List에 추가한 원소는 메모이즈가 이미 소진된 경우 반영되지 않는다.
- **메모리 누수 가능성**: `MemoizedIterable`은 한 번 평가한 원소를 계속 가지고 있으므로, 사용하지 않는 메모이즈 인스턴스는 가비지 컬렉션되지 않으면 메모리를 계속 차지한다.
- **예외 재시도는 원본 Iterator 타입에 따라 다름**: 이 구현은 예외를 캐시하지 않고 재시도한다. 테스트에서 확인한 List 기반 MappedListIterable은 실패한 원소 위치에 머물러 재시도 시 같은 예외를 던지지만, 다른 원본 Iterator(예: Stream 기반, 제너레이터)에서는 재시도 동작이 달라질 수 있다.
- **MappedListIterable 최적화는 Dart 구현 세부사항**: 이 최적화에 의존하는 코드는 Dart 버전이나 플랫폼에 따라 다르게 동작할 수 있다.

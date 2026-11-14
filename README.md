# Flutter Atelier

화면이랑 상태를 만져 본 코드를 남겨 둔다. 설명은 폴더 안 README에 있다.

## 목록

- [dart-required-named-default](packages/dart-required-named-default/README.md): Dart 명명된 매개변수에 required와 기본값을 함께 썼을 때 누락 호출의 컴파일 결과와 기본값 적용 방식을 코드로 확인한다.
- [dart-factory-instance-cache](packages/dart-factory-instance-cache/README.md): factory 생성자와 private _internal 생성자로 키별 인스턴스 캐시를 만들고, 같은 키 호출이 identical로 같은 객체를 돌려주는지 확인한다.
- [mixin-on-constraint-class-hierarchy](packages/mixin-on-constraint-class-hierarchy/README.md): Dart mixin의 on 제약으로 State 서브클래스에만 mixin을 적용하고, 조건을 어기는 클래스에서 컴파일 오류가 나는지 확인한다.
- [riverpod-family-same-args-identical](packages/riverpod-family-same-args-identical/README.md): Riverpod 3 family provider에 같은 인자를 두 번 넘겼을 때 두 watch가 같은 인스턴스를 공유하는지 identical로 확인한다.
- [stream-error-cancel-on-error-ondone](packages/stream-error-cancel-on-error-ondone/README.md): StreamSubscription에서 cancelOnError 옵션에 따른 에러 이벤트 처리와 구독 취소 순서, handleError 필터링, close 후 add/addError의 StateError를 실행으로 검증한다.
- [late-final-initializer-retry-reentrancy](packages/late-final-initializer-retry-reentrancy/README.md): Dart late final 필드와 최상위 final 지연 초기화의 실패·재진입·순환 동작을 검증하고, 실패 시 재시도 정책을 명시적으로 가진 캐시 설계와 비교한다.

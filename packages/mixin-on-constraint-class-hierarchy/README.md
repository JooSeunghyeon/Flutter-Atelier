# mixin on 제약으로 클래스 계층 한정하기

`on` 키워드가 붙은 mixin은 자신을 적용할 수 있는 상위 타입을 제한한다. 이 예제는 `State<StatefulWidget>` 서브클래스에만 mixin을 적용하고, 조건을 어기는 클래스에서 어떤 컴파일 오류가 나는지 본다.

## 확인 방법

1. `src/main.dart`의 `StateLogMixin`은 `on State<StatefulWidget>`으로 선언된다.
2. `CounterState`는 `State<CounterPage>`를 상속하고 mixin을 적용한다.
3. `BadHelper`에 주석을 해제하면 `on` 제약을 만족하지 않아 컴파일 오류가 발생한다.

실행 결과는 직접 `dart analyze`로 확인한다.

# factory 생성자로 키별 인스턴스 캐시 확인하기

같은 키로 factory 생성자를 두 번 호출했을 때 새 객체가 만들어지는지, 캐시된 객체가 돌아오는지 `identical`로 확인한다.

- `_internal` private 생성자는 외부에서 직접 인스턴스를 만들지 못하게 막는다.
- `factory`는 정적 `Map<String, Connection>`을 먼저 조회하고, 없을 때만 생성해서 저장한다.
- 빈 문자열 키는 `ArgumentError`를 던져 실패 경로도 함께 확인한다.

실행은 `dart run src/main.dart`로 한다. 실행 결과는 코드에서 출력하는 문장만 보면 된다.

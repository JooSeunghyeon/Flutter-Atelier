# StreamSubscription 에러 처리와 구독 취소 순서 확인

StreamSubscription에서 에러 이벤트가 발생한 뒤 무엇이 계속되고 무엇이 끝나는지 실행으로 검증한다.

## 검증하는 질문

1. **cancelOnError: false (기본)**: 에러 후에도 data 이벤트를 계속 받고 onDone이 호출되는가?
2. **cancelOnError: true**: 첫 에러 후 구독이 취소되어 이후 data와 onDone이 오지 않는가? StreamController.onCancel은 호출되는가?
3. **await for**: 에러가 루프 밖으로 throw되고 구독이 취소(onCancel)되며 finally가 실행되는가?
4. **handleError**: 특정 에러만 복구하고 스트림을 이어가는 경우와 test 조건에 맞지 않는 에러가 그대로 전달되는 경우
5. **경계**: close() 이후 add/addError 호출 시 StateError가 발생하는가?

각 시나리오는 이벤트 순서를 기록하는 로그 기반으로 예상과 일치하는지 비교한다.

## 실행 방법

```bash
dart run src/main.dart
```

모든 시나리오가 통과하면 `ALL_CHECKS_PASSED`를 출력하고 exit code 0으로 종료한다.  
하나라도 실패하면 실패 내용을 출력하고 exit code 1로 종료한다.

## 관찰 결과

### cancelOnError: false (기본)
- 에러 이벤트가 onError로 전달된다
- 에러 이후에도 data 이벤트를 계속 받는다
- 스트림이 close되면 onDone이 호출된다
- onCancel은 호출되지 않는다 (정상 완료)

### cancelOnError: true
- 첫 에러가 onError로 전달된다
- 구독이 즉시 취소된다
- 이후 data 이벤트는 수신되지 않는다
- onDone은 호출되지 않는다
- StreamController.onCancel이 호출된다

### await for
- 에러가 루프 밖으로 throw된다
- 구독이 자동으로 취소된다
- StreamController.onCancel이 호출된다
- finally 블록이 실행된다

### handleError
- test 조건을 만족하는 에러는 복구되어 스트림이 계속된다
- test 조건을 만족하지 않는 에러는 그대로 전달되어 onError로 간다
- handleError는 에러를 "제거"하거나 "통과"시키는 필터 역할

### close() 후 add/addError
- close() 후 add를 호출하면 StateError가 발생한다
- close() 후 addError를 호출해도 StateError가 발생한다
- 닫힌 스트림은 새로운 이벤트를 추가할 수 없다

## 헷갈리는 점

- **cancelOnError 기본값은 false**: 에러가 발생해도 구독이 계속된다. 많은 경우 이것이 원하는 동작이 아닐 수 있다.
- **await for는 자동 cancelOnError: true**: 첫 에러에서 루프가 중단되고 예외가 throw된다.
- **handleError는 test가 true일 때만 복구**: test를 제공하지 않으면 모든 에러를 복구한다.
- **onCancel vs onDone**: onCancel은 구독 취소 시, onDone은 정상 완료 시 호출된다. 둘 다 호출되지 않는 경우도 있다.

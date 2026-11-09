# StreamSubscription 에러 처리와 구독 취소 순서 확인

StreamSubscription에서 에러 이벤트가 발생한 뒤 무엇이 계속되고 무엇이 끝나는지, 이벤트 순서를 포함하여 실행으로 검증한다.

## 검증하는 질문

1. **cancelOnError: false (기본)**: 에러 후에도 data 이벤트를 계속 받고 onDone이 호출되는가? onCancel과 onDone의 순서는?
2. **cancelOnError: true**: 첫 에러 후 구독이 취소되어 이후 data와 onDone이 오지 않는가? onCancel과 onError 콜백의 순서는?
3. **await for**: 에러가 루프 밖으로 throw되고 구독이 취소(onCancel)되며 finally가 실행되는가? onCancel과 catch의 순서는?
4. **handleError**: 특정 에러만 복구하고 스트림을 이어가는 경우와 test 조건에 맞지 않는 에러가 그대로 전달되는 경우
5. **경계**: close() 이후 add/addError 호출 시 StateError가 발생하는가?

각 시나리오는 이벤트 순서를 기록하는 로그를 기대 순서와 완전히 일치하는지 비교한다.

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
- 스트림이 close되면 **onCancel이 먼저 호출되고 그 다음 onDone이 호출된다**
- 이벤트 순서: `data:1, error:에러1, data:2, error:에러2, data:3, onCancel, onDone`

### cancelOnError: true
- 첫 에러가 발생하면 **onCancel이 먼저 호출되고 그 다음 onError 콜백이 실행된다**
- 구독이 즉시 취소된다
- 이후 data 이벤트는 수신되지 않는다
- onDone은 호출되지 않는다
- 이벤트 순서: `data:1, onCancel, error:에러1`

### await for
- 에러가 발생하면 **onCancel이 먼저 호출되고 그 다음 catch 블록이 실행된다**
- 구독이 자동으로 취소된다
- 에러가 루프 밖으로 throw된다
- finally 블록이 실행된다
- 이벤트 순서: `data:1, onCancel, catch:에러1, finally`

### handleError
- test 조건을 만족하는 에러는 handleError 핸들러로 복구되어 스트림이 계속된다
- test 조건을 만족하지 않는 에러는 그대로 listen의 onError로 전달된다
- handleError는 에러를 "제거"하거나 "통과"시키는 필터 역할
- 복구된 에러든 통과된 에러든 모두 이후 data 이벤트는 계속 수신된다 (cancelOnError: false 기본)
- 이벤트 순서: `data:1, handled:복구가능, data:2, error:복구불가, data:3, onDone`

### close() 후 add/addError
- close() 후 add를 호출하면 StateError가 발생한다
- close() 후 addError를 호출해도 StateError가 발생한다
- 닫힌 스트림은 새로운 이벤트를 추가할 수 없다

## 헷갈리는 점

- **cancelOnError 기본값은 false**: 에러가 발생해도 구독이 계속된다. 많은 경우 이것이 원하는 동작이 아닐 수 있다.
- **await for는 자동 cancelOnError: true**: 첫 에러에서 루프가 중단되고 예외가 throw된다.
- **handleError는 test가 true일 때만 복구**: test를 제공하지 않으면 모든 에러를 복구한다.
- **onCancel은 onDone보다 먼저 호출된다**: 정상 완료(cancelOnError: false)에서도 onCancel이 먼저 실행되고 onDone이 나중에 실행된다.
- **onCancel은 onError보다 먼저 호출된다**: 에러로 인한 취소(cancelOnError: true)에서 onCancel이 먼저 실행되고 onError 콜백이 나중에 실행된다.
- **onCancel은 catch보다 먼저 호출된다**: await for에서 에러 발생 시 onCancel이 먼저 실행되고 catch 블록이 나중에 실행된다.
- **onCancel과 onDone은 배타적이지 않다**: cancelOnError: false에서 정상 완료하면 둘 다 호출되며, onCancel → onDone 순서로 실행된다.

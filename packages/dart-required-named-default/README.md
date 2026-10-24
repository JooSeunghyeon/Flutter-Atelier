# Dart required 명명된 매개변수와 기본값

이 폴더는 Dart의 명명된 매개변수에 required를 붙였을 때 누락 호출이 어떻게 처리되는지, 그리고 기본값과 함께 쓸 때 어떤 값이 들어가는지 코드로 확인한다.

실행 대상은 src/required_named_params.dart 한 파일이다. 주석으로 표시된 누락 호출 줄은 컴파일 에러가 나므로 주석을 풀면 dart analyze에서 에러를 확인할 수 있다.

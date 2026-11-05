# Riverpod 3 family provider 같은 인자 인스턴스 공유 확인

같은 인자로 family provider를 두 번 watch하면 같은 객체가 돌아오는지 identical로 확인한다.

- 같은 인자 두 번 호출: identical이 true인지 본다.
- 다른 인자 호출: 별도 인스턴스가 만들어지는지 본다.

실행 전 pubspec.yaml에 riverpod 3 의존성이 있어야 한다.

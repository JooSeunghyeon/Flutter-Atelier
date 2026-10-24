String buildGreeting({required String name, required String greeting}) {
  return '$greeting, $name';
}

String buildUser({required String name, int age = 20, String role = 'guest'}) {
  return '$name / $age / $role';
}

String buildMessage({required String text, String prefix = '[log]'}) {
  return '$prefix $text';
}

void main() {
  print(buildGreeting(name: 'Mina', greeting: 'Hello'));

  // 아래 줄의 주석을 풀면 greeting 누락으로 컴파일 에러가 난다.
  // print(buildGreeting(name: 'Mina'));

  print(buildUser(name: 'Jun'));
  print(buildUser(name: 'Jun', age: 30));
  print(buildUser(name: 'Jun', role: 'admin'));

  print(buildMessage(text: 'saved'));
  print(buildMessage(text: 'saved', prefix: '[info]'));
}

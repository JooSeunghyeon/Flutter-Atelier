import 'package:riverpod/riverpod.dart';

final greetingProvider = Provider.family<Object, String>((ref, name) {
  return Object();
});

void main() {
  final container = ProviderContainer();

  final a = container.read(greetingProvider('kim'));
  final b = container.read(greetingProvider('kim'));
  final c = container.read(greetingProvider('lee'));

  print('same args identical: ${identical(a, b)}');
  print('different args identical: ${identical(a, c)}');

  container.dispose();
}

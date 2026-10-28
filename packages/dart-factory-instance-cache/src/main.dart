class Connection {
  static final Map<String, Connection> _cache = {};

  final String key;

  Connection._internal(this.key);

  factory Connection(String key) {
    if (key.isEmpty) {
      throw ArgumentError('key는 비어 있을 수 없다');
    }
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    final created = Connection._internal(key);
    _cache[key] = created;
    return created;
  }

  static int get cacheSize => _cache.length;
}

void main() {
  final a = Connection('db-main');
  final b = Connection('db-main');
  final c = Connection('db-replica');

  print('a, b 같은 객체인가: ${identical(a, b)}');
  print('a, c 같은 객체인가: ${identical(a, c)}');
  print('캐시 개수: ${Connection.cacheSize}');

  try {
    Connection('');
  } on ArgumentError catch (e) {
    print('빈 키 실패: ${e.message}');
  }
  print('실패 후 캐시 개수: ${Connection.cacheSize}');
}

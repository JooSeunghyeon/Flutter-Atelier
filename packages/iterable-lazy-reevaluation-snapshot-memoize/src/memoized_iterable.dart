class MemoizedIterable<T> extends Iterable<T> {
  final Iterable<T> _source;
  final List<T> _cache = [];
  late final Iterator<T> _sourceIterator;
  bool _sourceExhausted = false;
  bool _iteratorInitialized = false;

  MemoizedIterable(this._source);

  @override
  Iterator<T> get iterator => _MemoizedIterator<T>(this);

  void _ensureIteratorInitialized() {
    if (!_iteratorInitialized) {
      _sourceIterator = _source.iterator;
      _iteratorInitialized = true;
    }
  }

  bool _fetchNext() {
    _ensureIteratorInitialized();
    if (_sourceExhausted) {
      return false;
    }
    final bool hasNext = _sourceIterator.moveNext();
    if (!hasNext) {
      _sourceExhausted = true;
      return false;
    }
    _cache.add(_sourceIterator.current);
    return true;
  }
}

class _MemoizedIterator<T> implements Iterator<T> {
  final MemoizedIterable<T> _parent;
  int _index = -1;

  _MemoizedIterator(this._parent);

  @override
  T get current {
    if (_index < 0 || _index >= _parent._cache.length) {
      throw StateError('No element');
    }
    return _parent._cache[_index];
  }

  @override
  bool moveNext() {
    final int nextIndex = _index + 1;
    if (nextIndex < _parent._cache.length) {
      _index = nextIndex;
      return true;
    }
    if (_parent._sourceExhausted) {
      return false;
    }
    final bool fetched = _parent._fetchNext();
    if (!fetched) {
      return false;
    }
    _index = nextIndex;
    return true;
  }
}

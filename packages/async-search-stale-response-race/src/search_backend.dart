import 'dart:async';

class SearchResult {
  SearchResult({required this.query, required this.items});

  final String query;
  final List<String> items;

  @override
  String toString() => 'SearchResult(query: "$query", items: $items)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SearchResult) {
      return false;
    }
    return query == other.query && _listEquals(items, other.items);
  }

  @override
  int get hashCode => Object.hash(query, Object.hashAll(items));

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class FakeSearchBackend {
  FakeSearchBackend();

  final Map<String, Completer<SearchResult>> _pendingRequests = {};
  int _requestCounter = 0;

  int get callCount => _requestCounter;

  Future<SearchResult> search(String query) {
    _requestCounter++;
    final Completer<SearchResult> completer = Completer<SearchResult>();
    _pendingRequests[query] = completer;
    return completer.future;
  }

  void completeRequest(String query, List<String> items) {
    final Completer<SearchResult>? completer = _pendingRequests[query];
    if (completer == null) {
      throw StateError('No pending request for query: $query');
    }
    if (completer.isCompleted) {
      throw StateError('Request for query "$query" is already completed');
    }
    completer.complete(SearchResult(query: query, items: items));
  }

  void failRequest(String query, Object error) {
    final Completer<SearchResult>? completer = _pendingRequests[query];
    if (completer == null) {
      throw StateError('No pending request for query: $query');
    }
    if (completer.isCompleted) {
      throw StateError('Request for query "$query" is already completed');
    }
    completer.completeError(error);
  }

  bool hasPendingRequest(String query) {
    final Completer<SearchResult>? completer = _pendingRequests[query];
    return completer != null && !completer.isCompleted;
  }

  void reset() {
    _pendingRequests.clear();
    _requestCounter = 0;
  }
}

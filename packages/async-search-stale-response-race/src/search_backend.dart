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

class _PendingRequest {
  _PendingRequest({
    required this.id,
    required this.query,
    required this.completer,
  });

  final int id;
  final String query;
  final Completer<SearchResult> completer;
}

class FakeSearchBackend {
  FakeSearchBackend();

  final List<_PendingRequest> _pendingRequests = [];
  int _nextRequestId = 0;

  int get callCount => _nextRequestId;

  Future<SearchResult> search(String query) {
    final int id = _nextRequestId++;
    final Completer<SearchResult> completer = Completer<SearchResult>();
    _pendingRequests.add(
      _PendingRequest(id: id, query: query, completer: completer),
    );
    return completer.future;
  }

  void completeRequestById(int id, List<String> items) {
    final _PendingRequest? request = _findRequestById(id);
    if (request == null) {
      throw StateError('No pending request with id: $id');
    }
    if (request.completer.isCompleted) {
      throw StateError('Request with id $id is already completed');
    }
    request.completer.complete(
      SearchResult(query: request.query, items: items),
    );
  }

  void failRequestById(int id, Object error) {
    final _PendingRequest? request = _findRequestById(id);
    if (request == null) {
      throw StateError('No pending request with id: $id');
    }
    if (request.completer.isCompleted) {
      throw StateError('Request with id $id is already completed');
    }
    request.completer.completeError(error);
  }

  void completeRequest(String query, List<String> items) {
    final _PendingRequest? request = _findNextPendingRequestForQuery(query);
    if (request == null) {
      throw StateError('No pending request for query: $query');
    }
    if (request.completer.isCompleted) {
      throw StateError('Request for query "$query" is already completed');
    }
    request.completer.complete(SearchResult(query: query, items: items));
  }

  void failRequest(String query, Object error) {
    final _PendingRequest? request = _findNextPendingRequestForQuery(query);
    if (request == null) {
      throw StateError('No pending request for query: $query');
    }
    if (request.completer.isCompleted) {
      throw StateError('Request for query "$query" is already completed');
    }
    request.completer.completeError(error);
  }

  bool hasPendingRequest(String query) {
    return _findNextPendingRequestForQuery(query) != null;
  }

  _PendingRequest? _findRequestById(int id) {
    for (final _PendingRequest request in _pendingRequests) {
      if (request.id == id && !request.completer.isCompleted) {
        return request;
      }
    }
    return null;
  }

  _PendingRequest? _findNextPendingRequestForQuery(String query) {
    for (final _PendingRequest request in _pendingRequests) {
      if (request.query == query && !request.completer.isCompleted) {
        return request;
      }
    }
    return null;
  }

  void reset() {
    _pendingRequests.clear();
    _nextRequestId = 0;
  }
}

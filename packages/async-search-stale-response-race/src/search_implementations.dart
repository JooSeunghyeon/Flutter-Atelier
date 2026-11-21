import 'dart:async';

import 'search_backend.dart';

abstract class SearchController {
  SearchController(this.backend);

  final FakeSearchBackend backend;
  SearchResult? _currentResults;
  Object? _currentError;

  SearchResult? get currentResults => _currentResults;
  Object? get currentError => _currentError;
  bool get hasError => _currentError != null;

  Future<void> search(String query);

  void dispose();
}

class NaiveSearch extends SearchController {
  NaiveSearch(super.backend);

  @override
  Future<void> search(String query) async {
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    try {
      final SearchResult result = await backend.search(query);
      _currentResults = result;
    } catch (error) {
      _currentError = error;
      _currentResults = null;
    }
  }

  @override
  void dispose() {}
}

class SequenceTokenSearch extends SearchController {
  SequenceTokenSearch(super.backend);

  int _requestId = 0;

  @override
  Future<void> search(String query) async {
    _requestId++;
    final int currentRequestId = _requestId;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    try {
      final SearchResult result = await backend.search(query);
      if (currentRequestId == _requestId) {
        _currentResults = result;
      }
    } catch (error) {
      if (currentRequestId == _requestId) {
        _currentError = error;
        _currentResults = null;
      }
    }
  }

  @override
  void dispose() {}
}

class SubscriptionCancelSearch extends SearchController {
  SubscriptionCancelSearch(super.backend);

  StreamSubscription<SearchResult>? _subscription;

  @override
  Future<void> search(String query) async {
    await _subscription?.cancel();
    _subscription = null;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Future<SearchResult> future = backend.search(query);
    _subscription = future.asStream().listen(
      (SearchResult result) {
        _currentResults = result;
      },
      onError: (Object error) {
        _currentError = error;
        _currentResults = null;
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

class DebounceSearch extends SearchController {
  DebounceSearch(super.backend, {required this.debounceDuration});

  final Duration debounceDuration;
  Timer? _debounceTimer;

  @override
  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _debounceTimer = Timer(debounceDuration, () async {
      try {
        final SearchResult result = await backend.search(query);
        _currentResults = result;
      } catch (error) {
        _currentError = error;
        _currentResults = null;
      }
      completer.complete();
    });
    return completer.future;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}

class DebounceWithSequenceTokenSearch extends SearchController {
  DebounceWithSequenceTokenSearch(
    super.backend, {
    required this.debounceDuration,
  });

  final Duration debounceDuration;
  Timer? _debounceTimer;
  int _requestId = 0;

  @override
  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    _requestId++;
    final int currentRequestId = _requestId;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _debounceTimer = Timer(debounceDuration, () async {
      try {
        final SearchResult result = await backend.search(query);
        if (currentRequestId == _requestId) {
          _currentResults = result;
        }
      } catch (error) {
        if (currentRequestId == _requestId) {
          _currentError = error;
          _currentResults = null;
        }
      }
      completer.complete();
    });
    return completer.future;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}

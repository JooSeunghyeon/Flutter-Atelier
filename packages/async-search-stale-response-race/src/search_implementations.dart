import 'dart:async';

import 'search_backend.dart';

abstract class SearchController {
  SearchController(this.backend);

  final FakeSearchBackend backend;
  SearchResult? _currentResults;
  Object? _currentError;
  bool _disposed = false;

  SearchResult? get currentResults => _currentResults;
  Object? get currentError => _currentError;
  bool get hasError => _currentError != null;
  bool get isDisposed => _disposed;

  Future<void> search(String query);

  void dispose() {
    _disposed = true;
  }
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
      if (!_disposed) {
        _currentResults = result;
      }
    } catch (error) {
      if (!_disposed) {
        _currentError = error;
        _currentResults = null;
      }
    }
  }
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
      if (!_disposed && currentRequestId == _requestId) {
        _currentResults = result;
      }
    } catch (error) {
      if (!_disposed && currentRequestId == _requestId) {
        _currentError = error;
        _currentResults = null;
      }
    }
  }
}

class SubscriptionCancelSearch extends SearchController {
  SubscriptionCancelSearch(super.backend);

  StreamSubscription<SearchResult>? _subscription;

  @override
  Future<void> search(String query) async {
    _subscription?.cancel();
    _subscription = null;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Future<SearchResult> future = backend.search(query);
    _subscription = future.asStream().listen(
      (SearchResult result) {
        if (!_disposed) {
          _currentResults = result;
        }
      },
      onError: (Object error) {
        if (!_disposed) {
          _currentError = error;
          _currentResults = null;
        }
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
    _subscription?.cancel();
    _subscription = null;
  }
}

class DebounceSearch extends SearchController {
  DebounceSearch(super.backend, {required this.debounceDuration});

  final Duration debounceDuration;
  Timer? _debounceTimer;
  Completer<void>? _currentCompleter;

  @override
  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
    }
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _currentCompleter = completer;
    _debounceTimer = Timer(debounceDuration, () async {
      try {
        final SearchResult result = await backend.search(query);
        if (!_disposed) {
          _currentResults = result;
        }
      } catch (error) {
        if (!_disposed) {
          _currentError = error;
          _currentResults = null;
        }
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    super.dispose();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
    }
    _currentCompleter = null;
  }
}

class DebounceWithSequenceTokenSearch extends SearchController {
  DebounceWithSequenceTokenSearch(
    super.backend, {
    required this.debounceDuration,
  });

  final Duration debounceDuration;
  Timer? _debounceTimer;
  Completer<void>? _currentCompleter;
  int _requestId = 0;

  @override
  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
    }
    _requestId++;
    final int currentRequestId = _requestId;
    _currentError = null;
    if (query.isEmpty) {
      _currentResults = null;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _currentCompleter = completer;
    _debounceTimer = Timer(debounceDuration, () async {
      try {
        final SearchResult result = await backend.search(query);
        if (!_disposed && currentRequestId == _requestId) {
          _currentResults = result;
        }
      } catch (error) {
        if (!_disposed && currentRequestId == _requestId) {
          _currentError = error;
          _currentResults = null;
        }
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    super.dispose();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
    }
    _currentCompleter = null;
  }
}

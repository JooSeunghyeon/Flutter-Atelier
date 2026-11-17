typedef VoidCallback = void Function();

abstract interface class ListenerNotifier {
  void addListener(VoidCallback listener);
  bool removeListener(VoidCallback listener);
  void notifyListeners();
  int get listenerCount;
}

class NaiveForInNotifier implements ListenerNotifier {
  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  bool removeListener(VoidCallback listener) {
    final int index = _listeners.indexOf(listener);
    if (index == -1) {
      return false;
    }
    _listeners.removeAt(index);
    return true;
  }

  @override
  void notifyListeners() {
    for (final VoidCallback listener in _listeners) {
      listener();
    }
  }

  @override
  int get listenerCount => _listeners.length;
}

class IndexLoopNotifier implements ListenerNotifier {
  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  bool removeListener(VoidCallback listener) {
    final int index = _listeners.indexOf(listener);
    if (index == -1) {
      return false;
    }
    _listeners.removeAt(index);
    return true;
  }

  @override
  void notifyListeners() {
    for (var i = 0; i < _listeners.length; i++) {
      _listeners[i]();
    }
  }

  @override
  int get listenerCount => _listeners.length;
}

class SnapshotNotifier implements ListenerNotifier {
  final List<VoidCallback> _listeners = [];
  int snapshotCopies = 0;
  int copiedElements = 0;

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  bool removeListener(VoidCallback listener) {
    final int index = _listeners.indexOf(listener);
    if (index == -1) {
      return false;
    }
    _listeners.removeAt(index);
    return true;
  }

  @override
  void notifyListeners() {
    final List<VoidCallback> snapshot = List.of(_listeners);
    snapshotCopies++;
    copiedElements += snapshot.length;
    for (final VoidCallback listener in snapshot) {
      listener();
    }
  }

  @override
  int get listenerCount => _listeners.length;
}

class DeferredRemovalNotifier implements ListenerNotifier {
  List<VoidCallback?> _listeners = [];
  int _notificationDepth = 0;
  int _removalsPending = 0;
  int compactions = 0;
  bool _disposed = false;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) {
      throw StateError('Cannot add listener after dispose');
    }
    _listeners.add(listener);
  }

  @override
  bool removeListener(VoidCallback listener) {
    for (int i = 0; i < _listeners.length; i++) {
      if (_listeners[i] == listener) {
        if (_notificationDepth > 0) {
          _listeners[i] = null;
          _removalsPending++;
        } else {
          _listeners.removeAt(i);
        }
        return true;
      }
    }
    return false;
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      throw StateError('Cannot notify listeners after dispose');
    }
    if (_listeners.isEmpty) {
      return;
    }
    _notificationDepth++;
    final int lengthAtStart = _listeners.length;
    final List<Object> errors = [];
    try {
      for (int i = 0; i < lengthAtStart; i++) {
        final VoidCallback? listener = _listeners[i];
        if (listener != null) {
          try {
            listener();
          } catch (error) {
            errors.add(error);
          }
        }
      }
    } finally {
      _notificationDepth--;
      if (_notificationDepth == 0 && _removalsPending > 0) {
        _compactListeners();
      }
    }
    if (errors.isNotEmpty) {
      throw errors.first;
    }
  }

  void _compactListeners() {
    _listeners = _listeners.where((VoidCallback? listener) => listener != null).cast<VoidCallback?>().toList();
    _removalsPending = 0;
    compactions++;
  }

  @override
  int get listenerCount {
    int count = 0;
    for (final VoidCallback? listener in _listeners) {
      if (listener != null) {
        count++;
      }
    }
    return count;
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

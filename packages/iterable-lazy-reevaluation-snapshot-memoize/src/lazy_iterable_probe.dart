class CallCounter {
  int count = 0;

  int Function(int) wrap(int Function(int) fn) {
    return (int x) {
      count++;
      return fn(x);
    };
  }

  void reset() {
    count = 0;
  }
}

import 'dart:collection';

/// A high-performance, fixed-capacity circular ring buffer.
///
/// Designed for zero-allocation recording in latency-critical UI loops.
/// Enqueue operates in O(1) with zero array-reallocation once initialized.
/// When capacity is reached, new entries overwrite the oldest entries.
class EventRingBuffer<T> with IterableMixin<T> {
  final int capacity;
  final List<T?> _buffer;
  int _head = 0; // Next write index
  int _tail = 0; // Oldest read index
  int _count = 0;

  EventRingBuffer(this.capacity)
      : assert(capacity > 0, 'Capacity must be greater than zero'),
        _buffer = List<T?>.filled(capacity, null, growable: false);

  /// Number of active items stored in the buffer.
  @override
  int get length => _count;

  /// Returns true if the ring buffer contains no elements.
  @override
  bool get isEmpty => _count == 0;

  /// Returns true if the ring buffer has reached its fixed capacity.
  bool get isFull => _count == capacity;

  /// Adds an item to the buffer in O(1) time.
  /// If the buffer is full, overwrites the oldest item.
  void add(T item) {
    _buffer[_head] = item;
    _head = (_head + 1) % capacity;

    if (_count < capacity) {
      _count++;
    } else {
      // Overwrote the oldest item, advance tail
      _tail = (_tail + 1) % capacity;
    }
  }

  /// Appends all elements from [iterable].
  void addAll(Iterable<T> iterable) {
    for (final item in iterable) {
      add(item);
    }
  }

  /// Clears the ring buffer.
  void clear() {
    _buffer.fillRange(0, capacity, null);
    _head = 0;
    _tail = 0;
    _count = 0;
  }

  /// Returns an ordered list from oldest to newest event.
  @override
  List<T> toList({bool growable = true}) {
    final list = List<T>.generate(_count, (i) {
      final index = (_tail + i) % capacity;
      return _buffer[index] as T;
    }, growable: growable);
    return list;
  }

  /// Iterates from the oldest entry to the newest entry.
  @override
  Iterator<T> get iterator => _RingBufferIterator(this);
}

class _RingBufferIterator<T> implements Iterator<T> {
  final EventRingBuffer<T> _buffer;
  int _index = -1;
  T? _current;

  _RingBufferIterator(this._buffer);

  @override
  T get current {
    if (_current == null) {
      throw StateError('No current element');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    if (_index + 1 < _buffer._count) {
      _index++;
      final actualIndex = (_buffer._tail + _index) % _buffer.capacity;
      _current = _buffer._buffer[actualIndex];
      return true;
    }
    _current = null;
    return false;
  }
}

import 'dart:collection';

/// LinkedHashMap LRU 辅助：把刚访问的条目移到末尾（最新）。
extension LinkedHashMapMoveFirst<K, V> on LinkedHashMap<K, V> {
  void setEntryFirst(K key, V value) {
    // LinkedHashMap 迭代顺序为插入序；删除后重新插入即移到末尾（最新）。
    remove(key);
    this[key] = value;
  }
}

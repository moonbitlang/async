// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// HPACK dynamic table implemented as a ring buffer.
/// New entries are added at the front (head), old entries are evicted from the back.
priv struct DynamicTable {
  mut entries : Array[(String, String)]
  mut head : Int
  mut len : Int
  mut size : Int
  mut max_size : Int
}

///|
/// Calculate the size of a header entry per RFC 7541 Section 4.1.
/// Size = 32 + length of name + length of value.
fn entry_size(name : String, value : String) -> Int {
  32 + name.length() + value.length()
}

///|
/// Create a new dynamic table with the given maximum size.
fn DynamicTable::new(max_size? : Int = 4096) -> DynamicTable {
  let capacity = 64
  {
    entries: Array::make(capacity, ("", "")),
    head: 0,
    len: 0,
    size: 0,
    max_size,
  }
}

///|
/// Evict entries from the back of the table until size <= max_size.
fn DynamicTable::evict(self : DynamicTable) -> Unit {
  while self.size > self.max_size && self.len > 0 {
    // The oldest entry is at index (head + len - 1) % capacity
    let capacity = self.entries.length()
    let tail = (self.head + self.len - 1) % capacity
    let (name, value) = self.entries[tail]
    self.size = self.size - entry_size(name, value)
    self.entries[tail] = ("", "")
    self.len = self.len - 1
  }
}

///|
/// Add a new entry at the front of the dynamic table.
/// Evicts entries from the back if the table would exceed max_size.
fn DynamicTable::add(
  self : DynamicTable,
  name : String,
  value : String,
) -> Unit {
  let es = entry_size(name, value)
  // If the entry itself is larger than max_size, clear the table
  if es > self.max_size {
    self.len = 0
    self.size = 0
    self.head = 0
    return
  }
  // Evict until there's room
  self.size = self.size + es
  self.evict()
  // Grow the backing array if needed
  if self.len >= self.entries.length() {
    let old_cap = self.entries.length()
    let new_cap = old_cap * 2
    let new_entries : Array[(String, String)] = Array::make(new_cap, ("", ""))
    for i = 0; i < self.len; i = i + 1 {
      new_entries[i] = self.entries[(self.head + i) % old_cap]
    }
    self.entries = new_entries
    self.head = 0
  }
  // Insert at front: move head back by 1
  let capacity = self.entries.length()
  self.head = (self.head - 1 + capacity) % capacity
  self.entries[self.head] = (name, value)
  self.len = self.len + 1
}

///|
/// Get an entry from the dynamic table by 0-based index.
/// Index 0 is the newest entry.
fn DynamicTable::get(self : DynamicTable, index : Int) -> (String, String)? {
  if index < 0 || index >= self.len {
    return None
  }
  let capacity = self.entries.length()
  let actual = (self.head + index) % capacity
  Some(self.entries[actual])
}

///|
/// Set a new maximum size for the dynamic table, evicting entries as needed.
fn DynamicTable::set_max_size(self : DynamicTable, new_max : Int) -> Unit {
  self.max_size = new_max
  self.evict()
}

///|
/// Return the number of entries in the dynamic table.
fn DynamicTable::length(self : DynamicTable) -> Int {
  self.len
}

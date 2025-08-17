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
pub(open) trait Writer {
  async write_once(Self, Bytes, offset~ : Int, len~ : Int) -> Int raise
  async write(Self, @bytes.View) -> Unit raise = _
  async write_reader(Self, &Reader) -> Unit raise = _
}

///|
impl Writer with write(self, view) {
  let start = view.start_offset()
  let len = view.length()
  let end = start + len
  let offset = self.write_once(view.data(), offset=start, len~)
  if offset == end {
    return
  }
  @async.protect_from_cancel(fn() {
    for offset = start; offset < end; {
      let progress = self.write_once(view.data(), offset~, len=end - offset)
      continue offset + progress
    }
  })
}

///|
impl Writer with write_reader(self, reader) {
  let buf = FixedArray::make(1024, b'0')
  while reader.read(buf, offset=0, max_len=1024) is n && n > 0 {
    for offset = 0; offset < n; {
      let progress = self.write_once(
        buf.unsafe_reinterpret_as_bytes(),
        offset~,
        len=n - offset,
      )
      continue offset + progress
    }
  }
}

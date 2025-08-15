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
/// `conn.recv_exactly(n)` receives exactly `n` bytes of data from a TCP connection.
/// `recv_exactly` will only return after all `n` bytes of data are received.
/// If the connection is closed before receiving all data, an error is raised.
///
/// At most one task can read from a TCP socket at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
#deprecated("use `read_exactly` instead")
pub async fn TCP::recv_exactly(self : TCP, len : Int) -> Bytes raise {
  @io.Reader::read_exactly(self, len)
}

///|
/// Send data through a TCP connection.
/// This function will only return after all data have been successfully sent.
///
/// At most one task can write to a TCP socket at any time.
/// To allow multiple writers,
/// use a worker task for writing and use `@async.Queue` to gather data.
#deprecated("use `write` instead")
pub async fn TCP::send(self : TCP, data : @bytes.View) -> Unit raise {
  @io.Writer::write(self, data)
}

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
/// Manual tests for HTTP proxy functionality
///
/// These tests require a local HTTP proxy running at 127.0.0.1:7890
///

// ///|
// async test "access youtube.com through proxy with Proxy::all" {
//   let proxy = Proxy::all("127.0.0.1", port=7890)
//   let (response, body) = @http.get("https://www.youtube.com", proxy~)
//   inspect(response.code, content="200")
//   let text = body.text()
//   assert_true(text.contains("YouTube"))
// }

// ///|
// async test "access youtube.com through proxy with Proxy::https" {
//   let proxy = Proxy::https("127.0.0.1", port=7890)
//   let (response, body) = @http.get("https://www.youtube.com", proxy~)
//   inspect(response.code, content="200")
//   let text = body.text()
//   assert_true(text.contains("YouTube"))
// }

// ///|
// async test "access youtube.com with Client through proxy" {
//   let proxy = Proxy::all("127.0.0.1", port=7890)
//   let client = Client::connect("www.youtube.com", protocol=Https, proxy~)
//   defer client.close()
//   let response = client..request(Get, "/").end_request()
//   inspect(response.code, content="200")
//   let body = client.read_all()
//   let text = body.text()
//   assert_true(text.contains("YouTube"))
// }

// ///|
// async test "multiple requests through proxy" {
//   let proxy = Proxy::all("127.0.0.1", port=7890)
//
//   let (response1, body1) = @http.get("https://www.youtube.com", proxy~)
//   inspect(response1.code, content="200")
//   assert_true(body1.text().contains("YouTube"))
//
//   let (response2, body2) = @http.get("https://www.youtube.com", proxy~)
//   inspect(response2.code, content="200")
//   assert_true(body2.text().contains("YouTube"))
// }

// ///|
// async test "access youtube.com with custom proxy" {
//   let proxy = Proxy::custom(
//     "127.0.0.1",
//     http_port=7890,
//     "127.0.0.1",
//     https_port=7890,
//   )
//
//   let (response, body) = @http.get("https://www.youtube.com", proxy~)
//   inspect(response.code, content="200")
//   assert_true(body.text().contains("YouTube"))
// }

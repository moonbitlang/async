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
/// WebSocket client example - Autobahn Test Suite Client
/// 
/// This implements the Autobahn test suite client logic:
/// 1. Get case count
/// 2. Run each test case (echo all messages)
/// 3. Update reports
async fn main {
  run_autobahn_tests()
}

///|
/// Run Autobahn WebSocket test suite
pub async fn run_autobahn_tests() -> Unit {
  let host = @sys.get_env_vars()
    .get("WS_TEST_HOST")
    .unwrap_or("127.0.0.1".to_string())
  let port = 9001
  let agent = "moonbit-async-websocket"

  // Step 1: Get case count
  @stdio.stdout.write("Getting case count from \{host}:\{port}...\n")
  let case_count = get_case_count(host, port)
  @stdio.stdout.write("Ok, will run \{case_count} cases\n\n")

  // Step 2: Run each test case
  for case_id = 1; case_id <= case_count; case_id = case_id + 1 {
    @stdio.stdout.write(
      "Running test case \{case_id}/\{case_count} as user agent \{agent}\n",
    )
    run_test_case(host, port, case_id, agent)
  }

  // Step 3: Update reports
  @stdio.stdout.write("\nUpdating reports...\n")
  update_reports(host, port, agent)
  @stdio.stdout.write("All tests completed!\n")
}

///|
/// Get the total number of test cases
async fn get_case_count(host : String, port : Int) -> Int {
  let client = @websocket.connect("ws://\{host}:\{port}/getCaseCount")
  defer client.close()
  let message = client.recv()
  match message.kind {
    Text => {
      let count_str = message.read_all().text()
      @strconv.parse_int(count_str)
    }
    Binary => {
      @stdio.stdout.write("Error: Expected text message with case count\n")
      0
    }
  }
}

///|
/// Run a single test case - echo all messages back to server
async fn run_test_case(
  host : String,
  port : Int,
  case_id : Int,
  agent : String,
) -> Unit {
  let client = @websocket.connect(
    "ws://\{host}:\{port}/runCase?case=\{case_id}&agent=\{agent}",
  )
  for {
    let message = client.recv() catch {
      @websocket.ConnectionClosed(_, _) =>
        // Test case completed
        break
      err => {
        @stdio.stdout.write("Error in case \{case_id}: \{err}\n")
        break
      }
    }
    // Echo the message back (core test logic)
    client..start_message(message.kind)..write_reader(message)..end_message()
  }
  client.close()
}

///|
/// Update test reports on the server
async fn update_reports(host : String, port : Int, agent : String) -> Unit {
  let client = @websocket.connect(
    "ws://\{host}:\{port}/updateReports?agent=\{agent}",
  )
  defer client.close()
  // Wait for server to close the connection
  try client.recv() catch {
    @websocket.ConnectionClosed(_, _) => ()
    err => raise err
  } noraise {
    _ => ()
  }
}

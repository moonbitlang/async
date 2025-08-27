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
/// Connect to a remote host using the happy eyeball algorithm.
pub async fn TCP::connect_to_host(host : Bytes, port~ : Int) -> TCP raise {
  let info = @ref.new(AddrInfo::null())
  let ret = @event_loop.perform_job(GetAddrInfo(host~, out=info))
  if ret > 0 {
    raise ResolveHostnameError(ret)
  }
  let mut result = None
  let mut conn_err = None
  @async.with_task_group(fn(group) {
    for ai = info.val; not(ai.is_null()); ai = ai.next() {
      group.spawn_bg(allow_failure=true, fn() {
        let conn = TCP::connect(Addr::new(ai.ip(), port)) catch {
          err => {
            if conn_err is None {
              conn_err = Some(err)
            }
            raise err
          }
        }
        result = Some(conn)
        group.return_immediately(())
      })
      @async.sleep(250)
    }
  })
  match result {
    Some(conn) => conn
    None => raise conn_err.unwrap()
  }
}

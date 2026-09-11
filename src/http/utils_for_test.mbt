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
#cfg(any(target="native", target="wasm"))
async fn non_responding_tcp_server(group : @async.TaskGroup[Unit]) -> Int {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  group.add_defer(() => server.close())
  server.addr.port()
}

///|
#cfg(target="js")
#external
type TcpServer

///|
#cfg(target="js")
extern "js" fn TcpServer::create() -> @js_async.Promise[TcpServer] =
  #| () => {
  #|   const net = require('node:net')
  #|   const server = net.createServer({})
  #|   server.listen(0, "127.0.0.1")
  #|   return new Promise((resolve) => {
  #|     server.on('listening', () => resolve(server))
  #|   })
  #| }

///|
#cfg(target="js")
extern "js" fn TcpServer::close(server : TcpServer) =
  #| (server) => server.close()

///|
#cfg(target="js")
extern "js" fn TcpServer::port(server : TcpServer) -> Int =
  #| (server) => server.address().port

///|
#cfg(target="js")
async fn non_responding_tcp_server(group : @async.TaskGroup[Unit]) -> Int {
  let server = TcpServer::create().wait()
  group.add_defer(() => server.close())
  server.port()
}

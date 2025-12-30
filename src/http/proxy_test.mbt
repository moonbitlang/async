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
async test "passthrough mode" {
  let log = []
  @async.with_task_group(group => {
    let server = @socket.TcpServer::new(@socket.Addr::parse("127.0.0.1:0"))
    let server_addr = server.addr()
    group.spawn_bg(() => {
      defer server.close()
      let (conn, _) = server.accept()
      let conn = @http.ServerConnection::new(conn)
      defer conn.close()
      let request = conn.read_request()
      inspect(request.meth, content="Connect")
      inspect(request.path, content="/path")
      conn..send_response(200, "OK")..end_response()
      conn.enter_passthrough_mode()
      while conn.read_some() is Some(packet) {
        let packet = @encoding/utf8.decode(packet)
        log.push("server received: \{packet}")
      }
    })
    let client = @http.Client::new("http://localhost:\{server_addr.port()}")
    defer client.close()
    let response = client..request(Connect, "/path").end_request()
    inspect(response.code, content="200")
    client.enter_passthrough_mode()
    for packet in ["abcd", "efgh", "ijkl"] {
      log.push("client sending: \{packet}")
      client.write(packet)
      @async.sleep(200)
    }
  })
  @json.inspect(log, content=[
    "client sending: abcd", "server received: abcd", "client sending: efgh", "server received: efgh",
    "client sending: ijkl", "server received: ijkl",
  ])
}

///|
async test "passthrough mode remaining data" {
  @async.with_task_group(group => {
    let server = @socket.TcpServer::new(@socket.Addr::parse("127.0.0.1:0"))
    let server_addr = server.addr()
    group.spawn_bg(() => {
      defer server.close()
      let (conn, _) = server.accept()
      let conn = @http.ServerConnection::new(conn)
      defer conn.close()
      let request = conn.read_request()
      inspect(request.meth, content="Get")
      inspect(request.path, content="/")
      conn.enter_passthrough_mode()
      inspect(conn.read_all().text(), content="remaining data")
    })
    let client = @socket.Tcp::connect(
      @socket.Addr::parse("127.0.0.1:\{server_addr.port()}"),
    )
    defer client.close()
    client.write("GET / HTTP/1.1\r\n\r\nremaining data")
  })
}

///|
async fn handle_connect(
  log : Array[String],
  request : @http.Request,
  _body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  guard request.meth is Connect else {
    conn..send_response(400, "BadRequest")..end_response()
    return
  }
  guard request.path.rev_find(":") is Some(index) else {
    conn..send_response(400, "BadRequest")..end_response()
    return
  }
  let client = try {
    let host = request.path[:index].to_string()
    let port = @strconv.parse_int(request.path[index + 1:])
    @socket.Tcp::connect_to_host(host, port~)
  } catch {
    err => {
      conn..send_response(502, "BadGateway")..end_response()
      raise err
    }
  }
  defer client.close()
  log.push("proxy server: connected to \{request.path} successfully")
  conn..send_response(200, "OK")..end_response()
  conn.enter_passthrough_mode()
  @async.with_task_group(group => {
    group.spawn_bg(() => conn.write_reader(client))
    group.spawn_bg(() => client.write_reader(conn))
  })
}

///|
async test "proxied https request" {
  let log = []
  @async.with_task_group(group => {
    let server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr().port()
    group.spawn_bg(no_wait=true, () => server.run_forever(
      handle_connect(log, _, _, _),
    ))
    let (_, result) = @http.get(
      "https://raw.githubusercontent.com/moonbitlang/async/refs/heads/main/LICENSE",
      proxy=@http.Client::new("http://localhost:\{port}"),
    )
    inspect(
      result.text(),
      content=(
        #|
        #|                                 Apache License
        #|                           Version 2.0, January 2004
        #|                        http://www.apache.org/licenses/
        #|
        #|   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION
        #|
        #|   1. Definitions.
        #|
        #|      "License" shall mean the terms and conditions for use, reproduction,
        #|      and distribution as defined by Sections 1 through 9 of this document.
        #|
        #|      "Licensor" shall mean the copyright owner or entity authorized by
        #|      the copyright owner that is granting the License.
        #|
        #|      "Legal Entity" shall mean the union of the acting entity and all
        #|      other entities that control, are controlled by, or are under common
        #|      control with that entity. For the purposes of this definition,
        #|      "control" means (i) the power, direct or indirect, to cause the
        #|      direction or management of such entity, whether by contract or
        #|      otherwise, or (ii) ownership of fifty percent (50%) or more of the
        #|      outstanding shares, or (iii) beneficial ownership of such entity.
        #|
        #|      "You" (or "Your") shall mean an individual or Legal Entity
        #|      exercising permissions granted by this License.
        #|
        #|      "Source" form shall mean the preferred form for making modifications,
        #|      including but not limited to software source code, documentation
        #|      source, and configuration files.
        #|
        #|      "Object" form shall mean any form resulting from mechanical
        #|      transformation or translation of a Source form, including but
        #|      not limited to compiled object code, generated documentation,
        #|      and conversions to other media types.
        #|
        #|      "Work" shall mean the work of authorship, whether in Source or
        #|      Object form, made available under the License, as indicated by a
        #|      copyright notice that is included in or attached to the work
        #|      (an example is provided in the Appendix below).
        #|
        #|      "Derivative Works" shall mean any work, whether in Source or Object
        #|      form, that is based on (or derived from) the Work and for which the
        #|      editorial revisions, annotations, elaborations, or other modifications
        #|      represent, as a whole, an original work of authorship. For the purposes
        #|      of this License, Derivative Works shall not include works that remain
        #|      separable from, or merely link (or bind by name) to the interfaces of,
        #|      the Work and Derivative Works thereof.
        #|
        #|      "Contribution" shall mean any work of authorship, including
        #|      the original version of the Work and any modifications or additions
        #|      to that Work or Derivative Works thereof, that is intentionally
        #|      submitted to Licensor for inclusion in the Work by the copyright owner
        #|      or by an individual or Legal Entity authorized to submit on behalf of
        #|      the copyright owner. For the purposes of this definition, "submitted"
        #|      means any form of electronic, verbal, or written communication sent
        #|      to the Licensor or its representatives, including but not limited to
        #|      communication on electronic mailing lists, source code control systems,
        #|      and issue tracking systems that are managed by, or on behalf of, the
        #|      Licensor for the purpose of discussing and improving the Work, but
        #|      excluding communication that is conspicuously marked or otherwise
        #|      designated in writing by the copyright owner as "Not a Contribution."
        #|
        #|      "Contributor" shall mean Licensor and any individual or Legal Entity
        #|      on behalf of whom a Contribution has been received by Licensor and
        #|      subsequently incorporated within the Work.
        #|
        #|   2. Grant of Copyright License. Subject to the terms and conditions of
        #|      this License, each Contributor hereby grants to You a perpetual,
        #|      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
        #|      copyright license to reproduce, prepare Derivative Works of,
        #|      publicly display, publicly perform, sublicense, and distribute the
        #|      Work and such Derivative Works in Source or Object form.
        #|
        #|   3. Grant of Patent License. Subject to the terms and conditions of
        #|      this License, each Contributor hereby grants to You a perpetual,
        #|      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
        #|      (except as stated in this section) patent license to make, have made,
        #|      use, offer to sell, sell, import, and otherwise transfer the Work,
        #|      where such license applies only to those patent claims licensable
        #|      by such Contributor that are necessarily infringed by their
        #|      Contribution(s) alone or by combination of their Contribution(s)
        #|      with the Work to which such Contribution(s) was submitted. If You
        #|      institute patent litigation against any entity (including a
        #|      cross-claim or counterclaim in a lawsuit) alleging that the Work
        #|      or a Contribution incorporated within the Work constitutes direct
        #|      or contributory patent infringement, then any patent licenses
        #|      granted to You under this License for that Work shall terminate
        #|      as of the date such litigation is filed.
        #|
        #|   4. Redistribution. You may reproduce and distribute copies of the
        #|      Work or Derivative Works thereof in any medium, with or without
        #|      modifications, and in Source or Object form, provided that You
        #|      meet the following conditions:
        #|
        #|      (a) You must give any other recipients of the Work or
        #|          Derivative Works a copy of this License; and
        #|
        #|      (b) You must cause any modified files to carry prominent notices
        #|          stating that You changed the files; and
        #|
        #|      (c) You must retain, in the Source form of any Derivative Works
        #|          that You distribute, all copyright, patent, trademark, and
        #|          attribution notices from the Source form of the Work,
        #|          excluding those notices that do not pertain to any part of
        #|          the Derivative Works; and
        #|
        #|      (d) If the Work includes a "NOTICE" text file as part of its
        #|          distribution, then any Derivative Works that You distribute must
        #|          include a readable copy of the attribution notices contained
        #|          within such NOTICE file, excluding those notices that do not
        #|          pertain to any part of the Derivative Works, in at least one
        #|          of the following places: within a NOTICE text file distributed
        #|          as part of the Derivative Works; within the Source form or
        #|          documentation, if provided along with the Derivative Works; or,
        #|          within a display generated by the Derivative Works, if and
        #|          wherever such third-party notices normally appear. The contents
        #|          of the NOTICE file are for informational purposes only and
        #|          do not modify the License. You may add Your own attribution
        #|          notices within Derivative Works that You distribute, alongside
        #|          or as an addendum to the NOTICE text from the Work, provided
        #|          that such additional attribution notices cannot be construed
        #|          as modifying the License.
        #|
        #|      You may add Your own copyright statement to Your modifications and
        #|      may provide additional or different license terms and conditions
        #|      for use, reproduction, or distribution of Your modifications, or
        #|      for any such Derivative Works as a whole, provided Your use,
        #|      reproduction, and distribution of the Work otherwise complies with
        #|      the conditions stated in this License.
        #|
        #|   5. Submission of Contributions. Unless You explicitly state otherwise,
        #|      any Contribution intentionally submitted for inclusion in the Work
        #|      by You to the Licensor shall be under the terms and conditions of
        #|      this License, without any additional terms or conditions.
        #|      Notwithstanding the above, nothing herein shall supersede or modify
        #|      the terms of any separate license agreement you may have executed
        #|      with Licensor regarding such Contributions.
        #|
        #|   6. Trademarks. This License does not grant permission to use the trade
        #|      names, trademarks, service marks, or product names of the Licensor,
        #|      except as required for reasonable and customary use in describing the
        #|      origin of the Work and reproducing the content of the NOTICE file.
        #|
        #|   7. Disclaimer of Warranty. Unless required by applicable law or
        #|      agreed to in writing, Licensor provides the Work (and each
        #|      Contributor provides its Contributions) on an "AS IS" BASIS,
        #|      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
        #|      implied, including, without limitation, any warranties or conditions
        #|      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
        #|      PARTICULAR PURPOSE. You are solely responsible for determining the
        #|      appropriateness of using or redistributing the Work and assume any
        #|      risks associated with Your exercise of permissions under this License.
        #|
        #|   8. Limitation of Liability. In no event and under no legal theory,
        #|      whether in tort (including negligence), contract, or otherwise,
        #|      unless required by applicable law (such as deliberate and grossly
        #|      negligent acts) or agreed to in writing, shall any Contributor be
        #|      liable to You for damages, including any direct, indirect, special,
        #|      incidental, or consequential damages of any character arising as a
        #|      result of this License or out of the use or inability to use the
        #|      Work (including but not limited to damages for loss of goodwill,
        #|      work stoppage, computer failure or malfunction, or any and all
        #|      other commercial damages or losses), even if such Contributor
        #|      has been advised of the possibility of such damages.
        #|
        #|   9. Accepting Warranty or Additional Liability. While redistributing
        #|      the Work or Derivative Works thereof, You may choose to offer,
        #|      and charge a fee for, acceptance of support, warranty, indemnity,
        #|      or other liability obligations and/or rights consistent with this
        #|      License. However, in accepting such obligations, You may act only
        #|      on Your own behalf and on Your sole responsibility, not on behalf
        #|      of any other Contributor, and only if You agree to indemnify,
        #|      defend, and hold each Contributor harmless for any liability
        #|      incurred by, or claims asserted against, such Contributor by reason
        #|      of your accepting any such warranty or additional liability.
        #|
        #|   END OF TERMS AND CONDITIONS
        #|
        #|   APPENDIX: How to apply the Apache License to your work.
        #|
        #|      To apply the Apache License to your work, attach the following
        #|      boilerplate notice, with the fields enclosed by brackets "[]"
        #|      replaced with your own identifying information. (Don't include
        #|      the brackets!)  The text should be enclosed in the appropriate
        #|      comment syntax for the file format. We also recommend that a
        #|      file or class name and description of purpose be included on the
        #|      same "printed page" as the copyright notice for easier
        #|      identification within third-party archives.
        #|
        #|   Copyright [yyyy] [name of copyright owner]
        #|
        #|   Licensed under the Apache License, Version 2.0 (the "License");
        #|   you may not use this file except in compliance with the License.
        #|   You may obtain a copy of the License at
        #|
        #|       http://www.apache.org/licenses/LICENSE-2.0
        #|
        #|   Unless required by applicable law or agreed to in writing, software
        #|   distributed under the License is distributed on an "AS IS" BASIS,
        #|   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        #|   See the License for the specific language governing permissions and
        #|   limitations under the License.
        #|
      ),
    )
  })
  @json.inspect(log, content=[
    "proxy server: connected to raw.githubusercontent.com:443 successfully",
  ])
}

///|
async test "proxied http request" {
  let log = []
  @async.with_task_group(group => {
    let server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr().port()
    group.spawn_bg(no_wait=true, () => server.run_forever(
      handle_connect(log, _, _, _),
    ))
    let (_, result) = @http.get(
      "http://www.example.org",
      proxy=@http.Client::new("http://localhost:\{port}"),
    )
    assert_true(result.text().has_prefix("<!doctype html>"))
  })
  @json.inspect(log, content=[
    "proxy server: connected to www.example.org:80 successfully",
  ])
}

///|
async test "proxied misc request" {
  let log = []
  let proxy_server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
  let proxy_server_addr = proxy_server.addr()
  let server = @socket.TcpServer::new(@socket.Addr::parse("127.0.0.1:0"))
  let port = server.addr().port()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => proxy_server.run_forever(
      handle_connect(log, _, _, _),
    ))
    group.spawn_bg(no_wait=true, () => server.run_forever((conn, _) => {
      let conn = @http.ServerConnection::new(conn)
      for {
        let request = conn.read_request()
        let body = conn.read_all().text()
        log.push(
          "target server: received request \{request.meth} \{request.path} \{body}",
        )
        conn..send_response(200, "OK")..end_response()
      }
    }))
    async fn proxy() {
      @http.Client::new("http://localhost:\{proxy_server_addr.port()}")
    }

    let _ = @http.get("http://localhost:\{port}", proxy=proxy())
    let _ = @http.put("http://localhost:\{port}", "abcd", proxy=proxy())
    let _ = @http.post("http://localhost:\{port}", "efgh", proxy=proxy())

  })
  for i in 0..<log.length() {
    log[i] = log[i].replace_all(old=":\{port}", new=":XXXXX")
  }
  @json.inspect(log, content=[
    "proxy server: connected to localhost:XXXXX successfully", "target server: received request Get / ",
    "proxy server: connected to localhost:XXXXX successfully", "target server: received request Put / abcd",
    "proxy server: connected to localhost:XXXXX successfully", "target server: received request Post / efgh",
  ])
}

///|
async test "proxy error" {
  let proxy_server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
  let port = proxy_server.addr().port()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => proxy_server.run_forever((_, _, conn) => {
      conn.send_response(407, "ProxyAuthenticationRequired")
      conn.end_response()
    }))
    try
      @http.get(
        "https://www.example.org",
        proxy=@http.Client::new("http://localhost:\{port}"),
      )
    catch {
      err =>
        inspect(
          err,
          content=(
            #|ProxyError({code: 407, reason: "ProxyAuthenticationRequired", headers: {"content-length": "0"}})
          ),
        )
    } noraise {
      _ => raise Failure("expected error, but nothing happens")
    }
  })
}

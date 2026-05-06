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
pub suberror TlsError {
  TlsError(String)
} derive(Debug, ToJson)

///|
pub suberror ConnectionClosed derive(Debug, ToJson)

///|
const PEM_BEGIN = "-----BEGIN CERTIFICATE-----"

///|
const PEM_END = "-----END CERTIFICATE-----"

///|
fn decode_pem_certificates(pem : String) -> Array[Bytes] raise TlsError {
  let certs = []
  for chunk in pem.split(PEM_BEGIN) {
    match chunk.split_once(PEM_END) {
      None => ()
      Some((base64_body, _)) => {
        let cert = @base64.decode(base64_body.trim(), ignore_whitespace=true) catch {
          _ =>
            raise TlsError(
              "invalid PEM certificate in custom root certificate file",
            )
        }
        certs.push(cert)
      }
    }
  }
  guard !certs.is_empty() else {
    raise TlsError("no PEM certificate found in custom root certificate file")
  }
  certs
}

///|
/// Specify the trusted root when performing TLS certificate validation.
///
/// - `NoVerification`: disable certificate validation.
///   This destroys the whole purpose of using TLS and should only be used for testing purpose.
///
/// - `SystemRoot`: use the default trusted root of the system
///
/// - `CustomPemFile(name)`: use the certificates in the PEM file `name` exclusively as trusted root.
///   Useful for connecting via a pre-shared self-signed certificate
pub(all) enum TrustedRoot {
  NoVerification
  SystemRoot
  CustomPemFile(String)
}

///|
/// Create a TLS client that read from write to `inner`.
/// `client` will block until TLS handshake to remote server completed.
///
/// `trust` specifies which servers are trusted and how certificate validation is performed.
/// See `TrustedRoot` for more details. The default is `SystemRoot`.
///
/// If `host` is present, it will be used to verify the peer's certificate.
///
/// If `host` is present and `sni` is `true` (`true` by default),
/// Server Name Indication (SNI) field of TLS will be set to `host`.
/// `sni=false` is currently unsupported on Windows.
#label_migration(verify, fill=false, msg="use `trust` instead")
pub async fn[Inner : @io.Reader + @io.Writer] Tls::client(
  inner : Inner,
  verify? : Bool = true,
  host? : String,
  sni? : Bool = true,
  trust? : TrustedRoot,
) -> Tls {
  let trust = match trust {
    Some(trust) => trust
    None => if verify { SystemRoot } else { NoVerification }
  }
  Tls::client_from_pair(inner, inner, host?, sni~, trust~)
}

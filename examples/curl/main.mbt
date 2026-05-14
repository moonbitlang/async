///|
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
async fn download(
  url : String,
  proxy~ : String?,
  output~ : &@io.Writer,
) -> Unit {
  let proxy = match proxy {
    None => None
    Some(proxy_url) => Some(@http.Client(proxy_url))
  }
  let (_response, body) = @http.get_stream(url, proxy?)
  defer body.close()
  output.write_reader(body)
}

///|
async fn main {
  let matches = @argparse.Command(
    "curl",
    about="Download content of URL",
    options=[
      OptionArg(
        "output",
        short='o',
        long="",
        about="write output to FILE instead of standard output",
      ),
      OptionArg("proxy", long="proxy", about="download via HTTP proxy URL"),
    ],
    positionals=[
      PositionArg(
        "url",
        about="URL to download",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  ).parse()
  guard matches.values is { "url": [url], .. } else { fail("no URL specified") }
  let output = match matches.values {
    { "output": [file], .. } => Some(file)
    _ => None
  }
  let proxy = match matches.values {
    { "proxy": [proxy_url], .. } => Some(proxy_url)
    _ => None
  }
  match output {
    None => download(url, proxy~, output=@stdio.stdout)
    Some(output) => {
      let file = @fs.open(output, mode=WriteOnly, create_mode=CreateOrTruncate)
      defer file.close()
      download(url, proxy~, output=file)
    }
  }
}

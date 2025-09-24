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
async test "https request" {
  let (_, result) = @http.get("https://www.example.org")
  inspect(
    result.text(),
    content=(
      #|<!doctype html>
      #|<html>
      #|<head>
      #|    <title>Example Domain</title>
      #|
      #|    <meta charset="utf-8" />
      #|    <meta http-equiv="Content-type" content="text/html; charset=utf-8" />
      #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
      #|    <style type="text/css">
      #|    body {
      #|        background-color: #f0f0f2;
      #|        margin: 0;
      #|        padding: 0;
      #|        font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", "Open Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;
      #|        
      #|    }
      #|    div {
      #|        width: 600px;
      #|        margin: 5em auto;
      #|        padding: 2em;
      #|        background-color: #fdfdff;
      #|        border-radius: 0.5em;
      #|        box-shadow: 2px 3px 7px 2px rgba(0,0,0,0.02);
      #|    }
      #|    a:link, a:visited {
      #|        color: #38488f;
      #|        text-decoration: none;
      #|    }
      #|    @media (max-width: 700px) {
      #|        div {
      #|            margin: 0 auto;
      #|            width: auto;
      #|        }
      #|    }
      #|    </style>    
      #|</head>
      #|
      #|<body>
      #|<div>
      #|    <h1>Example Domain</h1>
      #|    <p>This domain is for use in illustrative examples in documents. You may use this
      #|    domain in literature without prior coordination or asking for permission.</p>
      #|    <p><a href="https://www.iana.org/domains/example">More information...</a></p>
      #|</div>
      #|</body>
      #|</html>
      #|
    ),
  )
}

///|
async test "http request" {
  let (_, result) = @http.get("http://www.example.org")
  inspect(
    result.text(),
    content=(
      #|<!doctype html>
      #|<html>
      #|<head>
      #|    <title>Example Domain</title>
      #|
      #|    <meta charset="utf-8" />
      #|    <meta http-equiv="Content-type" content="text/html; charset=utf-8" />
      #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
      #|    <style type="text/css">
      #|    body {
      #|        background-color: #f0f0f2;
      #|        margin: 0;
      #|        padding: 0;
      #|        font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", "Open Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;
      #|        
      #|    }
      #|    div {
      #|        width: 600px;
      #|        margin: 5em auto;
      #|        padding: 2em;
      #|        background-color: #fdfdff;
      #|        border-radius: 0.5em;
      #|        box-shadow: 2px 3px 7px 2px rgba(0,0,0,0.02);
      #|    }
      #|    a:link, a:visited {
      #|        color: #38488f;
      #|        text-decoration: none;
      #|    }
      #|    @media (max-width: 700px) {
      #|        div {
      #|            margin: 0 auto;
      #|            width: auto;
      #|        }
      #|    }
      #|    </style>    
      #|</head>
      #|
      #|<body>
      #|<div>
      #|    <h1>Example Domain</h1>
      #|    <p>This domain is for use in illustrative examples in documents. You may use this
      #|    domain in literature without prior coordination or asking for permission.</p>
      #|    <p><a href="https://www.iana.org/domains/example">More information...</a></p>
      #|</div>
      #|</body>
      #|</html>
      #|
    ),
  )
}

// Import object for moonbitlang/async http wasm-gc fetch client.
// When loading the compiled wasm-gc module, merge this into the import object:
//
//   const imports = { ...otherImports, ...httpImports };
//   const { instance } = await WebAssembly.instantiateStreaming(fetch("module.wasm"), imports);

export const moonbitlang_async_http = {
  new_headers: () => new Headers(),
  headers_append: (h, name, value) => h.append(name, value),
  headers_for_each: (h, callback) => {
    for (const [name, value] of h.entries()) callback(name, value);
  },
  response_status: (r) => r.status,
  response_status_text: (r) => r.statusText,
  response_headers: (r) => r.headers,
  response_body: (r) => r.body,
  fetch_request: (uri, method, headers, body, signal) => {
    const fixed_body = (method === "GET" || method === "HEAD") ? null : body;
    return fetch(uri, {
      body: fixed_body,
      method: method,
      headers: headers,
      signal: signal,
      duplex: 'half',
    });
  },
};

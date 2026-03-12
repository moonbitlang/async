// Import object for moonbitlang/async js_async wasm-gc Promise and stream bridging.
// When loading the compiled wasm-gc module, merge this into the import object:
//
//   const imports = { ...otherImports, ...jsAsyncImports };
//   const { instance } = await WebAssembly.instantiateStreaming(fetch("module.wasm"), imports);

export const moonbitlang_async_js = {
  abort_error: () => {
    const err = new Error();
    err.name = 'AbortError';
    return err;
  },
  jsvalue_to_string: (v) => v.toString(),
  new_abort_controller: () => new AbortController(),
  abort_controller_signal: (ctrl) => ctrl.signal,
  abort_controller_abort: (ctrl) => ctrl.abort(),
  abort_signal_on_abort: (signal, f) =>
    signal.addEventListener('abort', f, { once: true }),
  promise_then: (p, resolve, reject) => p.then(resolve, reject),
  create_deferred: () => {
    let resolve, reject;
    const promise = new Promise((res, rej) => {
      resolve = res;
      reject = rej;
    });
    return { promise, resolve, reject };
  },
  resolve_deferred: (d, value) => d.resolve(value),
  reject_deferred: (d, err) => d.reject(err),
  get_deferred_promise: (d) => d.promise,
};

export const moonbitlang_async_stream = {
  reader_read: (reader) => reader.read(),
  reader_release_lock: (reader) => reader.releaseLock(),
  read_result_done: (result) => result.done,
  read_result_value_length: (result) =>
    result.value ? result.value.byteLength : 0,
  read_result_copy_value: (result, set_byte) => {
    const arr = result.value;
    for (let i = 0; i < arr.byteLength; i++) set_byte(i, arr[i]);
  },
  controller_close: (ctrl) => ctrl.close(),
  controller_enqueue: (ctrl, len, get_byte) => {
    const arr = new Uint8Array(len);
    for (let i = 0; i < len; i++) arr[i] = get_byte(i);
    ctrl.enqueue(arr);
  },
  new_readable_stream: (pull, cancel) =>
    new ReadableStream({ start: pull, pull: pull, cancel: cancel }),
  cancel_stream: (stream) => stream.cancel(),
  get_reader: (stream) => stream.getReader(),
};

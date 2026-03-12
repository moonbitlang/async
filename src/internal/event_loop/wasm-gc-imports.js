// Import object for moonbitlang/async wasm-gc timer and event loop.
// When loading the compiled wasm-gc module, merge this into the import object:
//
//   const imports = { ...otherImports, ...asyncImports };
//   const { instance } = await WebAssembly.instantiateStreaming(fetch("module.wasm"), imports);

export const moonbitlang_async_timer = {
  set_timeout: (duration, f) => setTimeout(f, duration),
  clear_timeout: (timer) => clearTimeout(timer),
};

export const moonbitlang_async_time = {
  date_now: () => Date.now(),
};

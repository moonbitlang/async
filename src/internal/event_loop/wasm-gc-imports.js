// Import objects for moonbitlang/async wasm-gc timer, event loop, and time modules.
// When loading the compiled wasm-gc module, merge these into the import object:
//
//   import { moonbitlang_async_timer, moonbitlang_async_time } from "./wasm-gc-imports.js";
//   const imports = { ...otherImports, moonbitlang_async_timer, moonbitlang_async_time };
//   const { instance } = await WebAssembly.instantiateStreaming(fetch("module.wasm"), imports);

export const moonbitlang_async_timer = {
  setTimeout: (duration, f) => setTimeout(f, duration),
  clearTimeout: (timer) => clearTimeout(timer),
};

export const moonbitlang_async_time = {
  date_now: () => Date.now(),
};

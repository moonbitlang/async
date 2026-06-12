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
let tmpdir_seed : @random.Rand = {
  let seed = Buffer()
  let now = @async.now()
  for _ in 0..<4 {
    seed.write_int64_le(now)
  }
  @random.Rand::chacha8(seed=seed.contents())
}

///|
fn get_tmp_path_len_ffi() -> Int = "moonbit_v0" "fs/get_tmp_path_len"

///|
fn get_tmp_path_ffi(ptr : Int, len : Int) -> Int = "moonbit_v0" "fs/get_tmp_path"

///|
let tmp_base_path : Ref[String?] = Ref(None)

///|
fn get_tmp_base_path() -> String {
  if tmp_base_path.val is Some(path) {
    return path
  }
  let len = get_tmp_path_len_ffi()
  if len < 0 {
    let err = @os_error.errno_to_string(@os_error.get_errno())
    abort("failed to obtain directory for temporary files: \{err}")
  }
  let data = FixedArray::make(len, b'\x00')
  let ret = get_tmp_path_ffi(@wasm_ffi.byte_array_to_ptr(data), len)
  if ret != 0 {
    let err = @os_error.errno_to_string(@os_error.get_errno())
    abort("failed to obtain directory for temporary files: \{err}")
  }
  let path = @utf16.decode_lossy(data.unsafe_reinterpret_as_bytes())
  tmp_base_path.val = Some(path)
  path
}

///|
pub async fn tmpdir(prefix~ : StringView) -> String {
  for _ in 0..<@int.MAX_VALUE {
    let hasher = Hasher()
    hasher.combine_uint64(tmpdir_seed.uint64())
    hasher.combine_int64(@async.now())
    let h = hasher.finalize().reinterpret_as_uint()
    let path = StringBuilder::new()
    path.write_string(get_tmp_base_path())
    path.write_stringview(prefix)
    path.write_char('.')
    path.write_string(@env_util.current_process.to_string())
    path.write_char('.')
    path.write_string(h.to_string(radix=16))
    let path = path.to_string()
    try @event_loop.mkdir(path, mode=0o700, context="@fs.tmpdir()") catch {
      @os_error.OSError(_) as err if err.is_EEXIST() => ()
      err => raise err
    } noraise {
      _ => return path
    }
  }
  raise Failure::Failure("failed to create tmp directory: too many attempts")
}

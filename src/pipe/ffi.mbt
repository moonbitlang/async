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

/// Check if a file descriptor is in blocking mode.
/// 
/// This function uses a C foreign function interface to check whether
/// a given file descriptor is currently set to blocking or non-blocking mode.
/// It's used internally to determine the current state of standard streams
/// (stdin, stdout, stderr) before modifying their blocking behavior.
/// 
/// # Arguments
/// 
/// * `fd` - The file descriptor to check (e.g., 0 for stdin, 1 for stdout, 2 for stderr)
/// 
/// # Returns
/// 
/// An integer where:
/// - A positive value indicates the file descriptor is in blocking mode
/// - Zero or negative indicates non-blocking mode
/// 
/// # Note
/// 
/// This function is primarily used internally by the pipe module to manage
/// the blocking state of standard streams when they are wrapped as pipes.
extern "C" fn get_blocking(fd : Int) -> Int = "moonbitlang_async_get_blocking"

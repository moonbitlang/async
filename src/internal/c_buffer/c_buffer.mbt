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

/// A C buffer type that provides a direct interface to C memory buffers.
/// 
/// This type represents a raw C pointer and is used for efficient
/// interoperation with C code, allowing zero-copy data transfer between
/// MoonBit and C memory regions.
///
/// # Safety
/// 
/// This type is marked as `#external` and requires careful handling:
/// - The buffer must be properly allocated before use
/// - The buffer must be freed using `Buffer::free` to prevent memory leaks
/// - Accessing beyond the allocated size leads to undefined behavior
/// - The buffer lifetime must be managed manually
#external
pub type Buffer

/// Copies data from a MoonBit Bytes object to a C buffer.
///
/// This function performs a memory copy operation from the MoonBit-managed
/// Bytes object to the C buffer, starting at the specified offset.
///
/// # Parameters
/// 
/// - `dst`: The destination C buffer
/// - `src`: The source Bytes object (borrowed)
/// - `offset`: The starting offset in the source Bytes
/// - `len`: The number of bytes to copy
///
/// # Safety
/// 
/// - The destination buffer must have sufficient space to hold `len` bytes
/// - The source must have at least `offset + len` bytes available
/// - Both buffers must be valid memory regions
#borrow(src)
pub extern "C" fn Buffer::blit_from_bytes(
  dst : Buffer,
  src~ : Bytes,
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_to_c"

/// Copies data from a C buffer to a MoonBit FixedArray[Byte].
///
/// This function performs a memory copy operation from the C buffer
/// to a MoonBit FixedArray[Byte], starting at the specified offset
/// in the destination array.
///
/// # Parameters
/// 
/// - `src`: The source C buffer
/// - `dst`: The destination FixedArray[Byte] (borrowed)
/// - `offset`: The starting offset in the destination array
/// - `len`: The number of bytes to copy
///
/// # Safety
/// 
/// - The source buffer must contain at least `len` valid bytes
/// - The destination array must have at least `offset + len` capacity
/// - Both memory regions must be valid
#borrow(dst)
pub extern "C" fn Buffer::blit_to_bytes(
  src : Buffer,
  dst~ : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_from_c"

/// Returns the length of a null-terminated C string in the buffer.
///
/// This function calculates the length of a C string (null-terminated)
/// starting from the beginning of the buffer. It's equivalent to the
/// C `strlen` function.
///
/// # Parameters
/// 
/// - `buf`: The C buffer containing a null-terminated string
///
/// # Returns
/// 
/// The number of characters before the first null terminator
///
/// # Safety
/// 
/// - The buffer must contain a valid null-terminated string
/// - The buffer must be readable up to the null terminator
/// - Undefined behavior if the buffer doesn't contain a null terminator
pub extern "C" fn Buffer::strlen(buf : Buffer) -> Int = "moonbitlang_async_strlen"

/// Creates a null pointer buffer.
///
/// This function returns a Buffer that represents a null pointer (0).
/// It's primarily used for initialization or as a sentinel value.
///
/// # Returns
/// 
/// A Buffer representing a null pointer
///
/// # Safety
/// 
/// - The returned buffer should not be used for memory operations
/// - This is mainly for comparison or initialization purposes
extern "C" fn Buffer::null() -> Buffer = "moonbitlang_async_null_pointer"

/// A constant representing a null buffer.
///
/// This is a pre-allocated null buffer that can be used for comparisons
/// or as a default value. It represents a null pointer in C terms.
pub let null : Buffer = Buffer::null()

/// Frees the memory associated with a C buffer.
///
/// This function releases the memory allocated for the buffer using
/// the standard C `free` function. After calling this function,
/// the buffer should not be used.
///
/// # Parameters
/// 
/// - `buf`: The buffer to free
///
/// # Safety
/// 
/// - The buffer must have been allocated with `malloc` or similar
/// - The buffer must not be used after calling this function
/// - Double-free will result in undefined behavior
/// - Freeing a null buffer is safe (no-op)
pub extern "C" fn Buffer::free(buf : Buffer) = "free"

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
fn try_parse_ipv6(
  input : String
) -> (FixedArray[UInt], Int, Int, Int) raise InvalidAddr {
  // Make sure the format is [addr]:port
  guard input.has_prefix("[") else {
    // IPv6 address must start with '['
    raise InvalidAddr
  }

  // Find the closing bracket
  guard input.rev_find("]") is Some(bracket_end) else {
    // IPv6 address missing closing ']'
    raise InvalidAddr
  }

  // Check the part after the closing bracket, it must be ":port"
  let remaining = input.substring(start=bracket_end + 1)
  guard remaining.has_prefix(":") else {
    // Missing port after IPv6 address
    raise InvalidAddr
  }

  // Parse the IPv6 address and port
  let ip_str = input.substring(start=1, end=bracket_end)
  let port_str = remaining.substring(start=1)

  // Parse the IPv6 address into a byte array
  let ip_bytes = parse_ipv6_to_bytes(ip_str)
  let port = parse_port(port_str)
  (ip_bytes, port, 0, 0)
}

///|
fn parse_ipv6_to_bytes(ip_str : String) -> FixedArray[UInt] raise InvalidAddr {
  // Handle the case where the IPv6 address is "::"
  if ip_str == "::" {
    return FixedArray::make(16, 0)
  }

  // Check for "::" compression
  let compression_count = count_substring_occurrences(ip_str, "::")
  guard compression_count <= 1 else {
    // IPv6 address can only have one '::' compression
    raise InvalidAddr
  }
  if compression_count == 1 {
    return parse_compressed_ipv6_to_bytes(ip_str)
  } else {
    return parse_full_ipv6_to_bytes(ip_str)
  }
}

///|
fn parse_compressed_ipv6_to_bytes(
  ip_str : String
) -> FixedArray[UInt] raise InvalidAddr {
  let parts = ip_str.split("::").collect()
  let left_part = parts[0]
  let right_part = if parts.length() > 1 { parts[1] } else { "" }
  let left_groups = if left_part.is_empty() {
    []
  } else {
    left_part.split(":").collect()
  }

  // Parse the right part, which may contain IPv4 address
  let right_groups = if right_part.is_empty() {
    []
  } else {
    right_part.split(":").collect()
  }

  // Check if the last group is an IPv4 address
  let (right_groups_final, ipv4_bytes) = if !right_groups.is_empty() &&
    right_groups[right_groups.length() - 1].contains(".") {
    let ipv4_str = right_groups[right_groups.length() - 1]
    let (a, b, c, d) = parse_ipv4_to_bytes(ipv4_str)
    // Remove the IPv4 part from the right groups
    let new_right = Array::new()
    for i in 0..<(right_groups.length() - 1) {
      new_right.push(right_groups[i])
    }
    (new_right, Some((a, b, c, d)))
  } else {
    (right_groups, None)
  }

  // Calculate the number of groups of compression
  let ipv4_group_count = if ipv4_bytes.is_empty() { 0 } else { 2 }
  let total_explicit_groups = left_groups.length() +
    right_groups_final.length() +
    ipv4_group_count
  guard total_explicit_groups < 8 else {
    // IPv6 address can have at most less than 8 explicit groups if "::" is used
    raise InvalidAddr
  }
  let compression_groups = 8 - total_explicit_groups

  // Build a 16-byte array initialized to zero
  let result : FixedArray[UInt] = FixedArray::make(16, 0)
  let mut byte_index = 0

  // Add left side groups
  for group_str in left_groups {
    let group_value = parse_ipv6_group(group_str.to_string())
    result[byte_index] = (group_value >> 8) & 0xFF
    result[byte_index + 1] = group_value & 0xFF
    byte_index += 2
  }

  // Add compression groups (zero groups)
  for _ in 0..<compression_groups {
    result[byte_index] = 0
    result[byte_index + 1] = 0
    byte_index += 2
  }

  // Add right side groups
  for group_str in right_groups_final {
    let group_value = parse_ipv6_group(group_str.to_string())
    result[byte_index] = (group_value >> 8) & 0xFF
    result[byte_index + 1] = group_value & 0xFF
    byte_index += 2
  }

  // Add IPv4 bytes if they were parsed
  if ipv4_bytes is Some((a, b, c, d)) {
    result[byte_index + 0] = a
    result[byte_index + 1] = b
    result[byte_index + 2] = c
    result[byte_index + 3] = d
  }
  result
}

///|
fn parse_full_ipv6_to_bytes(
  ip_str : String
) -> FixedArray[UInt] raise InvalidAddr {
  let parts = ip_str.split(":").collect()
  let result : FixedArray[UInt] = FixedArray::make(16, 0)
  let mut byte_index = 0
  // Check if the last part contains a dot, indicating an embedded IPv4 address
  if !parts.is_empty() && parts[parts.length() - 1].contains(".") {
    guard parts.length() == 7 else {
      // IPv6 address with embedded IPv4 must have 7 parts
      raise InvalidAddr
    }

    // Parse the last part as an IPv4 address
    let ipv4_str = parts[parts.length() - 1]
    let (a, b, c, d) = parse_ipv4_to_bytes(ipv4_str)

    // Build a 16-byte array initialized to zero
    let mut byte_index = 0

    // Add the first 6 IPv6 groups
    for i in 0..<6 {
      let group_value = parse_ipv6_group(parts[i].to_string())
      result[byte_index] = (group_value >> 8) & 0xFF
      result[byte_index + 1] = group_value & 0xFF
      byte_index += 2
    }
    result[byte_index + 0] = a
    result[byte_index + 1] = b
    result[byte_index + 2] = c
    result[byte_index + 3] = d
    result
  } else {
    // The pure IPv6 address should have 8 groups
    guard parts.length() == 8 else {
      // Full IPv6 address must have 8 groups
      raise InvalidAddr
    }
    for group_str in parts {
      let group_value = parse_ipv6_group(group_str.to_string())
      result[byte_index] = (group_value >> 8) & 0xFF
      result[byte_index + 1] = group_value & 0xFF
      byte_index += 2
    }
    result
  }
}

///|
fn parse_ipv6_group(group : String) -> UInt raise InvalidAddr {
  guard !group.is_empty() && group.length() <= 4 else { raise InvalidAddr }
  @strconv.parse_uint(group, base=16) catch {
    _ => raise InvalidAddr
  }
}

///|
fn parse_ipv4_to_bytes(
  ip_str : @string.View
) -> (UInt, UInt, UInt, UInt) raise InvalidAddr {
  let parts = ip_str.split(".").collect()
  guard parts.length() == 4 else { raise InvalidAddr }
  fn parse_octal(x : @string.View) raise InvalidAddr {
    let value = @strconv.parse_uint(x.to_string()) catch {
      _ => raise InvalidAddr
    }
    guard value < 256 else { raise InvalidAddr }
    value
  }

  return (
    parse_octal(parts[0]),
    parse_octal(parts[1]),
    parse_octal(parts[2]),
    parse_octal(parts[3]),
  )
}

///|
fn try_parse_ipv4(input : String) -> (UInt, Int) raise InvalidAddr {
  // Find the last colon to separate IP and port
  guard input.rev_find(":") is Some(last_colon) else { raise InvalidAddr }
  let ip_str = input.substring(end=last_colon)
  let port_str = input.substring(start=last_colon + 1)
  let port = @strconv.parse_int(port_str.to_string()) catch {
    _ => raise InvalidAddr
  }
  guard 0 <= port && port < 65536 else { raise InvalidAddr }
  // Parse the IP address
  let (a, b, c, d) = parse_ipv4_to_bytes(ip_str.view())
  let ip = (a << 24) | (b << 16) | (c << 8) | d
  (ip, port)
}

///|
fn parse_port(port_str : String) -> Int raise InvalidAddr {
  guard !port_str.is_empty() else { raise InvalidAddr }
  let port = @strconv.parse_int(port_str) catch { _ => raise InvalidAddr }
  guard 0 <= port && port < 65536 else { raise InvalidAddr }
  port
}

///|
fn count_substring_occurrences(text : String, pattern : String) -> Int {
  let mut count = 0
  let mut start = 0
  while text.substring(start~).find(pattern) is Some(pos) {
    count += 1
    start += pos + pattern.length()
  }
  count
}

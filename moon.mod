name = "moonbitlang/async"

version = "0.19.4"

readme = "README.md"

repository = "https://github.com/moonbitlang/async"

license = "Apache-2.0"

keywords = [ ]

description = "Asynchronous programming library for MoonBit"

preferred_target = "native"

options(
  source: "src",
  exclude: [ "test_directory", "test_keys" ],
)

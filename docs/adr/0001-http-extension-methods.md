# Preserve the request method enum with a validated extension branch

Support arbitrary legal HTTP method tokens in clients and servers while preserving the existing named `RequestMethod` variants. Add `Extension(String)` rather than replacing the public enum or introducing an extensible enum: downstream constructors would still require a separate mapping to and from wire tokens.

A public string parser validates a nonempty HTTP token, preserves case, and maps exact existing standard method names to their named variants. Directly constructed extension values are validated before request bytes are written or sending state changes; invalid tokens and exact duplicates of existing standard method names are rejected. This preserves the existing derived equality, hashing, and ordering without introducing multiple valid representations of the same method.

Adding a variant requires downstream exhaustive matches to be updated. WebDAV is a use case for method extensibility; implementing its resource, property, and locking semantics is outside this change.

The public conversion API is `RequestMethod::from_string(StringView)` and `RequestMethod::as_string()`. Invalid local method values raise `InvalidMethod`; invalid method tokens received by the server retain the existing `BadRequest` behavior.

The JavaScript client retains its Fetch backend and its restrictions, including forbidden methods and normalization of selected standard method names. Native and wasm preserve extension method names on the wire. This change does not replace Fetch or expand WebDAV protocol support.

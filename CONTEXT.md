# HTTP Method Vocabulary

Terminology for HTTP request method extensibility in this library.

## Language

**Extension method**:
An HTTP request method beyond the nine methods currently named by this library, identified by its case-sensitive method token. It need not be specific to WebDAV.
_Avoid_: Custom-only method, WebDAV-only method

**WebDAV**:
An HTTP extension for distributed authoring, including resource properties, collections, and locking. Its additional request methods are a use case for general HTTP method extensibility.

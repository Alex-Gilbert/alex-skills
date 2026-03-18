/// Request-scoped author context using Erlang process dictionary.
/// Mist spawns a process per connection, so this is safe for concurrent requests.

/// Set the author for the current request process.
@external(erlang, "alex_memory_ffi", "put_author")
pub fn set(author: String) -> Nil

/// Get the author for the current request process.
/// Returns Error(Nil) if no author has been set.
@external(erlang, "alex_memory_ffi", "get_author")
pub fn get() -> Result(String, Nil)

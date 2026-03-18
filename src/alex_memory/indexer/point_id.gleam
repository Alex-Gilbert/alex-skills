import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/string

/// Generate a deterministic UUID-shaped ID from a vault path and chunk index.
///
/// The ID is derived from SHA-256 of `vault_path:chunk_index`, formatted as
/// an 8-4-4-4-12 hex string. These are not compliant UUID v5 — just
/// SHA-256-derived hex strings that Qdrant accepts as string point IDs.
///
pub fn generate(vault_path: String, chunk_index: Int) -> String {
  let input = vault_path <> ":" <> int.to_string(chunk_index)
  let hash = crypto.hash(crypto.Sha256, bit_array.from_string(input))

  let assert <<a:bytes-size(4), b:bytes-size(2), c:bytes-size(2), d:bytes-size(2), e:bytes-size(6), _:bytes>> =
    hash

  string.join(
    [
      bit_array.base16_encode(a),
      bit_array.base16_encode(b),
      bit_array.base16_encode(c),
      bit_array.base16_encode(d),
      bit_array.base16_encode(e),
    ],
    "-",
  )
  |> string.lowercase
}

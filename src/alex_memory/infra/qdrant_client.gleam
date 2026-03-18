import gleam/dynamic
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub type QdrantError {
  ConnectionError(String)
  ApiError(Int, String)
}

pub type SearchHit {
  SearchHit(id: String, score: Float, payload: dynamic.Dynamic)
}

pub type ScrollPoint {
  ScrollPoint(id: String, payload: dynamic.Dynamic)
}

/// Helper to build a Qdrant match filter for a field/value pair
pub fn match_filter(field: String, value: String) -> json.Json {
  json.object([
    #(
      "must",
      json.array(
        [
          json.object([
            #(
              "key",
              json.string(field),
            ),
            #(
              "match",
              json.object([#("value", json.string(value))]),
            ),
          ]),
        ],
        fn(x) { x },
      ),
    ),
  ])
}

/// GET /collections/{name} — returns Ok(Nil) if collection exists.
/// If 404, creates it with Cosine distance and returns Ok(Nil).
pub fn ensure_collection(
  base_url: String,
  collection: String,
  vector_size: Int,
) -> Result(Nil, QdrantError) {
  let check_url = base_url <> "/collections/" <> collection
  use req <- result.try(
    request.to(check_url)
    |> result.map_error(fn(_) {
      ConnectionError("Invalid URL: " <> check_url)
    }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    404 -> create_collection(base_url, collection, vector_size)
    status ->
      Error(ApiError(status, "Unexpected status checking collection: " <> resp.body))
  }
}

fn create_collection(
  base_url: String,
  collection: String,
  vector_size: Int,
) -> Result(Nil, QdrantError) {
  let url = base_url <> "/collections/" <> collection
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let body =
    json.object([
      #(
        "vectors",
        json.object([
          #("size", json.int(vector_size)),
          #("distance", json.string("Cosine")),
        ]),
      ),
    ])
    |> json.to_string
  let req =
    req
    |> request.set_method(http.Put)
    |> request.set_body(body)
    |> request.set_header("content-type", "application/json")
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status ->
      Error(ApiError(status, "Failed to create collection: " <> resp.body))
  }
}

/// DELETE /collections/{name}
pub fn delete_collection(
  base_url: String,
  collection: String,
) -> Result(Nil, QdrantError) {
  let url = base_url <> "/collections/" <> collection
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let req = req |> request.set_method(http.Delete)
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status ->
      Error(ApiError(status, "Failed to delete collection: " <> resp.body))
  }
}

/// PUT /collections/{name}/points — upsert a single point
pub fn upsert(
  base_url: String,
  collection: String,
  id: String,
  vector: List(Float),
  payload: json.Json,
) -> Result(Nil, QdrantError) {
  let url = base_url <> "/collections/" <> collection <> "/points"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let point =
    json.object([
      #("id", json.string(id)),
      #("vector", json.array(vector, json.float)),
      #("payload", payload),
    ])
  let body =
    json.object([#("points", json.array([point], fn(x) { x }))])
    |> json.to_string
  let req =
    req
    |> request.set_method(http.Put)
    |> request.set_body(body)
    |> request.set_header("content-type", "application/json")
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status -> Error(ApiError(status, "Failed to upsert point: " <> resp.body))
  }
}

/// POST /collections/{name}/points/search
pub fn search(
  base_url: String,
  collection: String,
  vector: List(Float),
  limit: Int,
  filter: Option(json.Json),
) -> Result(List(SearchHit), QdrantError) {
  let url =
    base_url <> "/collections/" <> collection <> "/points/search"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let base_fields = [
    #("vector", json.array(vector, json.float)),
    #("limit", json.int(limit)),
    #("with_payload", json.bool(True)),
  ]
  let fields = case filter {
    option.None -> base_fields
    option.Some(f) -> list.append(base_fields, [#("filter", f)])
  }
  let body = json.object(fields) |> json.to_string
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(body)
    |> request.set_header("content-type", "application/json")
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> {
      let hit_decoder = {
        use id <- decode.field("id", decode.string)
        use score <- decode.field("score", decode.float)
        use payload <- decode.field("payload", decode.dynamic)
        decode.success(SearchHit(id: id, score: score, payload: payload))
      }
      let decoder = decode.at(["result"], decode.list(hit_decoder))
      json.parse(resp.body, decoder)
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    }
    status -> Error(ApiError(status, "Search failed: " <> resp.body))
  }
}

/// POST /collections/{name}/points/delete — delete by field match
pub fn delete_by_field(
  base_url: String,
  collection: String,
  field: String,
  value: String,
) -> Result(Nil, QdrantError) {
  let url =
    base_url <> "/collections/" <> collection <> "/points/delete"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let body =
    json.object([#("filter", match_filter(field, value))])
    |> json.to_string
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(body)
    |> request.set_header("content-type", "application/json")
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status ->
      Error(ApiError(status, "Failed to delete by field: " <> resp.body))
  }
}

/// POST /collections/{name}/points/scroll — scroll points with optional filter
pub fn scroll(
  base_url: String,
  collection: String,
  filter: Option(json.Json),
  limit: Int,
) -> Result(List(ScrollPoint), QdrantError) {
  let url =
    base_url <> "/collections/" <> collection <> "/points/scroll"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let base_fields = [
    #("limit", json.int(limit)),
    #("with_payload", json.bool(True)),
  ]
  let fields = case filter {
    option.None -> base_fields
    option.Some(f) -> list.append(base_fields, [#("filter", f)])
  }
  let body = json.object(fields) |> json.to_string
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(body)
    |> request.set_header("content-type", "application/json")
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> {
      let point_decoder = {
        use id <- decode.field("id", decode.string)
        use payload <- decode.field("payload", decode.dynamic)
        decode.success(ScrollPoint(id: id, payload: payload))
      }
      let decoder =
        decode.at(["result", "points"], decode.list(point_decoder))
      json.parse(resp.body, decoder)
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    }
    status -> Error(ApiError(status, "Scroll failed: " <> resp.body))
  }
}

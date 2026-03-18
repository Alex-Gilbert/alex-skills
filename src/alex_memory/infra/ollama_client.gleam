import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type OllamaError {
  ConnectionError(String)
  ApiError(String)
  ModelNotFound(String)
}

/// GET /api/tags — returns Ok(Nil) if Ollama is reachable
pub fn health_check(base_url: String) -> Result(Nil, OllamaError) {
  let url = base_url <> "/api/tags"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status ->
      Error(ApiError("Unexpected status " <> string.inspect(status)))
  }
}

/// GET /api/tags — returns Ok(True) if the model name appears in the list
pub fn model_exists(
  base_url: String,
  model: String,
) -> Result(Bool, OllamaError) {
  let url = base_url <> "/api/tags"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> {
      let decoder =
        decode.at(["models"], decode.list(decode.at(["name"], decode.string)))
      use models <- result.try(
        json.parse(resp.body, decoder)
        |> result.map_error(fn(e) { ApiError(string.inspect(e)) }),
      )
      Ok(list.any(models, fn(m) { string.contains(m, model) }))
    }
    status ->
      Error(ApiError("Unexpected status " <> string.inspect(status)))
  }
}

/// POST /api/pull with {"name": model}
pub fn pull_model(base_url: String, model: String) -> Result(Nil, OllamaError) {
  let url = base_url <> "/api/pull"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let body = json.object([#("name", json.string(model))]) |> json.to_string
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
    404 -> Error(ModelNotFound(model))
    status ->
      Error(ApiError("Unexpected status " <> string.inspect(status)))
  }
}

/// POST /api/embed with {"model": model, "input": text}
/// Returns the first embedding vector from the response
pub fn embed(
  base_url: String,
  model: String,
  text: String,
) -> Result(List(Float), OllamaError) {
  let url = base_url <> "/api/embed"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  let body =
    json.object([#("model", json.string(model)), #("input", json.string(text))])
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
    200 -> {
      let decoder =
        decode.at(["embeddings"], decode.list(decode.list(decode.float)))
      use embeddings <- result.try(
        json.parse(resp.body, decoder)
        |> result.map_error(fn(e) { ApiError(string.inspect(e)) }),
      )
      case embeddings {
        [first, ..] -> Ok(first)
        [] -> Error(ApiError("Empty embeddings list in response"))
      }
    }
    404 -> Error(ModelNotFound(model))
    status ->
      Error(ApiError("Unexpected status " <> string.inspect(status)))
  }
}

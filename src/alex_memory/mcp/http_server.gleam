import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import alex_memory/mcp/author
import alex_memory/mcp/server
import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import mist

/// Start the HTTP REST server on the configured port.
/// Mist runs its accept loop in a background OTP supervisor — this returns immediately.
pub fn start(
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> Result(Nil, String) {
  let default_author = config.http.default_author

  let handler = fn(req: request.Request(mist.Connection)) {
    // Extract author from X-Author header, fall back to config default
    let req_author =
      request.get_header(req, "x-author")
      |> result.unwrap(default_author)
    author.set(req_author)

    case request.path_segments(req), req.method {
      ["health"], http.Get -> json_response(200, "{\"status\":\"ok\"}")
      ["memories"], http.Post -> handle_store(req, config, embedder_subject)
      ["memories", "search"], http.Post -> handle_find(req, config)
      ["memories"], http.Get -> handle_list(req, config)
      ["memories"], http.Patch -> handle_update(req, config)
      ["memories", "reindex"], http.Post -> handle_reindex(embedder_subject)
      ["memories", ..path_rest], http.Get ->
        handle_read(config, string.join(path_rest, "/"))
      _, _ -> text_response(404, "not found")
    }
  }

  let port = config.http.port
  io.println_error(
    "HTTP REST server starting on port " <> string.inspect(port) <> "...",
  )

  case
    mist.new(handler)
    |> mist.bind("0.0.0.0")
    |> mist.port(port)
    |> mist.start
  {
    Ok(_) -> {
      io.println_error(
        "HTTP REST server listening on port " <> string.inspect(port),
      )
      Ok(Nil)
    }
    Error(e) -> {
      io.println_error("Failed to start HTTP server: " <> string.inspect(e))
      Error("Failed to start HTTP server")
    }
  }
}

// ---------- Route handlers ----------

fn handle_store(
  req: request.Request(mist.Connection),
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> response.Response(mist.ResponseData) {
  case read_json_body(req, server.decode_store_args()) {
    Error(msg) -> text_response(400, msg)
    Ok(args) ->
      case server.handle_store(config, embedder_subject, args) {
        Ok(msg) -> text_response(200, msg)
        Error(msg) -> text_response(500, msg)
      }
  }
}

fn handle_find(
  req: request.Request(mist.Connection),
  config: Config,
) -> response.Response(mist.ResponseData) {
  case read_json_body(req, server.decode_find_args()) {
    Error(msg) -> text_response(400, msg)
    Ok(args) ->
      case server.handle_find(config, args) {
        Ok(toon_body) -> toon_response(200, toon_body)
        Error(msg) -> text_response(500, msg)
      }
  }
}

fn handle_list(
  req: request.Request(mist.Connection),
  config: Config,
) -> response.Response(mist.ResponseData) {
  let query_params =
    request.get_query(req)
    |> result.unwrap([])

  let get_param = fn(key: String) -> option.Option(String) {
    list.find(query_params, fn(pair) { pair.0 == key })
    |> result.map(fn(pair) { pair.1 })
    |> option.from_result
  }

  let args =
    server.ListArgs(
      type_: get_param("type"),
      status: get_param("status"),
      tags: case get_param("tags") {
        None -> None
        Some(t) -> Some(string.split(t, ","))
      },
      author: get_param("author"),
    )

  case server.handle_list(config, args) {
    Ok(toon_body) -> toon_response(200, toon_body)
    Error(msg) -> text_response(500, msg)
  }
}

fn handle_update(
  req: request.Request(mist.Connection),
  config: Config,
) -> response.Response(mist.ResponseData) {
  case read_json_body(req, server.decode_update_args()) {
    Error(msg) -> text_response(400, msg)
    Ok(args) ->
      case server.handle_update(config, args) {
        Ok(msg) -> text_response(200, msg)
        Error(msg) -> text_response(500, msg)
      }
  }
}

fn handle_reindex(
  embedder_subject: Subject(embedder.Message),
) -> response.Response(mist.ResponseData) {
  case server.handle_reindex(embedder_subject) {
    Ok(msg) -> text_response(200, msg)
    Error(msg) -> text_response(500, msg)
  }
}

fn handle_read(
  config: Config,
  vault_path: String,
) -> response.Response(mist.ResponseData) {
  case server.handle_read(config, vault_path) {
    Ok(content) -> markdown_response(200, content)
    Error(_msg) -> text_response(404, "not found")
  }
}

// ---------- Body reading helpers ----------

fn read_json_body(
  req: request.Request(mist.Connection),
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  case mist.read_body(req, 1_000_000) {
    Error(_) -> Error("Failed to read request body")
    Ok(req_with_body) ->
      case bit_array.to_string(req_with_body.body) {
        Error(_) -> Error("Invalid UTF-8 body")
        Ok(body_string) ->
          json.parse(body_string, decoder)
          |> result.map_error(fn(_) { "Invalid JSON body" })
      }
  }
}

// ---------- Response helpers ----------

fn text_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/plain")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn json_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn toon_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/toon")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn markdown_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/markdown")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

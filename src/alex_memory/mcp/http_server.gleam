import alex_memory/config.{type Config}
import gleam/bytes_tree
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/string
import mcp_toolkit
import mcp_toolkit/transport/rpc
import mcp_toolkit/transport/sse
import mist

/// Start the HTTP MCP server on the configured port.
/// Mist runs its accept loop in a background OTP supervisor — this returns immediately.
pub fn start(
  config: Config,
  server: mcp_toolkit.Server,
) -> Result(Nil, String) {
  let registry = sse.start_registry()

  let handler = fn(req: request.Request(mist.Connection)) {
    case request.path_segments(req) {
      ["sse"] -> sse.handle_sse(req, registry, server)
      ["mcp"] -> rpc.handle_http_rpc(req, server, 1_000_000)
      ["health"] -> health_response()
      _ -> not_found_response()
    }
  }

  let port = config.mcp.http_port
  io.println_error(
    "HTTP MCP server starting on port " <> string.inspect(port) <> "...",
  )

  case
    mist.new(handler)
    |> mist.bind("0.0.0.0")
    |> mist.port(port)
    |> mist.start
  {
    Ok(_) -> {
      io.println_error(
        "HTTP MCP server listening on port " <> string.inspect(port),
      )
      Ok(Nil)
    }
    Error(e) -> {
      io.println_error("Failed to start HTTP server: " <> string.inspect(e))
      Error("Failed to start HTTP server")
    }
  }
}

fn health_response() -> response.Response(mist.ResponseData) {
  response.new(200)
  |> response.set_header("Content-Type", "application/json")
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("{\"status\":\"ok\"}")),
  )
}

fn not_found_response() -> response.Response(mist.ResponseData) {
  response.new(404)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("Not found")),
  )
}

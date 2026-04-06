import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type VikunjaError {
  ConnectionError(String)
  ApiError(Int, String)
}

pub type Project {
  Project(id: Int, title: String, description: String)
}

pub type Task {
  Task(
    id: Int,
    title: String,
    description: String,
    done: Bool,
    priority: Int,
    project_id: Int,
  )
}

pub type Label {
  Label(id: Int, title: String)
}

// ---------- Request helper ----------

fn auth_request(
  url: String,
  api_token: String,
  method: http.Method,
) -> Result(request.Request(String), VikunjaError) {
  request.to(url)
  |> result.map(fn(req) {
    req
    |> request.set_method(method)
    |> request.set_header("authorization", "Bearer " <> api_token)
    |> request.set_header("content-type", "application/json")
  })
  |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) })
}

// ---------- Decoders ----------

fn project_decoder() -> decode.Decoder(Project) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field(
    "description",
    "",
    decode.string,
  )
  decode.success(Project(id: id, title: title, description: description))
}

fn task_decoder() -> decode.Decoder(Task) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field(
    "description",
    "",
    decode.string,
  )
  use done <- decode.field("done", decode.bool)
  use priority <- decode.optional_field("priority", 0, decode.int)
  use project_id <- decode.field("project_id", decode.int)
  decode.success(Task(
    id: id,
    title: title,
    description: description,
    done: done,
    priority: priority,
    project_id: project_id,
  ))
}

fn label_decoder() -> decode.Decoder(Label) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  decode.success(Label(id: id, title: title))
}

// ---------- Public API ----------

/// GET /api/v1/info — confirms Vikunja is reachable
pub fn health_check(
  base_url: String,
  api_token: String,
) -> Result(Nil, VikunjaError) {
  use req <- result.try(auth_request(
    base_url <> "/api/v1/info",
    api_token,
    http.Get,
  ))
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status -> Error(ApiError(status, resp.body))
  }
}

/// GET /api/v1/projects
pub fn list_projects(
  base_url: String,
  api_token: String,
) -> Result(List(Project), VikunjaError) {
  use req <- result.try(auth_request(
    base_url <> "/api/v1/projects",
    api_token,
    http.Get,
  ))
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 ->
      json.parse(resp.body, decode.list(project_decoder()))
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

/// PUT /api/v1/projects
pub fn create_project(
  base_url: String,
  api_token: String,
  title: String,
  description: String,
) -> Result(Project, VikunjaError) {
  use req <- result.try(auth_request(
    base_url <> "/api/v1/projects",
    api_token,
    http.Put,
  ))
  let body =
    json.object([
      #("title", json.string(title)),
      #("description", json.string(description)),
    ])
    |> json.to_string
  let req = request.set_body(req, body)
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 | 201 ->
      json.parse(resp.body, project_decoder())
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

/// GET /api/v1/projects/{project_id}/tasks
pub fn list_tasks(
  base_url: String,
  api_token: String,
  project_id: Int,
) -> Result(List(Task), VikunjaError) {
  let url =
    base_url
    <> "/api/v1/projects/"
    <> int.to_string(project_id)
    <> "/tasks"
  use req <- result.try(auth_request(url, api_token, http.Get))
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 ->
      json.parse(resp.body, decode.list(task_decoder()))
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

/// PUT /api/v1/projects/{project_id}/tasks
pub fn create_task(
  base_url: String,
  api_token: String,
  project_id: Int,
  title: String,
  description: String,
  priority: Option(Int),
) -> Result(Task, VikunjaError) {
  let url =
    base_url
    <> "/api/v1/projects/"
    <> int.to_string(project_id)
    <> "/tasks"
  use req <- result.try(auth_request(url, api_token, http.Put))
  let fields = [
    #("title", json.string(title)),
    #("description", json.string(description)),
  ]
  let fields = case priority {
    Some(p) -> [#("priority", json.int(p)), ..fields]
    None -> fields
  }
  let req = request.set_body(req, json.object(fields) |> json.to_string)
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 | 201 ->
      json.parse(resp.body, task_decoder())
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

/// POST /api/v1/projects/{project_id}/tasks/{task_id}
pub fn update_task(
  base_url: String,
  api_token: String,
  project_id: Int,
  task_id: Int,
  title: Option(String),
  description: Option(String),
  done: Option(Bool),
  priority: Option(Int),
) -> Result(Task, VikunjaError) {
  let url =
    base_url
    <> "/api/v1/projects/"
    <> int.to_string(project_id)
    <> "/tasks/"
    <> int.to_string(task_id)
  use req <- result.try(auth_request(url, api_token, http.Post))
  let fields = []
  let fields = case title {
    Some(t) -> [#("title", json.string(t)), ..fields]
    None -> fields
  }
  let fields = case description {
    Some(d) -> [#("description", json.string(d)), ..fields]
    None -> fields
  }
  let fields = case done {
    Some(d) -> [#("done", json.bool(d)), ..fields]
    None -> fields
  }
  let fields = case priority {
    Some(p) -> [#("priority", json.int(p)), ..fields]
    None -> fields
  }
  let req = request.set_body(req, json.object(fields) |> json.to_string)
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 ->
      json.parse(resp.body, task_decoder())
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

/// GET /api/v1/labels
pub fn list_labels(
  base_url: String,
  api_token: String,
) -> Result(List(Label), VikunjaError) {
  use req <- result.try(auth_request(
    base_url <> "/api/v1/labels",
    api_token,
    http.Get,
  ))
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 ->
      json.parse(resp.body, decode.list(label_decoder()))
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

/// PUT /api/v1/labels
pub fn create_label(
  base_url: String,
  api_token: String,
  title: String,
) -> Result(Label, VikunjaError) {
  use req <- result.try(auth_request(
    base_url <> "/api/v1/labels",
    api_token,
    http.Put,
  ))
  let body =
    json.object([#("title", json.string(title))])
    |> json.to_string
  let req = request.set_body(req, body)
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { ConnectionError(string.inspect(e)) }),
  )
  case resp.status {
    200 | 201 ->
      json.parse(resp.body, label_decoder())
      |> result.map_error(fn(e) { ApiError(200, string.inspect(e)) })
    status -> Error(ApiError(status, resp.body))
  }
}

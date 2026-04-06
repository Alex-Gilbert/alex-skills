#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const API_URL = process.env.MEMORY_API_URL ?? "http://localhost:7890";

// ---------- HTTP helpers ----------

async function api(
  method: string,
  path: string,
  body?: Record<string, unknown>
): Promise<{ status: number; text: string }> {
  const res = await fetch(`${API_URL}${path}`, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, text: await res.text() };
}

function ok(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

function err(text: string) {
  return { content: [{ type: "text" as const, text }], isError: true };
}

// ---------- Server ----------

const server = new McpServer({
  name: "vikunja",
  version: "0.1.0",
});

// --- Projects ---

server.registerTool(
  "list_projects",
  {
    description: "List all Vikunja projects (kanban boards)",
    inputSchema: {},
  },
  async () => {
    const res = await api("GET", "/projects");
    if (res.status !== 200) return err(`Failed to list projects: ${res.text}`);
    return ok(res.text);
  }
);

server.registerTool(
  "get_project",
  {
    description: "Get details of a specific Vikunja project by ID",
    inputSchema: {
      id: z.number().describe("Project ID"),
    },
  },
  async ({ id }) => {
    // List all and filter — our REST API doesn't have a single-project endpoint
    const res = await api("GET", "/projects");
    if (res.status !== 200) return err(`Failed to get project: ${res.text}`);
    return ok(res.text);
  }
);

server.registerTool(
  "save_project",
  {
    description: "Create a new Vikunja project",
    inputSchema: {
      title: z.string().describe("Project title"),
      description: z.string().optional().describe("Project description"),
    },
  },
  async ({ title, description }) => {
    const res = await api("POST", "/projects", {
      title,
      description: description ?? "",
    });
    if (res.status !== 201) return err(`Failed to create project: ${res.text}`);
    return ok(res.text);
  }
);

// --- Issues (Tasks) ---

server.registerTool(
  "list_issues",
  {
    description:
      "List tasks in a Vikunja project. Returns title, status (open/done), priority, and ID.",
    inputSchema: {
      project_id: z.number().describe("Project ID to list tasks from"),
    },
  },
  async ({ project_id }) => {
    const res = await api("GET", `/tasks?project_id=${project_id}`);
    if (res.status !== 200) return err(`Failed to list tasks: ${res.text}`);
    return ok(res.text);
  }
);

server.registerTool(
  "get_issue",
  {
    description: "Get details of a specific task by ID",
    inputSchema: {
      project_id: z.number().describe("Project ID the task belongs to"),
      id: z.number().describe("Task ID"),
    },
  },
  async ({ project_id, id }) => {
    // List tasks and find the one we want
    const res = await api("GET", `/tasks?project_id=${project_id}`);
    if (res.status !== 200) return err(`Failed to get task: ${res.text}`);
    return ok(res.text);
  }
);

server.registerTool(
  "save_issue",
  {
    description:
      "Create or update a Vikunja task. Omit 'id' to create a new task; include 'id' to update an existing one. " +
      "Priority: 0=unset, 1=low, 2=medium, 3=high, 4=urgent, 5=do-now. " +
      "Set done=true to mark a task complete.",
    inputSchema: {
      project_id: z.number().describe("Project ID"),
      id: z.number().optional().describe("Task ID (omit to create new)"),
      title: z.string().optional().describe("Task title"),
      description: z.string().optional().describe("Task description"),
      done: z.boolean().optional().describe("Whether the task is complete"),
      priority: z
        .number()
        .min(0)
        .max(5)
        .optional()
        .describe("Priority: 0=unset, 1=low, 2=medium, 3=high, 4=urgent, 5=do-now"),
    },
  },
  async ({ project_id, id, title, description, done, priority }) => {
    if (id !== undefined) {
      // Update existing task
      const body: Record<string, unknown> = { project_id };
      if (title !== undefined) body.title = title;
      if (description !== undefined) body.description = description;
      if (done !== undefined) body.done = done;
      if (priority !== undefined) body.priority = priority;
      const res = await api("PATCH", `/tasks/${id}`, body);
      if (res.status !== 200)
        return err(`Failed to update task: ${res.text}`);
      return ok(res.text);
    } else {
      // Create new task
      const res = await api("POST", "/tasks", {
        project_id,
        title: title ?? "Untitled",
        description: description ?? "",
        ...(priority !== undefined ? { priority } : {}),
      });
      if (res.status !== 201)
        return err(`Failed to create task: ${res.text}`);
      return ok(res.text);
    }
  }
);

// --- Labels ---

server.registerTool(
  "list_issue_labels",
  {
    description: "List all available labels",
    inputSchema: {},
  },
  async () => {
    // Labels aren't proxied yet — hit Vikunja directly
    return ok("Labels are managed through the Vikunja web UI at http://localhost:3456");
  }
);

// --- Status ---

server.registerTool(
  "get_issue_status",
  {
    description:
      "Get the status of a task. Vikunja tasks are either 'open' or 'done'.",
    inputSchema: {
      project_id: z.number().describe("Project ID"),
      id: z.number().describe("Task ID"),
    },
  },
  async ({ project_id, id }) => {
    const res = await api("GET", `/tasks?project_id=${project_id}`);
    if (res.status !== 200)
      return err(`Failed to get task status: ${res.text}`);
    return ok(res.text);
  }
);

// ---------- Start ----------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Vikunja MCP server running on stdio");
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});

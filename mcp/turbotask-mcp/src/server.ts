#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  activityKinds,
  jobPalettes,
  taskCadences,
  taskEnergies,
  taskStatuses,
  type TaskStatus
} from "./types.js";
import {
  appendManualEvent,
  archiveTask,
  createJob,
  createOperation,
  createProject,
  createTask,
  deleteTask,
  findTask,
  flattenTasks,
  mutateWorkspace,
  readWorkspace,
  searchWorkspace,
  setTaskStatus,
  summarizeWorkspace,
  toggleTaskNow,
  updateTask,
  workspacePaths,
  type UpdateTaskPatch,
  WorkspaceError
} from "./workspace.js";

const server = new McpServer({
  name: "turbotask-mcp",
  version: "0.1.0"
});
const registerTool = server.registerTool.bind(server) as unknown as (
  name: string,
  config: { description: string; inputSchema: z.ZodRawShape },
  cb: (args: Record<string, unknown>) => Promise<ReturnType<typeof textResult> | { isError: true; content: ReturnType<typeof textResult>["content"] }>
) => void;

const textResult = (value: unknown) => ({
  content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }]
});

const tool = <T extends z.ZodRawShape>(
  name: string,
  description: string,
  inputSchema: T,
  handler: (args: z.infer<z.ZodObject<T>>) => Promise<unknown> | unknown
) => {
  registerTool(name, { description, inputSchema }, async (args) => {
    try {
      return textResult(await handler(args as z.infer<z.ZodObject<T>>));
    } catch (error) {
      return {
        isError: true,
        content: [{ type: "text" as const, text: formatError(error) }]
      };
    }
  });
};

const noInput = {};
const uuidString = z.string().min(1).describe("Turbotask UUID string.");
const maybeUuid = uuidString.nullish();
const statusSchema = z.enum(taskStatuses);
const taskPatchSchema = {
  title: z.string().min(1).optional(),
  summary: z.string().optional(),
  why: z.string().optional(),
  status: statusSchema.optional(),
  energy: z.enum(taskEnergies).optional(),
  cadence: z.enum(taskCadences).optional(),
  progress: z.number().min(0).max(1).optional(),
  estimatedMinutes: z.number().int().min(1).max(1440).optional(),
  isScheduledNow: z.boolean().optional(),
  priority: z.number().int().min(1).max(5).optional(),
  waitingOn: z.string().nullable().optional(),
  nextStep: z.string().optional(),
  repeatEveryMinutes: z.number().int().positive().nullable().optional(),
  kpiTarget: z.number().int().positive().nullable().optional(),
  kpiUnit: z.string().nullable().optional(),
  kpiRoundsRemaining: z.number().int().min(0).nullable().optional(),
  kpiCount: z.number().int().min(0).optional(),
  nextAvailableAt: z.string().datetime({ offset: true }).nullable().optional(),
  toolBundleIDs: z.array(z.string()).max(12).optional(),
  startDate: z.string().datetime({ offset: true }).nullable().optional(),
  endDate: z.string().datetime({ offset: true }).nullable().optional(),
  isArchived: z.boolean().optional(),
  blockedByTaskIDs: z.array(uuidString).max(24).optional()
};

registerResource("workspace", "turbotask://workspace", "Complete Turbotask workspace JSON.", async () => {
  return readWorkspace();
});

registerResource("now-tasks", "turbotask://tasks/now", "Current non-archived tasks scheduled for Now.", async () => {
  const workspace = await readWorkspace();
  return flattenTasks(workspace, false)
    .filter((ctx) => ctx.task.isScheduledNow)
    .sort((a, b) => a.task.nowOrder - b.task.nowOrder);
});

registerResource("all-tasks", "turbotask://tasks/all", "All tasks with job/project/operation context.", async () => {
  const workspace = await readWorkspace();
  return flattenTasks(workspace);
});

registerResource("recent-history", "turbotask://history/recent", "Most recent Turbotask activity events.", async () => {
  const workspace = await readWorkspace();
  return workspace.history.slice(0, 100);
});

tool("workspace_status", "Return workspace file paths and object counts.", noInput, async () => {
  const workspace = await readWorkspace();
  return { paths: workspacePaths(), counts: summarizeWorkspace(workspace) };
});

tool(
  "read_workspace",
  "Return a full or summarized Turbotask workspace snapshot.",
  {
    full: z.boolean().default(false).describe("When true, return full workspace JSON. Otherwise return counts and recent/now slices.")
  },
  async ({ full }) => {
    const workspace = await readWorkspace();
    if (full) return workspace;
    const tasks = flattenTasks(workspace);
    return {
      counts: summarizeWorkspace(workspace),
      jobs: workspace.jobs.map(({ id, title, summary, palette, projects, operations, jobTasks }) => ({
        id,
        title,
        summary,
        palette,
        projectCount: projects.length,
        operationCount: operations.length,
        jobTaskCount: jobTasks.length
      })),
      nowTasks: tasks.filter((ctx) => ctx.task.isScheduledNow && !ctx.task.isArchived),
      recentHistory: workspace.history.slice(0, 25)
    };
  }
);

tool("list_jobs", "List Turbotask fields/jobs.", noInput, async () => {
  const workspace = await readWorkspace();
  return workspace.jobs;
});

tool("list_projects", "List projects, optionally filtered by job.", { jobID: maybeUuid }, async ({ jobID }) => {
  const workspace = await readWorkspace();
  return workspace.jobs
    .filter((job) => !jobID || job.id === jobID)
    .flatMap((job) => job.projects.map((project) => ({ ...project, jobID: job.id, jobTitle: job.title })));
});

tool("list_operations", "List ongoing operations, optionally filtered by job.", { jobID: maybeUuid }, async ({ jobID }) => {
  const workspace = await readWorkspace();
  return workspace.jobs
    .filter((job) => !jobID || job.id === jobID)
    .flatMap((job) => job.operations.map((operation) => ({ ...operation, jobID: job.id, jobTitle: job.title })));
});

tool(
  "list_tasks",
  "List tasks with container context and optional filters.",
  {
    jobID: maybeUuid,
    projectID: maybeUuid,
    operationID: maybeUuid,
    status: statusSchema.nullish(),
    onlyNow: z.boolean().default(false),
    includeArchived: z.boolean().default(false),
    query: z.string().optional()
  },
  async ({ jobID, projectID, operationID, status, onlyNow, includeArchived, query }) => {
    const workspace = await readWorkspace();
    const needle = query?.trim().toLocaleLowerCase();
    return flattenTasks(workspace, includeArchived)
      .filter((ctx) => !jobID || ctx.jobID === jobID)
      .filter((ctx) => !projectID || ctx.projectID === projectID)
      .filter((ctx) => !operationID || ctx.operationID === operationID)
      .filter((ctx) => !status || ctx.task.status === status)
      .filter((ctx) => !onlyNow || ctx.task.isScheduledNow)
      .filter((ctx) => !needle || [ctx.task.title, ctx.task.summary, ctx.task.why, ctx.task.nextStep].join(" ").toLocaleLowerCase().includes(needle))
      .sort((a, b) => a.task.nowOrder - b.task.nowOrder || b.task.priority - a.task.priority);
  }
);

tool("get_task", "Get one task by ID, including its container context.", { taskID: uuidString }, async ({ taskID }) => {
  const workspace = await readWorkspace();
  const task = findTask(workspace, taskID);
  if (!task) throw new WorkspaceError(`Task not found: ${taskID}`, "NOT_FOUND");
  return task;
});

tool(
  "create_job",
  "Create a Turbotask field/job.",
  {
    title: z.string().min(1),
    summary: z.string().default(""),
    palette: z.enum(jobPalettes).default("forest")
  },
  async (input) => mutateWorkspace((workspace) => createJob(workspace, input))
);

tool(
  "create_project",
  "Create a project inside a field/job.",
  {
    jobID: uuidString,
    title: z.string().min(1),
    outcome: z.string().default(""),
    iconEmoji: z.string().default("")
  },
  async (input) => mutateWorkspace((workspace) => createProject(workspace, input))
);

tool(
  "create_operation",
  "Create an ongoing operation inside a field/job.",
  {
    jobID: uuidString,
    title: z.string().min(1),
    summary: z.string().default("")
  },
  async (input) => mutateWorkspace((workspace) => createOperation(workspace, input))
);

tool(
  "create_task",
  "Create a task in the inbox, a field, a project, or an operation.",
  {
    title: z.string().min(1),
    summary: z.string().default(""),
    why: z.string().default(""),
    status: statusSchema.default("queued"),
    energy: z.enum(taskEnergies).default("deepFocus"),
    cadence: z.enum(taskCadences).default("oneOff"),
    isScheduledNow: z.boolean().default(false),
    estimatedMinutes: z.number().int().min(1).max(1440).default(30),
    priority: z.number().int().min(1).max(5).default(3),
    nextStep: z.string().default(""),
    waitingOn: z.string().nullable().optional(),
    repeatEveryMinutes: z.number().int().positive().nullable().optional(),
    kpiTarget: z.number().int().positive().nullable().optional(),
    kpiUnit: z.string().nullable().optional(),
    kpiRoundsRemaining: z.number().int().min(0).nullable().optional(),
    toolBundleIDs: z.array(z.string()).max(12).default([]),
    startDate: z.string().datetime({ offset: true }).nullable().optional(),
    endDate: z.string().datetime({ offset: true }).nullable().optional(),
    jobID: maybeUuid,
    projectID: maybeUuid,
    operationID: maybeUuid
  },
  async (input) => mutateWorkspace((workspace) => createTask(workspace, input))
);

tool(
  "update_task",
  "Patch editable task fields. Use set_task_status for status changes that should journal activity.",
  {
    taskID: uuidString,
    patch: z.object(taskPatchSchema).strict()
  },
  async ({ taskID, patch }) => mutateWorkspace((workspace) => updateTask(workspace, taskID, patch as UpdateTaskPatch))
);

tool(
  "set_task_status",
  "Set task status and add the corresponding activity history event.",
  {
    taskID: uuidString,
    status: statusSchema,
    detail: z.string().optional()
  },
  async ({ taskID, status, detail }) =>
    mutateWorkspace((workspace) => setTaskStatus(workspace, taskID, status as TaskStatus, detail))
);

tool(
  "toggle_task_now",
  "Add or remove a task from the Now list.",
  {
    taskID: uuidString,
    scheduled: z.boolean().optional()
  },
  async ({ taskID, scheduled }) => mutateWorkspace((workspace) => toggleTaskNow(workspace, taskID, scheduled))
);

tool(
  "archive_task",
  "Archive or restore a task. Archiving removes it from Now.",
  {
    taskID: uuidString,
    archived: z.boolean().default(true)
  },
  async ({ taskID, archived }) => mutateWorkspace((workspace) => archiveTask(workspace, taskID, archived))
);

tool("delete_task", "Delete a task and its activity history entries.", { taskID: uuidString }, async ({ taskID }) =>
  mutateWorkspace((workspace) => deleteTask(workspace, taskID))
);

tool(
  "log_activity",
  "Append a manual activity event, optionally attached to a task.",
  {
    kind: z.enum(activityKinds),
    detail: z.string().min(1),
    taskID: maybeUuid,
    focusRating: z.number().int().min(1).max(5).nullable().optional(),
    qualityRating: z.number().int().min(1).max(5).nullable().optional(),
    sessionMinutes: z.number().int().positive().nullable().optional()
  },
  async (input) => mutateWorkspace((workspace) => appendManualEvent(workspace, input))
);

tool("search_workspace", "Search fields, projects, operations, and tasks.", { query: z.string().min(1) }, async ({ query }) => {
  const workspace = await readWorkspace();
  return searchWorkspace(workspace, query);
});

server.registerPrompt(
  "daily_plan",
  {
    description: "Plan today's Turbotask work from Now tasks and open high-priority work.",
    argsSchema: {
      focusMinutes: z.string().optional().describe("Available focus minutes for the plan.")
    }
  },
  async ({ focusMinutes }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: [
            "Use Turbotask MCP resources and tools to build a practical plan for today.",
            "Start from turbotask://tasks/now, then inspect high-priority queued work if capacity remains.",
            focusMinutes ? `Available focus minutes: ${focusMinutes}.` : "Ask for capacity only if it materially changes the plan.",
            "Return a concise sequence of tasks with status changes you recommend before making any write."
          ].join("\n")
        }
      }
    ]
  })
);

server.registerPrompt(
  "task_breakdown",
  {
    description: "Break a selected Turbotask task into clearer next steps.",
    argsSchema: {
      taskID: z.string().describe("Task UUID to inspect and break down.")
    }
  },
  async ({ taskID }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: [
            `Inspect task ${taskID} with get_task.`,
            "Propose a tighter title, next step, estimate, dependencies, and whether it belongs in Now.",
            "Do not update the workspace until the user approves the exact patch."
          ].join("\n")
        }
      }
    ]
  })
);

function registerResource(name: string, uri: string, description: string, reader: () => Promise<unknown>) {
  server.registerResource(name, uri, { description, mimeType: "application/json" }, async () => ({
    contents: [{ uri, mimeType: "application/json", text: JSON.stringify(await reader(), null, 2) }]
  }));
}

function formatError(error: unknown): string {
  if (error instanceof WorkspaceError) return `${error.code}: ${error.message}`;
  return error instanceof Error ? error.message : String(error);
}

const transport = new StdioServerTransport();
await server.connect(transport);

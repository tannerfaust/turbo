import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  createJob,
  createProject,
  createTask,
  defaultWorkspace,
  flattenTasks,
  mutateWorkspace,
  nowIso,
  readWorkspace,
  setTaskStatus,
  workspacePaths
} from "./workspace.js";

let tempDir: string;

beforeEach(async () => {
  tempDir = await mkdtemp(path.join(os.tmpdir(), "turbotask-mcp-"));
  process.env.TURBOTASK_APP_SUPPORT_DIR = tempDir;
  delete process.env.TURBOTASK_WORKSPACE;
});

afterEach(async () => {
  delete process.env.TURBOTASK_APP_SUPPORT_DIR;
  delete process.env.TURBOTASK_WORKSPACE;
  await rm(tempDir, { recursive: true, force: true });
});

describe("workspace persistence", () => {
  it("creates a Swift-compatible default workspace when mutating an empty store", async () => {
    const job = await mutateWorkspace((workspace) => createJob(workspace, { title: "Client Work", palette: "ocean" }));

    const workspace = await readWorkspace();
    expect(job.title).toBe("Client Work");
    expect(workspace.jobs).toHaveLength(1);
    expect(workspace.tasksPresentation.visibleFields).toContain("status");

    const raw = await readFile(workspacePaths().primary, "utf8");
    expect(raw).toContain('"jobs"');
    expect(raw).not.toContain(".000Z");
  });

  it("creates tasks in projects and journals status changes", async () => {
    const taskContext = await mutateWorkspace((workspace) => {
      const job = createJob(workspace, { title: "Product", palette: "forest" });
      const project = createProject(workspace, { jobID: job.id, title: "Launch", outcome: "Ship v1" });
      return createTask(workspace, {
        jobID: job.id,
        projectID: project.id,
        title: "Draft launch plan",
        isScheduledNow: true,
        priority: 5,
        estimatedMinutes: 45
      });
    });

    await mutateWorkspace((workspace) => setTaskStatus(workspace, taskContext.task.id, "active"));

    const workspace = await readWorkspace();
    const [task] = flattenTasks(workspace);
    expect(task.task.status).toBe("active");
    expect(task.task.isScheduledNow).toBe(true);
    expect(workspace.history[0]?.kind).toBe("started");
    expect(workspace.history[0]?.taskTitle).toBe("Draft launch plan");
  });

  it("formats dates without fractional seconds for Swift JSONDecoder.iso8601", () => {
    expect(nowIso()).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    expect(defaultWorkspace().focusOverlayPresenceMode).toBe("allDesktops");
  });
});

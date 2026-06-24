import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import type {
  ActivityEvent,
  ActivityKind,
  Job,
  JobPalette,
  Operation,
  Project,
  Task,
  TaskCadence,
  TaskContext,
  TaskEnergy,
  TaskStatus,
  WorkspaceSnapshot
} from "./types.js";

export class WorkspaceError extends Error {
  constructor(
    message: string,
    readonly code: string
  ) {
    super(message);
  }
}

export interface WorkspacePaths {
  directory: string;
  primary: string;
  backup: string;
}

export interface CreateTaskInput {
  title: string;
  summary?: string;
  why?: string;
  status?: TaskStatus;
  energy?: TaskEnergy;
  cadence?: TaskCadence;
  isScheduledNow?: boolean;
  estimatedMinutes?: number;
  priority?: number;
  nextStep?: string;
  waitingOn?: string | null;
  repeatEveryMinutes?: number | null;
  kpiTarget?: number | null;
  kpiUnit?: string | null;
  kpiRoundsRemaining?: number | null;
  toolBundleIDs?: string[];
  startDate?: string | null;
  endDate?: string | null;
  jobID?: string | null;
  projectID?: string | null;
  operationID?: string | null;
}

export interface UpdateTaskPatch {
  title?: string;
  summary?: string;
  why?: string;
  status?: TaskStatus;
  energy?: TaskEnergy;
  cadence?: TaskCadence;
  progress?: number;
  estimatedMinutes?: number;
  isScheduledNow?: boolean;
  priority?: number;
  waitingOn?: string | null;
  nextStep?: string;
  repeatEveryMinutes?: number | null;
  kpiTarget?: number | null;
  kpiUnit?: string | null;
  kpiRoundsRemaining?: number | null;
  kpiCount?: number;
  nextAvailableAt?: string | null;
  toolBundleIDs?: string[];
  startDate?: string | null;
  endDate?: string | null;
  isArchived?: boolean;
  blockedByTaskIDs?: string[];
}

export function workspacePaths(): WorkspacePaths {
  if (process.env.TURBOTASK_WORKSPACE) {
    const primary = path.resolve(process.env.TURBOTASK_WORKSPACE);
    return {
      directory: path.dirname(primary),
      primary,
      backup: path.join(path.dirname(primary), "workspace.backup.json")
    };
  }

  const directory = process.env.TURBOTASK_APP_SUPPORT_DIR
    ? path.resolve(process.env.TURBOTASK_APP_SUPPORT_DIR)
    : path.join(os.homedir(), "Library", "Application Support", "TurboTasker");

  return {
    directory,
    primary: path.join(directory, "workspace.json"),
    backup: path.join(directory, "workspace.backup.json")
  };
}

export function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function newID(): string {
  return crypto.randomUUID().toUpperCase();
}

export function defaultWorkspace(): WorkspaceSnapshot {
  return {
    jobs: [],
    standaloneTasks: [],
    history: [],
    dailyCapacityMinutes: 540,
    dayBatteryStartMinutes: 480,
    dayBatteryEndMinutes: 0,
    dayBatteryShowsPercentageInMenuBar: true,
    dayBatteryUsesWideMenuBarItem: false,
    taskAutoArchiveAfterIdleHours: 0,
    doneTaskAutoArchiveAfterDays: 0,
    archivedTaskPurgeAfterDays: 0,
    tasksPresentation: {
      viewMode: "table",
      visibleFields: ["energy", "estimate", "nextStep", "now", "priority", "progress", "project", "status"]
    },
    themeMode: "system",
    nowPinnedJobIDs: [],
    nowSuppressedJobIDs: [],
    focusCardDensity: "standard",
    newNowTaskPlacement: "bottom",
    focusOverlayPresenceMode: "allDesktops",
    focusOverlayWindowFrame: null,
    trainingWheelsEnabled: true,
    typeaheadListNavigationEnabled: true
  };
}

export async function readWorkspace({ createIfMissing = false } = {}): Promise<WorkspaceSnapshot> {
  const paths = workspacePaths();
  await fs.mkdir(paths.directory, { recursive: true });

  for (const candidate of [paths.primary, paths.backup]) {
    try {
      const text = await fs.readFile(candidate, "utf8");
      return normalizeWorkspace(JSON.parse(text) as WorkspaceSnapshot);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") continue;
      if (candidate === paths.primary) continue;
      throw new WorkspaceError(`Unable to read Turbotask workspace: ${(error as Error).message}`, "READ_FAILED");
    }
  }

  if (!createIfMissing) {
    throw new WorkspaceError(`No Turbotask workspace found at ${paths.primary}`, "NO_WORKSPACE");
  }

  const snapshot = defaultWorkspace();
  await writeWorkspace(snapshot);
  return snapshot;
}

export async function writeWorkspace(snapshot: WorkspaceSnapshot): Promise<void> {
  const paths = workspacePaths();
  await fs.mkdir(paths.directory, { recursive: true });
  const data = `${stableStringify(normalizeWorkspace(snapshot))}\n`;
  await atomicWrite(paths.primary, data);
  await atomicWrite(paths.backup, data);
}

export async function mutateWorkspace<T>(
  mutator: (snapshot: WorkspaceSnapshot) => T | Promise<T>,
  options: { createIfMissing?: boolean } = {}
): Promise<T> {
  const snapshot = await readWorkspace({ createIfMissing: options.createIfMissing ?? true });
  const result = await mutator(snapshot);
  await writeWorkspace(snapshot);
  return result;
}

export function summarizeWorkspace(snapshot: WorkspaceSnapshot) {
  const tasks = flattenTasks(snapshot);
  return {
    jobs: snapshot.jobs.length,
    projects: snapshot.jobs.reduce((sum, job) => sum + job.projects.length, 0),
    operations: snapshot.jobs.reduce((sum, job) => sum + job.operations.length, 0),
    tasks: tasks.length,
    nowTasks: tasks.filter((ctx) => ctx.task.isScheduledNow && !ctx.task.isArchived).length,
    activeTasks: tasks.filter((ctx) => ctx.task.status === "active" && !ctx.task.isArchived).length,
    archivedTasks: tasks.filter((ctx) => ctx.task.isArchived).length,
    historyEvents: snapshot.history.length
  };
}

export function flattenTasks(snapshot: WorkspaceSnapshot, includeArchived = true): TaskContext[] {
  const contexts: TaskContext[] = [];

  for (const task of snapshot.standaloneTasks ?? []) {
    if (includeArchived || !task.isArchived) {
      contexts.push({
        task,
        jobID: null,
        projectID: null,
        operationID: null,
        jobTitle: "",
        projectTitle: "",
        operationTitle: "",
        containerTitle: "Inbox"
      });
    }
  }

  for (const job of snapshot.jobs ?? []) {
    for (const task of job.jobTasks ?? []) {
      if (includeArchived || !task.isArchived) {
        contexts.push({
          task,
          jobID: job.id,
          projectID: null,
          operationID: null,
          jobTitle: job.title,
          projectTitle: "",
          operationTitle: "",
          containerTitle: job.title
        });
      }
    }

    for (const project of job.projects ?? []) {
      for (const task of project.tasks ?? []) {
        if (includeArchived || !task.isArchived) {
          contexts.push({
            task,
            jobID: job.id,
            projectID: project.id,
            operationID: null,
            jobTitle: job.title,
            projectTitle: project.title,
            operationTitle: "",
            containerTitle: project.title
          });
        }
      }
    }

    for (const operation of job.operations ?? []) {
      for (const task of operation.tasks ?? []) {
        if (includeArchived || !task.isArchived) {
          contexts.push({
            task,
            jobID: job.id,
            projectID: null,
            operationID: operation.id,
            jobTitle: job.title,
            projectTitle: "",
            operationTitle: operation.title,
            containerTitle: operation.title
          });
        }
      }
    }
  }

  return contexts;
}

export function findTask(snapshot: WorkspaceSnapshot, taskID: string): TaskContext | undefined {
  return flattenTasks(snapshot).find((ctx) => ctx.task.id === taskID);
}

export function createJob(snapshot: WorkspaceSnapshot, input: { title: string; summary?: string; palette?: JobPalette }): Job {
  const job: Job = {
    id: newID(),
    title: input.title.trim(),
    summary: input.summary?.trim() ?? "",
    palette: input.palette ?? "forest",
    jobTasks: [],
    projects: [],
    operations: []
  };
  snapshot.jobs.push(job);
  return job;
}

export function createProject(
  snapshot: WorkspaceSnapshot,
  input: { jobID: string; title: string; outcome?: string; iconEmoji?: string }
): Project {
  const job = requireJob(snapshot, input.jobID);
  const project: Project = {
    id: newID(),
    title: input.title.trim(),
    outcome: input.outcome?.trim() ?? "",
    iconEmoji: normalizeIconEmoji(input.iconEmoji),
    tasks: []
  };
  job.projects.push(project);
  return project;
}

export function createOperation(
  snapshot: WorkspaceSnapshot,
  input: { jobID: string; title: string; summary?: string }
): Operation {
  const job = requireJob(snapshot, input.jobID);
  const operation: Operation = {
    id: newID(),
    title: input.title.trim(),
    summary: input.summary?.trim() ?? "",
    isArchived: false,
    archivedAt: null,
    tasks: [],
    cascadeArchivedTaskIDs: []
  };
  job.operations.push(operation);
  return operation;
}

export function createTask(snapshot: WorkspaceSnapshot, input: CreateTaskInput): TaskContext {
  const task: Task = {
    id: newID(),
    title: input.title.trim(),
    summary: input.summary?.trim() ?? "",
    why: input.why?.trim() ?? "",
    energy: input.energy ?? "deepFocus",
    cadence: input.cadence ?? "oneOff",
    status: input.status ?? "queued",
    progress: 0,
    estimatedMinutes: clampInt(input.estimatedMinutes ?? 30, 1, 24 * 60),
    isScheduledNow: input.isScheduledNow ?? false,
    nowOrder: input.isScheduledNow ? nextNowOrder(snapshot) : 0,
    priority: clampInt(input.priority ?? 3, 1, 5),
    waitingOn: emptyToNull(input.waitingOn),
    nextStep: input.nextStep?.trim() ?? "",
    repeatEveryMinutes: input.repeatEveryMinutes ?? null,
    kpiTarget: input.cadence === "kpi" ? input.kpiTarget ?? null : null,
    kpiUnit: input.cadence === "kpi" ? emptyToNull(input.kpiUnit) : null,
    kpiRoundsRemaining: input.cadence === "kpi" ? input.kpiRoundsRemaining ?? null : null,
    kpiCount: 0,
    nextAvailableAt: null,
    toolBundleIDs: normalizeStringList(input.toolBundleIDs, 12),
    startDate: input.startDate ?? null,
    endDate: input.endDate ?? null,
    isArchived: false,
    archivedAt: null,
    blockedByTaskIDs: []
  };

  insertTask(snapshot, task, input.jobID ?? null, input.projectID ?? null, input.operationID ?? null);
  return requireTask(snapshot, task.id);
}

export function updateTask(snapshot: WorkspaceSnapshot, taskID: string, patch: UpdateTaskPatch): TaskContext {
  const context = requireTask(snapshot, taskID);
  const task = context.task;

  if (patch.title !== undefined) task.title = patch.title.trim();
  if (patch.summary !== undefined) task.summary = patch.summary.trim();
  if (patch.why !== undefined) task.why = patch.why.trim();
  if (patch.status !== undefined) task.status = patch.status;
  if (patch.energy !== undefined) task.energy = patch.energy;
  if (patch.cadence !== undefined) task.cadence = patch.cadence;
  if (patch.progress !== undefined) task.progress = Math.max(0, Math.min(1, patch.progress));
  if (patch.estimatedMinutes !== undefined) task.estimatedMinutes = clampInt(patch.estimatedMinutes, 1, 24 * 60);
  if (patch.priority !== undefined) task.priority = clampInt(patch.priority, 1, 5);
  if (patch.waitingOn !== undefined) task.waitingOn = emptyToNull(patch.waitingOn);
  if (patch.nextStep !== undefined) task.nextStep = patch.nextStep.trim();
  if (patch.repeatEveryMinutes !== undefined) task.repeatEveryMinutes = patch.repeatEveryMinutes;
  if (patch.kpiTarget !== undefined) task.kpiTarget = patch.kpiTarget;
  if (patch.kpiUnit !== undefined) task.kpiUnit = emptyToNull(patch.kpiUnit);
  if (patch.kpiRoundsRemaining !== undefined) task.kpiRoundsRemaining = patch.kpiRoundsRemaining;
  if (patch.kpiCount !== undefined) task.kpiCount = Math.max(0, patch.kpiCount);
  if (patch.nextAvailableAt !== undefined) task.nextAvailableAt = patch.nextAvailableAt;
  if (patch.toolBundleIDs !== undefined) task.toolBundleIDs = normalizeStringList(patch.toolBundleIDs, 12);
  if (patch.startDate !== undefined) task.startDate = patch.startDate;
  if (patch.endDate !== undefined) task.endDate = patch.endDate;
  if (patch.blockedByTaskIDs !== undefined) {
    task.blockedByTaskIDs = normalizeStringList(patch.blockedByTaskIDs.filter((id) => id !== task.id), 24);
  }
  if (patch.isScheduledNow !== undefined) {
    task.isScheduledNow = patch.isScheduledNow;
    if (patch.isScheduledNow) {
      task.isArchived = false;
      task.archivedAt = null;
      task.nowOrder = nextNowOrder(snapshot);
    }
  }
  if (patch.isArchived !== undefined) {
    task.isArchived = patch.isArchived;
    task.archivedAt = patch.isArchived ? task.archivedAt ?? nowIso() : null;
    if (patch.isArchived) task.isScheduledNow = false;
  }

  return requireTask(snapshot, taskID);
}

export function setTaskStatus(snapshot: WorkspaceSnapshot, taskID: string, status: TaskStatus, detail?: string): TaskContext {
  const context = requireTask(snapshot, taskID);
  context.task.status = status;
  if (status === "active") {
    context.task.isScheduledNow = true;
    context.task.isArchived = false;
    context.task.archivedAt = null;
    context.task.nowOrder = 0;
    pauseConflictingActiveTasks(snapshot, taskID);
  }
  if (status === "done") {
    context.task.progress = 1;
  }
  appendEvent(snapshot, eventKindForStatus(status), context, detail ?? defaultDetailForStatus(status));
  return context;
}

export function toggleTaskNow(snapshot: WorkspaceSnapshot, taskID: string, scheduled?: boolean): TaskContext {
  const context = requireTask(snapshot, taskID);
  const next = scheduled ?? !context.task.isScheduledNow;
  context.task.isScheduledNow = next;
  if (next) {
    context.task.isArchived = false;
    context.task.archivedAt = null;
    context.task.nowOrder = nextNowOrder(snapshot);
  }
  return context;
}

export function archiveTask(snapshot: WorkspaceSnapshot, taskID: string, archived: boolean): TaskContext {
  return updateTask(snapshot, taskID, { isArchived: archived });
}

export function deleteTask(snapshot: WorkspaceSnapshot, taskID: string): TaskContext {
  const location = taskLocation(snapshot, taskID);
  if (!location) throw new WorkspaceError(`Task not found: ${taskID}`, "NOT_FOUND");
  const [removed] = location.tasks.splice(location.index, 1);
  snapshot.history = snapshot.history.filter((event) => event.taskID !== taskID);
  return location.context(removed);
}

export function appendManualEvent(
  snapshot: WorkspaceSnapshot,
  input: {
    kind: ActivityKind;
    detail: string;
    taskID?: string | null;
    focusRating?: number | null;
    qualityRating?: number | null;
    sessionMinutes?: number | null;
  }
): ActivityEvent {
  const context = input.taskID ? requireTask(snapshot, input.taskID) : undefined;
  const event = makeEvent(input.kind, context, input.detail, {
    focusRating: input.focusRating,
    qualityRating: input.qualityRating,
    sessionMinutes: input.sessionMinutes
  });
  snapshot.history.unshift(event);
  return event;
}

export function searchWorkspace(snapshot: WorkspaceSnapshot, query: string) {
  const needle = query.trim().toLocaleLowerCase();
  if (!needle) return { jobs: [], projects: [], operations: [], tasks: [] };
  return {
    jobs: snapshot.jobs.filter((job) => matches(needle, job.title, job.summary)),
    projects: snapshot.jobs.flatMap((job) =>
      job.projects
        .filter((project) => matches(needle, project.title, project.outcome))
        .map((project) => ({ ...project, jobID: job.id, jobTitle: job.title }))
    ),
    operations: snapshot.jobs.flatMap((job) =>
      job.operations
        .filter((operation) => matches(needle, operation.title, operation.summary))
        .map((operation) => ({ ...operation, jobID: job.id, jobTitle: job.title }))
    ),
    tasks: flattenTasks(snapshot).filter((ctx) =>
      matches(needle, ctx.task.title, ctx.task.summary, ctx.task.why, ctx.task.nextStep, ctx.task.waitingOn ?? "")
    )
  };
}

function normalizeWorkspace(snapshot: WorkspaceSnapshot): WorkspaceSnapshot {
  snapshot.jobs ??= [];
  snapshot.standaloneTasks ??= [];
  snapshot.history ??= [];
  for (const job of snapshot.jobs) {
    job.jobTasks ??= [];
    job.projects ??= [];
    job.operations ??= [];
    for (const project of job.projects) project.tasks ??= [];
    for (const operation of job.operations) {
      operation.tasks ??= [];
      operation.isArchived ??= false;
      operation.cascadeArchivedTaskIDs ??= [];
    }
  }
  return { ...defaultWorkspace(), ...snapshot };
}

function insertTask(snapshot: WorkspaceSnapshot, task: Task, jobID: string | null, projectID: string | null, operationID: string | null) {
  if (!jobID) {
    snapshot.standaloneTasks.push(task);
    return;
  }
  const job = requireJob(snapshot, jobID);
  if (operationID) {
    const operation = job.operations.find((candidate) => candidate.id === operationID);
    if (!operation) throw new WorkspaceError(`Operation not found: ${operationID}`, "NOT_FOUND");
    operation.tasks.push(task);
    return;
  }
  if (projectID) {
    const project = job.projects.find((candidate) => candidate.id === projectID);
    if (!project) throw new WorkspaceError(`Project not found: ${projectID}`, "NOT_FOUND");
    project.tasks.push(task);
    return;
  }
  job.jobTasks.push(task);
}

function requireJob(snapshot: WorkspaceSnapshot, jobID: string): Job {
  const job = snapshot.jobs.find((candidate) => candidate.id === jobID);
  if (!job) throw new WorkspaceError(`Job not found: ${jobID}`, "NOT_FOUND");
  return job;
}

function requireTask(snapshot: WorkspaceSnapshot, taskID: string): TaskContext {
  const context = findTask(snapshot, taskID);
  if (!context) throw new WorkspaceError(`Task not found: ${taskID}`, "NOT_FOUND");
  return context;
}

function nextNowOrder(snapshot: WorkspaceSnapshot): number {
  const orders = flattenTasks(snapshot)
    .filter((ctx) => ctx.task.isScheduledNow && !ctx.task.isArchived)
    .map((ctx) => ctx.task.nowOrder);
  return orders.length ? Math.max(...orders) + 1 : 0;
}

function pauseConflictingActiveTasks(snapshot: WorkspaceSnapshot, activatedTaskID: string) {
  const activated = requireTask(snapshot, activatedTaskID);
  const activeContexts = flattenTasks(snapshot).filter(
    (ctx) => ctx.task.status === "active" && ctx.task.id !== activatedTaskID
  );
  if (activated.task.energy.startsWith("multitask")) return;
  for (const context of activeContexts) {
    context.task.status = "paused";
    appendEvent(snapshot, "paused", context, "Paused because another task was started.");
  }
}

function appendEvent(snapshot: WorkspaceSnapshot, kind: ActivityKind, context: TaskContext, detail: string) {
  snapshot.history.unshift(makeEvent(kind, context, detail));
}

function makeEvent(
  kind: ActivityKind,
  context: TaskContext | undefined,
  detail: string,
  extras: Pick<ActivityEvent, "focusRating" | "qualityRating" | "sessionMinutes"> = {}
): ActivityEvent {
  return {
    id: newID(),
    timestamp: nowIso(),
    kind,
    taskID: context?.task.id ?? null,
    taskTitle: context?.task.title ?? "",
    projectTitle: context?.projectTitle ?? "",
    containerKind: context?.operationID ? "operation" : context?.projectID ? "project" : null,
    containerTitle: context?.containerTitle ?? "",
    detail,
    ...extras
  };
}

function eventKindForStatus(status: TaskStatus): ActivityKind {
  if (status === "active") return "started";
  if (status === "waiting") return "waiting";
  if (status === "done") return "completed";
  if (status === "paused") return "paused";
  return "switched";
}

function defaultDetailForStatus(status: TaskStatus): string {
  if (status === "active") return "Started from MCP.";
  if (status === "waiting") return "Marked waiting from MCP.";
  if (status === "done") return "Completed from MCP.";
  if (status === "paused") return "Paused from MCP.";
  return "Updated from MCP.";
}

function taskLocation(snapshot: WorkspaceSnapshot, taskID: string) {
  const standaloneIndex = snapshot.standaloneTasks.findIndex((task) => task.id === taskID);
  if (standaloneIndex >= 0) {
    return {
      tasks: snapshot.standaloneTasks,
      index: standaloneIndex,
      context: (task: Task): TaskContext => ({
        task,
        jobID: null,
        projectID: null,
        operationID: null,
        jobTitle: "",
        projectTitle: "",
        operationTitle: "",
        containerTitle: "Inbox"
      })
    };
  }

  for (const job of snapshot.jobs) {
    const jobTaskIndex = job.jobTasks.findIndex((task) => task.id === taskID);
    if (jobTaskIndex >= 0) {
      return {
        tasks: job.jobTasks,
        index: jobTaskIndex,
        context: (task: Task): TaskContext => ({
          task,
          jobID: job.id,
          projectID: null,
          operationID: null,
          jobTitle: job.title,
          projectTitle: "",
          operationTitle: "",
          containerTitle: job.title
        })
      };
    }

    for (const project of job.projects) {
      const taskIndex = project.tasks.findIndex((task) => task.id === taskID);
      if (taskIndex >= 0) {
        return {
          tasks: project.tasks,
          index: taskIndex,
          context: (task: Task): TaskContext => ({
            task,
            jobID: job.id,
            projectID: project.id,
            operationID: null,
            jobTitle: job.title,
            projectTitle: project.title,
            operationTitle: "",
            containerTitle: project.title
          })
        };
      }
    }

    for (const operation of job.operations) {
      const taskIndex = operation.tasks.findIndex((task) => task.id === taskID);
      if (taskIndex >= 0) {
        return {
          tasks: operation.tasks,
          index: taskIndex,
          context: (task: Task): TaskContext => ({
            task,
            jobID: job.id,
            projectID: null,
            operationID: operation.id,
            jobTitle: job.title,
            projectTitle: "",
            operationTitle: operation.title,
            containerTitle: operation.title
          })
        };
      }
    }
  }

  return undefined;
}

async function atomicWrite(filePath: string, data: string) {
  const tmp = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmp, data, "utf8");
  await fs.rename(tmp, filePath);
}

function stableStringify(value: unknown): string {
  return JSON.stringify(sortKeys(value), null, 2);
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, entry]) => [key, sortKeys(entry)])
  );
}

function normalizeIconEmoji(value?: string): string {
  const trimmed = value?.trim() ?? "";
  return Array.from(trimmed)[0] ?? "";
}

function normalizeStringList(value: string[] | undefined, limit: number): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of value ?? []) {
    const trimmed = item.trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    out.push(trimmed);
    if (out.length >= limit) break;
  }
  return out;
}

function emptyToNull(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed ? trimmed : null;
}

function clampInt(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.round(value)));
}

function matches(needle: string, ...values: string[]): boolean {
  return values.some((value) => value.toLocaleLowerCase().includes(needle));
}

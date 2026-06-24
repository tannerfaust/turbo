export const jobPalettes = [
  "forest",
  "ocean",
  "amber",
  "rose",
  "slate",
  "violet",
  "magenta",
  "mint",
  "teal",
  "sky",
  "indigo",
  "lime",
  "coral",
  "plum",
  "copper",
  "cyan",
  "iris",
  "grey"
] as const;

export const taskEnergies = ["deepFocus", "shallowWork", "multitask2", "multitask3", "multitask4"] as const;
export const taskCadences = ["oneOff", "repeatable", "kpi"] as const;
export const taskStatuses = ["queued", "active", "waiting", "paused", "done"] as const;
export const activityKinds = [
  "started",
  "paused",
  "waiting",
  "completed",
  "switched",
  "counted",
  "focusRated",
  "qualityRated"
] as const;

export type JobPalette = (typeof jobPalettes)[number];
export type TaskEnergy = (typeof taskEnergies)[number];
export type TaskCadence = (typeof taskCadences)[number];
export type TaskStatus = (typeof taskStatuses)[number];
export type ActivityKind = (typeof activityKinds)[number];

export interface WorkspaceSnapshot {
  jobs: Job[];
  standaloneTasks: Task[];
  history: ActivityEvent[];
  dailyCapacityMinutes: number;
  dayBatteryStartMinutes: number;
  dayBatteryEndMinutes: number;
  dayBatteryShowsPercentageInMenuBar: boolean;
  dayBatteryUsesWideMenuBarItem: boolean;
  taskAutoArchiveAfterIdleHours: number;
  doneTaskAutoArchiveAfterDays: number;
  archivedTaskPurgeAfterDays: number;
  tasksPresentation: {
    viewMode: "table" | "kanban" | "cards";
    visibleFields: string[];
  };
  themeMode: "system" | "light" | "dark";
  nowPinnedJobIDs: string[];
  nowSuppressedJobIDs: string[];
  focusCardDensity: "compact" | "standard" | "minimal";
  newNowTaskPlacement: "top" | "bottom";
  focusOverlayPresenceMode: "allDesktops" | "thisDesktopOnly";
  focusOverlayWindowFrame?: {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null;
  trainingWheelsEnabled: boolean;
  typeaheadListNavigationEnabled: boolean;
  [key: string]: unknown;
}

export interface Job {
  id: string;
  title: string;
  summary: string;
  palette: JobPalette;
  jobTasks: Task[];
  projects: Project[];
  operations: Operation[];
  [key: string]: unknown;
}

export interface Project {
  id: string;
  title: string;
  outcome: string;
  iconEmoji: string;
  tasks: Task[];
  [key: string]: unknown;
}

export interface Operation {
  id: string;
  title: string;
  summary: string;
  isArchived: boolean;
  archivedAt?: string | null;
  tasks: Task[];
  cascadeArchivedTaskIDs: string[];
  [key: string]: unknown;
}

export interface Task {
  id: string;
  title: string;
  summary: string;
  why: string;
  energy: TaskEnergy;
  cadence: TaskCadence;
  status: TaskStatus;
  progress: number;
  estimatedMinutes: number;
  isScheduledNow: boolean;
  nowOrder: number;
  priority: number;
  waitingOn?: string | null;
  nextStep: string;
  repeatEveryMinutes?: number | null;
  kpiTarget?: number | null;
  kpiUnit?: string | null;
  kpiRoundsRemaining?: number | null;
  kpiCount: number;
  nextAvailableAt?: string | null;
  toolBundleIDs: string[];
  startDate?: string | null;
  endDate?: string | null;
  isArchived: boolean;
  archivedAt?: string | null;
  blockedByTaskIDs: string[];
  [key: string]: unknown;
}

export interface ActivityEvent {
  id: string;
  timestamp: string;
  kind: ActivityKind;
  taskID?: string | null;
  taskTitle: string;
  projectTitle: string;
  containerKind?: "project" | "operation" | null;
  containerTitle: string;
  detail: string;
  focusRating?: number | null;
  qualityRating?: number | null;
  sessionMinutes?: number | null;
  [key: string]: unknown;
}

export interface TaskContext {
  task: Task;
  jobID: string | null;
  projectID: string | null;
  operationID: string | null;
  jobTitle: string;
  projectTitle: string;
  operationTitle: string;
  containerTitle: string;
}

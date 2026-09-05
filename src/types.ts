export type TaskStatus = "inbox" | "doing" | "paused" | "done";
export type JumpKind = "url" | "file" | "app";

export interface JumpTarget {
  kind: JumpKind;
  value: string;
  label: string;
}

export interface PauseNote {
  id: string;
  at: number;
  text: string;
}

export interface WorkSession {
  id: string;
  start: number;
  end?: number;
}

export type SubStatus = "open" | "doing" | "done";

export interface SubTask {
  id: string;
  text: string;
  status: SubStatus;
  startedAt?: number;
  completedAt?: number;
  elapsedMs: number;
}

export interface Task {
  id: string;
  title: string;
  raw: string;
  status: TaskStatus;
  jump?: JumpTarget;
  notes: PauseNote[];
  sessions: WorkSession[];
  subs: SubTask[];
  createdAt: number;
  startedAt?: number;
  pausedAt?: number;
  completedAt?: number;
  scheduledFor: number;
  waitForId?: string;
  waitForText?: string;
  focusMs: number;
  remindAt?: number;
  lastRemindedAt?: number;
  updatedAt: number;
}

export interface Settings {
  defaultFocusMs: number;
  inboxNudgeMs: number;
  pauseNudgeMs: number;
  snoozeMs: number;
  autoSplit: boolean;
}

export interface AppState {
  tasks: Task[];
  settings: Settings;
}

export const DEFAULT_SETTINGS: Settings = {
  defaultFocusMs: 25 * 60 * 1000,
  inboxNudgeMs: 15 * 60 * 1000,
  pauseNudgeMs: 30 * 60 * 1000,
  snoozeMs: 5 * 60 * 1000,
  autoSplit: true,
};

export const QUICK_APPS: { label: string; value: string }[] = [
  { label: "Figma", value: "Figma" },
  { label: "Cursor", value: "Cursor" },
  { label: "浏览器", value: "Google Chrome" },
  { label: "访达", value: "Finder" },
  { label: "备忘录", value: "Notes" },
  { label: "飞书", value: "Lark" },
  { label: "微信", value: "WeChat" },
  { label: "邮件", value: "Mail" },
];

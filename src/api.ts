import { DEFAULT_SETTINGS, type AppState, type JumpTarget, type SubTask, type Task, type WorkSession } from "./types";
import { makeSessionId, startOfDay } from "./parseCapture";

const STORE = "nowdo-web:state";

function migrateSubs(task: Task & { subs?: SubTask[] }): SubTask[] {
  if (Array.isArray(task.subs) && task.subs.length > 0) return task.subs;
  return (task.notes ?? []).map((note, index) => {
    const session = task.sessions?.[index] ?? task.sessions?.at(-1);
    const elapsed = session ? Math.max(0, (session.end ?? note.at) - session.start) : 0;
    return {
      id: note.id,
      text: note.text,
      status: "done" as const,
      startedAt: session?.start,
      completedAt: note.at,
      elapsedMs: elapsed,
    };
  });
}

function migrateTask(task: Task & { sessions?: WorkSession[]; subs?: SubTask[] }): Task {
  let sessions = Array.isArray(task.sessions) ? task.sessions : [];
  if (!Array.isArray(task.sessions) && task.startedAt) {
    sessions = [
      {
        id: makeSessionId(),
        start: task.startedAt,
        end: task.pausedAt || task.completedAt || (task.status === "doing" ? undefined : task.updatedAt),
      },
    ];
  }
  const next = { ...task, sessions };
  return {
    ...next,
    subs: migrateSubs(next),
    scheduledFor: next.scheduledFor ?? startOfDay(next.remindAt ?? next.createdAt),
  };
}

export async function loadState(): Promise<AppState> {
  try {
    const cached = localStorage.getItem(STORE);
    if (!cached) return { tasks: [], settings: DEFAULT_SETTINGS };
    const parsed = JSON.parse(cached) as AppState;
    return {
      tasks: (parsed.tasks ?? []).map(migrateTask),
      settings: { ...DEFAULT_SETTINGS, ...parsed.settings },
    };
  } catch {
    return { tasks: [], settings: DEFAULT_SETTINGS };
  }
}

export async function saveState(state: AppState) {
  localStorage.setItem(STORE, JSON.stringify(state));
}

export async function openJump(jump: JumpTarget) {
  if (jump.kind === "url") {
    window.open(jump.value, "_blank", "noopener");
    return true;
  }
  return false;
}

export function subscribeEvents(_onEvent: (event: { type: string; taskId?: string }) => void) {
  return () => undefined;
}

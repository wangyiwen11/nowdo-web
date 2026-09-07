import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { loadState, openJump, saveState, subscribeEvents } from "./api";
import {
  addDays,
  captureDay,
  findAfterTask,
  latestNote,
  makeId,
  makeNoteId,
  makeSessionId,
  makeSubId,
  parsePlans,
  startOfDay,
  taskDay,
  taskElapsed,
} from "./parseCapture";
import { DEFAULT_SETTINGS, type AppState, type JumpTarget, type Settings, type SubTask, type Task, type WorkSession } from "./types";

function closeOpenSessions(sessions: WorkSession[], at: number) {
  return (sessions ?? []).map((session) => (session.end ? session : { ...session, end: at }));
}

function openSession(sessions: WorkSession[], at: number) {
  return [...closeOpenSessions(sessions, at), { id: makeSessionId(), start: at }];
}

function lastOpenElapsed(sessions: WorkSession[], at: number) {
  const open = [...(sessions ?? [])].reverse().find((session) => !session.end);
  return open ? Math.max(0, at - open.start) : 0;
}

function lastIndex(subs: SubTask[], status: SubTask["status"]) {
  for (let i = subs.length - 1; i >= 0; i -= 1) {
    if (subs[i].status === status) return i;
  }
  return -1;
}

function currentSubIndex(subs: SubTask[]) {
  const doing = lastIndex(subs, "doing");
  if (doing >= 0) return doing;
  return lastIndex(subs, "open");
}

function withCurrentSub(subs: SubTask[], text: string, at: number, extra: number, asDone: boolean) {
  const next = [...subs];
  const index = currentSubIndex(next);
  if (index >= 0) {
    const sub = next[index];
    next[index] = {
      ...sub,
      text: text || sub.text,
      status: asDone ? "done" : "open",
      completedAt: asDone ? at : undefined,
      elapsedMs: (sub.elapsedMs ?? 0) + extra,
    };
    return next;
  }
  if (!text) return next;
  next.push({
    id: makeSubId(),
    text,
    status: asDone ? "done" : "open",
    startedAt: at - extra,
    completedAt: asDone ? at : undefined,
    elapsedMs: extra,
  });
  return next;
}

function startOrAddSub(subs: SubTask[], text: string | undefined, at: number) {
  const next = [...subs];
  const index = currentSubIndex(next);
  if (text) {
    if (index >= 0 && !next[index].text) {
      next[index] = { ...next[index], text, status: "doing", startedAt: next[index].startedAt ?? at };
      return next;
    }
    if (index >= 0 && next[index].status !== "done" && next[index].text === text) {
      next[index] = { ...next[index], status: "doing", startedAt: next[index].startedAt ?? at };
      return next;
    }
    next.push({ id: makeSubId(), text, status: "doing", startedAt: at, elapsedMs: 0 });
    return next;
  }
  if (index >= 0) {
    next[index] = { ...next[index], status: "doing", startedAt: next[index].startedAt ?? at };
    return next;
  }
  return next;
}

function now() {
  return Date.now();
}

function requestBrowserNotify() {
  if (typeof Notification === "undefined") return;
  if (Notification.permission === "default") {
    void Notification.requestPermission().catch(() => undefined);
  }
}

function browserNotify(title: string, body: string, taskId: string, onClick: () => void) {
  if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
  try {
    const note = new Notification(title, { body, tag: `nowdo-${taskId}` });
    note.onclick = () => {
      window.focus();
      onClick();
      note.close();
    };
  } catch {
    // Some mobile browsers expose Notification but do not allow its constructor.
    // The in-page reminder remains available.
  }
}

export function useNowdo() {
  const [state, setState] = useState<AppState>({ tasks: [], settings: DEFAULT_SETTINGS });
  const [ready, setReady] = useState(false);
  const [pauseTaskId, setPauseTaskId] = useState<string | null>(null);
  const [completeTaskId, setCompleteTaskId] = useState<string | null>(null);
  const [continueTaskId, setContinueTaskId] = useState<string | null>(null);
  const [activeReminderId, setActiveReminderId] = useState<string | null>(null);
  const [clock, setClock] = useState(now());
  const [viewDay, setViewDay] = useState(() => startOfDay());
  const stateRef = useRef(state);
  const jumpedHash = useRef(false);
  stateRef.current = state;

  useEffect(() => {
    void loadState().then((loaded) => {
      setState(loaded);
      setReady(true);
      requestBrowserNotify();
    });
  }, []);

  useEffect(() => {
    if (!ready) return;
    void saveState(state);
  }, [ready, state]);

  useEffect(() => {
    const timer = window.setInterval(() => setClock(now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const patchTasks = useCallback((updater: (tasks: Task[]) => Task[]) => {
    setState((prev) => ({ ...prev, tasks: updater(prev.tasks) }));
  }, []);

  const updateSettings = useCallback((settings: Partial<Settings>) => {
    setState((prev) => ({ ...prev, settings: { ...prev.settings, ...settings } }));
  }, []);

  const jumpToTask = useCallback((taskId: string, startIfNeeded = false) => {
    setActiveReminderId(taskId);
    const task = stateRef.current.tasks.find((item) => item.id === taskId);
    if (task) setViewDay(taskDay(task));
    if (startIfNeeded && task && task.status !== "doing") {
      void startTask(taskId);
    }
    const card = document.getElementById(`task-${taskId}`);
    card?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, []);

  const startTask = useCallback(async (taskId: string, nextSub?: string) => {
    const task = stateRef.current.tasks.find((item) => item.id === taskId);
    if (!task) return false;

    const at = now();
    patchTasks((tasks) =>
      tasks.map((item) =>
        item.id === taskId
          ? {
              ...item,
              status: "doing",
              completedAt: undefined,
              startedAt: item.startedAt ?? at,
              sessions: item.status === "doing" ? item.sessions : openSession(item.sessions, at),
              subs: startOrAddSub(item.subs ?? [], nextSub?.trim() || undefined, at),
              remindAt: undefined,
              updatedAt: at,
            }
          : item,
      ),
    );
    setActiveReminderId(null);
    setContinueTaskId(null);
    if (task.jump) {
      await openJump(task.jump);
    }
    return true;
  }, [patchTasks]);

  const capture = useCallback(
    (text: string) => {
      const createdAt = now();
      const plans = parsePlans(text, createdAt, { split: stateRef.current.settings.autoSplit !== false });
      if (plans.length === 0) return null;
      const focusDay = captureDay(plans, stateRef.current.tasks, createdAt);
      let last: Task | null = null;

      patchTasks((tasks) => {
        let next = tasks;
        for (const plan of plans) {
          if (plan.afterQuery) {
            const host = findAfterTask(next, plan.afterQuery);
            if (host) {
              const follow = [plan.title, ...plan.parts].filter((part, index, all) => all.indexOf(part) === index);
              next = next.map((item) =>
                item.id === host.id
                  ? {
                      ...item,
                      subs: [
                        ...(item.subs ?? []),
                        ...follow.map((part) => ({
                          id: makeSubId(),
                          text: part,
                          status: "open" as const,
                          elapsedMs: 0,
                        })),
                      ],
                      updatedAt: createdAt,
                    }
                  : item,
              );
              last = { ...host, scheduledFor: taskDay(host) };
              continue;
            }
          }

          const startNow =
            plans.length === 1 &&
            /现在做|马上做|开始做/.test(text) &&
            !plan.remindAt &&
            plan.scheduledFor === startOfDay(createdAt);
          const created: Task = {
            id: makeId(),
            title: plan.title.replace(/现在做|马上做|开始做/g, "").trim() || plan.title,
            raw: plan.source?.trim() || text.trim(),
            status: startNow ? "doing" : "inbox",
            jump: plan.jump,
            notes: [],
            sessions: startNow ? [{ id: makeSessionId(), start: createdAt }] : [],
            subs: plan.parts.map((part) => ({
              id: makeSubId(),
              text: part,
              status: "open" as const,
              elapsedMs: 0,
            })),
            createdAt,
            startedAt: startNow ? createdAt : undefined,
            scheduledFor: plan.scheduledFor,
            waitForText: plan.afterQuery,
            focusMs: stateRef.current.settings.defaultFocusMs,
            remindAt: plan.remindAt,
            updatedAt: createdAt,
          };
          next = [...next, created];
          last = created;
        }
        return next;
      });
      setViewDay(focusDay);
      return last;
    },
    [patchTasks],
  );

  const finishSegment = useCallback((taskId: string, note: string, asDone: boolean) => {
    const text = note.trim();
    if (!text) return false;
    const at = now();
    patchTasks((tasks) =>
      tasks.map((item) => {
        if (item.id !== taskId) return item;
        const extra = lastOpenElapsed(item.sessions, at);
        return {
          ...item,
          status: "paused",
          pausedAt: at,
          sessions: closeOpenSessions(item.sessions, at),
          subs: withCurrentSub(item.subs ?? [], text, at, extra, asDone),
          remindAt: undefined,
          notes: text ? [...item.notes, { id: makeNoteId(), at, text }] : item.notes,
          updatedAt: at,
        };
      }),
    );
    setPauseTaskId(null);
    setCompleteTaskId(null);
    return true;
  }, [patchTasks]);

  const confirmPause = useCallback(
    (taskId: string, note: string) => finishSegment(taskId, note, false),
    [finishSegment],
  );

  const completeSegment = useCallback(
    (taskId: string, note: string) => finishSegment(taskId, note, true),
    [finishSegment],
  );

  const askComplete = useCallback((taskId: string) => {
    const task = stateRef.current.tasks.find((item) => item.id === taskId);
    const index = currentSubIndex(task?.subs ?? []);
    const current = index >= 0 ? task?.subs[index] : undefined;
    if (current?.text) {
      completeSegment(taskId, current.text);
      return;
    }
    setCompleteTaskId(taskId);
  }, [completeSegment]);

  const addNote = useCallback((taskId: string, text: string) => {
    const note = text.trim();
    if (!note) return;
    patchTasks((tasks) =>
      tasks.map((item) =>
        item.id === taskId
          ? {
              ...item,
              notes: [...item.notes, { id: makeNoteId(), at: now(), text: note }],
              updatedAt: now(),
            }
          : item,
      ),
    );
  }, [patchTasks]);

  const setJump = useCallback((taskId: string, jump?: JumpTarget) => {
    patchTasks((tasks) =>
      tasks.map((item) => (item.id === taskId ? { ...item, jump, updatedAt: now() } : item)),
    );
  }, [patchTasks]);

  const snooze = useCallback((taskId: string, ms: number) => {
    patchTasks((tasks) =>
      tasks.map((item) =>
        item.id === taskId
          ? { ...item, remindAt: now() + ms, lastRemindedAt: now(), updatedAt: now() }
          : item,
      ),
    );
    setActiveReminderId((id) => (id === taskId ? null : id));
    setContinueTaskId((id) => (id === taskId ? null : id));
  }, [patchTasks]);

  const remindNow = useCallback(
    (task: Task) => {
      setActiveReminderId(task.id);
      const note = latestNote(task.notes) || task.subs?.at(-1)?.text;
      const body = note ? `还停在：${note}` : "还没开始。现在做这一件？";
      browserNotify(`nowdo · ${task.title}`, body, task.id, () => jumpToTask(task.id));
      patchTasks((tasks) =>
        tasks.map((item) =>
          item.id === task.id
            ? {
                ...item,
                lastRemindedAt: now(),
                remindAt: now() + stateRef.current.settings.snoozeMs,
                updatedAt: now(),
              }
            : item,
        ),
      );
    },
    [jumpToTask, patchTasks],
  );

  useEffect(() => {
    if (!ready) return;
    const due = state.tasks.find(
      (task) =>
        task.status !== "done" &&
        task.status !== "doing" &&
        task.remindAt &&
        task.remindAt <= clock &&
        task.id !== activeReminderId,
    );
    if (due) remindNow(due);
  }, [activeReminderId, clock, ready, remindNow, state.tasks]);

  useEffect(() => {
    return subscribeEvents((event) => {
      if (event.type === "reminder" && event.taskId) {
        const task = stateRef.current.tasks.find((item) => item.id === event.taskId);
        if (task) remindNow(task);
        jumpToTask(event.taskId);
      }
      if (event.type === "focus" && event.taskId) {
        jumpToTask(event.taskId);
      }
    });
  }, [jumpToTask, remindNow]);

  useEffect(() => {
    if (!ready || jumpedHash.current) return;
    const hash = window.location.hash.replace(/^#/, "");
    const params = new URLSearchParams(hash.includes("=") ? hash : `task=${hash.replace(/^task=/, "")}`);
    const taskId = params.get("task") || params.get("remind");
    if (!taskId) return;
    if (!state.tasks.some((task) => task.id === taskId)) return;
    jumpedHash.current = true;
    jumpToTask(taskId);
  }, [jumpToTask, ready, state.tasks]);

  const doingTasks = useMemo(
    () => state.tasks.filter((task) => task.status === "doing").sort((a, b) => (a.startedAt ?? 0) - (b.startedAt ?? 0)),
    [state.tasks],
  );
  const openTasks = useMemo(
    () => state.tasks.filter((task) => task.status === "inbox" || task.status === "paused"),
    [state.tasks],
  );
  const doneToday = useMemo(() => {
    const start = startOfDay();
    return state.tasks
      .filter((task) => task.status === "done" && (task.completedAt ?? 0) >= start)
      .sort((a, b) => (a.completedAt ?? 0) - (b.completedAt ?? 0));
  }, [state.tasks]);

  const todayAxis = useMemo(() => {
    return state.tasks
      .filter((task) => taskDay(task) === viewDay)
      .map((task) => ({
        task,
        elapsed: taskElapsed(task, clock),
      }))
      .sort((a, b) => (a.task.remindAt ?? a.task.createdAt) - (b.task.remindAt ?? b.task.createdAt));
  }, [clock, state.tasks, viewDay]);

  const todayElapsed = useMemo(
    () => todayAxis.reduce((sum, item) => sum + item.elapsed, 0),
    [todayAxis],
  );

  const completeTask = useMemo(
    () => state.tasks.find((task) => task.id === completeTaskId) ?? null,
    [completeTaskId, state.tasks],
  );
  const pauseTask = useMemo(
    () => state.tasks.find((task) => task.id === pauseTaskId) ?? null,
    [pauseTaskId, state.tasks],
  );
  const reminderTask = useMemo(
    () => state.tasks.find((task) => task.id === activeReminderId) ?? null,
    [activeReminderId, state.tasks],
  );
  const continueTask = useMemo(
    () => state.tasks.find((task) => task.id === continueTaskId) ?? null,
    [continueTaskId, state.tasks],
  );

  return {
    ready,
    clock,
    tasks: state.tasks,
    settings: state.settings,
    doingTasks,
    openTasks,
    doneToday,
    todayAxis,
    todayElapsed,
    viewDay,
    setViewDay,
    shiftDay: (n: number) => setViewDay((day) => addDays(day, n)),
    pauseTask,
    continueTask,
    reminderTask,
    capture,
    startTask,
    askPause: (taskId: string) => setPauseTaskId(taskId),
    cancelPause: () => setPauseTaskId(null),
    confirmPause,
    completeSegment,
    askComplete,
    cancelComplete: () => setCompleteTaskId(null),
    completePrompt: completeTask,
    addNote,
    setJump,
    snooze,
    askContinue: (taskId: string) => {
      setContinueTaskId(taskId);
      setActiveReminderId(null);
    },
    cancelContinue: () => setContinueTaskId(null),
    dismissReminder: () => setActiveReminderId(null),
    jumpToTask,
    updateSettings,
  };
}

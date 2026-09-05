import type { JumpTarget } from "./types";

export interface ParsedCapture {
  title: string;
  jump?: JumpTarget;
  remindInMs?: number;
}

export interface ParsedPlan {
  title: string;
  jump?: JumpTarget;
  remindInMs?: number;
  remindAt?: number;
  scheduledFor: number;
  parts: string[];
  afterQuery?: string;
  source?: string;
}

const APP_ALIASES: Record<string, string> = {
  figma: "Figma",
  cursor: "Cursor",
  chrome: "Google Chrome",
  浏览器: "Google Chrome",
  safari: "Safari",
  finder: "Finder",
  访达: "Finder",
  notes: "Notes",
  备忘录: "Notes",
  notion: "Notion",
  slack: "Slack",
  lark: "Lark",
  飞书: "Lark",
  微信: "WeChat",
  wechat: "WeChat",
  mail: "Mail",
  邮件: "Mail",
  vscode: "Visual Studio Code",
  "vs code": "Visual Studio Code",
};

const APP_NAMES = Object.keys(APP_ALIASES).sort((a, b) => b.length - a.length);

function uid(prefix: string) {
  return `${prefix}-${Math.random().toString(36).slice(2, 8)}`;
}

function cleanTitle(text: string) {
  return text
    .replace(/^(帮我|请|麻烦|我想|我要|我打算|打算|记得|提醒我)/g, "")
    .replace(/[。.!！]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function parseRemindInMs(text: string): { remindInMs?: number; rest: string } {
  let rest = text;
  let remindInMs: number | undefined;

  const patterns: Array<[RegExp, number | ((m: RegExpMatchArray) => number)]> = [
    [/半小时后|30\s*分钟后/, 30 * 60 * 1000],
    [/一刻钟后|15\s*分钟后/, 15 * 60 * 1000],
    [/一小时后|1\s*小时后/, 60 * 60 * 1000],
    [/今晚/, () => hoursUntil(20)],
    [/明天/, () => nextDayAt(10)],
    [/(\d+)\s*分钟后/, (m) => Number(m[1]) * 60 * 1000],
    [/(\d+)\s*小时后/, (m) => Number(m[1]) * 60 * 60 * 1000],
    [/(\d{1,2})[:：](\d{2})/, (m) => msUntilClock(Number(m[1]), Number(m[2]))],
    [
      /(凌晨|早上|上午|中午|下午|晚上|傍晚)?\s*([一二两三四五六七八九十\d]{1,3})\s*点\s*(半|[一二三四五六七八九十\d]{1,2})?/,
      (m) => {
        const hour = chineseHour(m[2]);
        if (hour == null) return -1;
        const minute = m[3] === "半" ? 30 : m[3] ? chineseHour(m[3]) ?? 0 : 0;
        return msUntilClock(applyPeriod(hour, m[1]), minute);
      },
    ],
  ];

  for (const [re, value] of patterns) {
    const m = rest.match(re);
    if (!m) continue;
    const resolved = typeof value === "function" ? value(m) : value;
    if (resolved < 0) continue;
    remindInMs = resolved;
    rest = rest.replace(m[0], " ");
    break;
  }

  rest = rest.replace(/提醒我|到点提醒|叫我/g, " ").replace(/\s+/g, " ").trim();
  return { remindInMs, rest };
}

function chineseHour(raw: string) {
  if (/^\d+$/.test(raw)) return Number(raw);
  const table: Record<string, number> = {
    零: 0,
    一: 1,
    二: 2,
    两: 2,
    三: 3,
    四: 4,
    五: 5,
    六: 6,
    七: 7,
    八: 8,
    九: 9,
    十: 10,
    十一: 11,
    十二: 12,
  };
  return table[raw] ?? null;
}

function applyPeriod(hour: number, period?: string) {
  if (period === "下午" || period === "晚上" || period === "傍晚") return hour < 12 ? hour + 12 : hour;
  if (period === "中午" && hour <= 2) return 12;
  return hour;
}

function msUntilClock(hour: number, minute: number) {
  const next = new Date();
  next.setHours(hour, minute, 0, 0);
  if (next.getTime() <= Date.now()) next.setDate(next.getDate() + 1);
  return next.getTime() - Date.now();
}

export function parseReminder(text: string) {
  return parseRemindInMs(text).remindInMs;
}

function hoursUntil(hour: number) {
  const now = new Date();
  const next = new Date(now);
  next.setHours(hour, 0, 0, 0);
  if (next.getTime() <= now.getTime()) next.setDate(next.getDate() + 1);
  return next.getTime() - now.getTime();
}

function nextDayAt(hour: number) {
  const next = new Date();
  next.setDate(next.getDate() + 1);
  next.setHours(hour, 0, 0, 0);
  return next.getTime() - Date.now();
}

function jumpFromUrl(text: string): { jump?: JumpTarget; rest: string } {
  const m = text.match(/https?:\/\/\S+/i);
  if (!m) return { rest: text };
  const url = m[0].replace(/[)，。,]+$/, "");
  return {
    jump: { kind: "url", value: url, label: prettyHost(url) },
    rest: text.replace(m[0], " ").replace(/\s+/g, " ").trim(),
  };
}

function jumpFromPath(text: string): { jump?: JumpTarget; rest: string } {
  const m = text.match(/(?:~|\/Users)\/[^\s]+/);
  if (!m) return { rest: text };
  return {
    jump: { kind: "file", value: m[0], label: m[0].split("/").filter(Boolean).at(-1) || m[0] },
    rest: text.replace(m[0], " ").replace(/\s+/g, " ").trim(),
  };
}

function jumpFromApp(text: string): { jump?: JumpTarget; rest: string } {
  const open = text.match(
    new RegExp(`(?:打开|用|在)\\s*(${APP_NAMES.join("|")})(?:\\s*(?:里|中|上))?`, "i"),
  );
  if (open) {
    const key = open[1].toLowerCase();
    const app = APP_ALIASES[key] || APP_ALIASES[open[1]] || open[1];
    return {
      jump: { kind: "app", value: app, label: app },
      rest: text.replace(open[0], " ").replace(/\s+/g, " ").trim(),
    };
  }

  for (const name of APP_NAMES) {
    const re = new RegExp(`(?:^|[\\s])${name}(?:[\\s]|$)`, "i");
    if (re.test(text)) {
      const app = APP_ALIASES[name] || name;
      return {
        jump: { kind: "app", value: app, label: app },
        rest: text.replace(new RegExp(name, "i"), " ").replace(/\s+/g, " ").trim(),
      };
    }
  }
  return { rest: text };
}

function prettyHost(url: string) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

export function parseCapture(input: string): ParsedCapture {
  const plan = parsePlan(input);
  return { title: plan.title, jump: plan.jump, remindInMs: plan.remindInMs };
}

export function addDays(dayStart: number, n: number) {
  const d = new Date(dayStart);
  d.setDate(d.getDate() + n);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function startOfMonth(ts: number) {
  const d = new Date(startOfDay(ts));
  d.setDate(1);
  return d.getTime();
}

export function addMonths(ts: number, n: number) {
  const d = new Date(startOfMonth(ts));
  d.setMonth(d.getMonth() + n);
  return startOfMonth(d.getTime());
}

export function sameMonth(a: number, b: number) {
  const left = new Date(a);
  const right = new Date(b);
  return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth();
}

export function monthGrid(monthStart: number) {
  const start = startOfMonth(monthStart);
  const lead = new Date(start).getDay();
  return Array.from({ length: 42 }, (_, index) => addDays(start, index - lead));
}

export function formatMonthTitle(ts: number) {
  const d = new Date(ts);
  return `${d.getFullYear()}年${d.getMonth() + 1}月`;
}

export function taskDay(task: { scheduledFor?: number; createdAt: number }) {
  return task.scheduledFor ?? startOfDay(task.createdAt);
}

export function compactText(text: string) {
  return text.toLowerCase().replace(/[\s,，。.!！、]/g, "");
}

export function findAfterTask<T extends { title: string }>(tasks: T[], query: string) {
  const q = compactText(query);
  if (!q) return undefined;
  return tasks.find((task) => {
    const title = compactText(task.title);
    if (title.includes(q) || q.includes(title)) return true;
    const bits = q.split(/开发|完成|做完/).filter((bit) => bit.length >= 2);
    return bits.length > 0 && bits.every((bit) => title.includes(bit));
  });
}

function clockOnDay(dayStart: number, hour: number, minute: number) {
  const next = new Date(dayStart);
  next.setHours(hour, minute, 0, 0);
  return next.getTime();
}

function takeAfter(text: string): { afterQuery?: string; rest: string } {
  const m = text.match(/等\s*(.+?)\s*(?:完(?:成)?后|之后)/);
  if (!m) return { rest: text };
  return {
    afterQuery: m[1].replace(/开发$/, "").trim() || m[1].trim(),
    rest: text.replace(m[0], " ").replace(/\s+/g, " ").trim(),
  };
}

function takeDay(text: string, nowTs = Date.now()): { scheduledFor: number; mentioned: boolean; period?: string; rest: string } {
  const today = startOfDay(nowTs);
  if (/后天/.test(text)) {
    return { scheduledFor: addDays(today, 2), mentioned: true, period: periodOf(text), rest: stripDayWords(text) };
  }
  if (/明天/.test(text)) {
    return { scheduledFor: addDays(today, 1), mentioned: true, period: periodOf(text), rest: stripDayWords(text) };
  }
  if (/今天|今晚/.test(text)) {
    return { scheduledFor: today, mentioned: true, period: periodOf(text), rest: stripDayWords(text) };
  }
  return { scheduledFor: today, mentioned: false, period: periodOf(text), rest: text };
}

function periodOf(text: string) {
  if (/今晚|晚上|傍晚/.test(text)) return "晚上";
  if (/中午/.test(text)) return "中午";
  if (/早上|上午/.test(text)) return "早上";
  if (/下午/.test(text)) return "下午";
  return undefined;
}

function stripDayWords(text: string) {
  return text.replace(/后天|明天|今天晚上|今晚|今天/g, " ").replace(/\s+/g, " ").trim();
}

function takeClock(text: string): { hour?: number; minute?: number; matched?: string; rest: string } {
  const colon = text.match(/(\d{1,2})\s*[:：]\s*(\d{2})/);
  if (colon) {
    return {
      hour: Number(colon[1]),
      minute: Number(colon[2]),
      matched: colon[0],
      rest: text.replace(colon[0], " ").replace(/\s+/g, " ").trim(),
    };
  }
  const point = text.match(
    /(凌晨|早上|上午|中午|下午|晚上|傍晚)?\s*([一二两三四五六七八九十\d]{1,3})\s*点\s*(半|[一二三四五六七八九十\d]{1,2})?/,
  );
  if (point) {
    const hour = chineseHour(point[2]);
    if (hour == null) return { rest: text };
    const minute = point[3] === "半" ? 30 : point[3] ? chineseHour(point[3]) ?? 0 : 0;
    return {
      hour: applyPeriod(hour, point[1]),
      minute,
      matched: point[0],
      rest: text.replace(point[0], " ").replace(/\s+/g, " ").trim(),
    };
  }
  return { rest: text };
}

function defaultHour(period?: string, dayMentioned = false, hasAfter = false) {
  if (period === "晚上") return 20;
  if (period === "中午") return 12;
  if (period === "下午") return 15;
  if (period === "早上") return 10;
  if (dayMentioned && !hasAfter) return 10;
  return undefined;
}

function splitAndList(chunk: string) {
  const listed = chunk.match(/^([拿取带买回看做])(.+)和(.+)$/);
  if (listed) {
    return [`${listed[1]}${listed[2].trim()}`, `${listed[1]}${listed[3].trim()}`];
  }
  if (chunk.includes("、")) {
    const verb = chunk.match(/^([拿取带买回看做])/);
    return chunk.split("、").map((piece) => {
      const bit = piece.trim();
      if (verb && bit && !bit.startsWith(verb[1])) return `${verb[1]}${bit}`;
      return bit;
    });
  }
  return [chunk];
}

function splitParts(text: string) {
  return text
    .split(/[，。；;]|顺便|还有/)
    .flatMap((chunk) => splitAndList(chunk.replace(/^[，、和与再]+/, "").trim()))
    .map((part) => cleanTitle(part))
    .filter(Boolean)
    .filter((part, index, all) => all.indexOf(part) === index);
}

function takeJump(text: string): { jump?: JumpTarget; rest: string } {
  const url = jumpFromUrl(text);
  if (url.jump) return url;
  const path = jumpFromPath(text);
  if (path.jump) return path;
  return jumpFromApp(text);
}

export function parsePlans(input: string, nowTs = Date.now(), options?: { split?: boolean }): ParsedPlan[] {
  const split = options?.split !== false;
  if (!split) {
    const plan = parsePlan(input, nowTs, { split: false });
    return plan.title ? [{ ...plan, source: input.trim() }] : [];
  }
  const chunks = input
    .split(/[。！？\n]+/)
    .map((chunk) => chunk.trim())
    .filter((chunk) => chunk && !/^(比如|理解|你理解|对吧|嗯|啊)/.test(chunk));
  const source = chunks.length > 0 ? chunks : [input.trim()];
  return source
    .map((chunk) => ({ ...parsePlan(chunk, nowTs, { split: true }), source: chunk }))
    .filter((plan) => plan.title);
}

export function parsePlan(input: string, nowTs = Date.now(), options?: { split?: boolean }): ParsedPlan {
  const raw = input.trim();
  const empty = { title: "", scheduledFor: startOfDay(nowTs), parts: [] as string[] };
  if (!raw) return empty;

  const after = takeAfter(raw);
  let rest = after.rest;
  const day = takeDay(rest, nowTs);
  rest = day.rest;
  const clock = takeClock(rest);
  rest = clock.rest;
  const relative = parseRemindInMs(rest);
  rest = relative.rest;
  rest = rest.replace(/提醒我|到点提醒|叫我|我打算|打算/g, " ").replace(/\s+/g, " ").trim();
  const jumped = takeJump(rest);
  rest = jumped.rest;

  const split = options?.split !== false;
  const parts = split ? splitParts(rest) : [cleanTitle(rest) || cleanTitle(raw)].filter(Boolean);
  const title = parts[0] || cleanTitle(rest) || cleanTitle(raw) || "未命名待办";
  const extras = split ? parts.slice(1) : [];

  let hour = clock.hour;
  let minute = clock.minute ?? 0;
  if (hour == null) {
    hour = defaultHour(day.period, day.mentioned, Boolean(after.afterQuery));
    minute = 0;
  }

  let remindAt: number | undefined;
  if (hour != null) {
    remindAt = clockOnDay(day.scheduledFor, hour, minute);
  } else if (relative.remindInMs) {
    remindAt = nowTs + relative.remindInMs;
  }

  return {
    title,
    jump: jumped.jump,
    remindInMs: remindAt ? Math.max(0, remindAt - nowTs) : relative.remindInMs,
    remindAt,
    scheduledFor: remindAt ? startOfDay(remindAt) : day.scheduledFor,
    parts: extras,
    afterQuery: after.afterQuery,
  };
}

export function formatJump(jump?: JumpTarget) {
  if (!jump) return "";
  if (jump.kind === "app") return `打开 ${jump.label}`;
  if (jump.kind === "file") return jump.label;
  return jump.label;
}

export function makeId() {
  return uid("t");
}

export function makeNoteId() {
  return uid("n");
}

export function makeSubId() {
  return uid("u");
}

export function makeSessionId() {
  return uid("s");
}

export function formatDuration(ms: number) {
  const total = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export function formatElapsedLabel(ms: number) {
  const total = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h} 小时 ${m} 分`;
  if (m > 0) return s > 0 ? `${m} 分 ${s} 秒` : `${m} 分钟`;
  return `${s} 秒`;
}

export function formatClock(ts: number) {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export function formatDateTitle(ts = Date.now()) {
  const d = new Date(ts);
  const week = ["日", "一", "二", "三", "四", "五", "六"][d.getDay()];
  return {
    date: `${d.getMonth() + 1}月${d.getDate()}日`,
    weekday: `星期${week}`,
  };
}

export function startOfDay(ts = Date.now()) {
  const d = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function elapsedMs(sessions: { start: number; end?: number }[], clock: number) {
  return sessions.reduce((sum, session) => sum + Math.max(0, (session.end ?? clock) - session.start), 0);
}

export function taskElapsed(
  task: {
    sessions?: { start: number; end?: number }[];
    startedAt?: number;
    pausedAt?: number;
    completedAt?: number;
    status?: string;
  },
  clock: number,
) {
  const fromSessions = elapsedMs(task.sessions ?? [], clock);
  if (fromSessions > 0) return fromSessions;
  if (!task.startedAt) return 0;
  const end = task.status === "doing" ? clock : (task.completedAt ?? task.pausedAt ?? clock);
  return Math.max(0, end - task.startedAt);
}

export function formatWhen(ts: number) {
  const d = new Date(ts);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  if (sameDay) return `今天 ${hh}:${mm}`;
  return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
}

export function latestNote(notes: { text: string }[]) {
  return notes.at(-1)?.text ?? "";
}

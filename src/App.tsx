import { useEffect, useMemo, useRef, useState, type FormEvent, type PointerEvent } from "react";
import {
  addDays,
  addMonths,
  formatClock,
  formatDateTitle,
  formatDuration,
  formatElapsedLabel,
  formatJump,
  formatMonthTitle,
  latestNote,
  monthGrid,
  parseCapture,
  parsePlans,
  parseReminder,
  sameMonth,
  startOfDay,
  startOfMonth,
  taskDay,
  taskElapsed,
} from "./parseCapture";
import { speechSupported, listenOnce } from "./speech";
import type { Task } from "./types";
import { useNowdo } from "./useNowdo";
import { openJump } from "./api";
import { Guide, markGuideSeen, openGuideHash, shouldAutoOpenGuide } from "./Guide";

function MicIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
      <path
        fill="currentColor"
        d="M12 14a3 3 0 0 0 3-3V6a3 3 0 0 0-6 0v5a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2z"
      />
    </svg>
  );
}

function PauseIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
      <path fill="currentColor" d="M7 5h4v14H7V5zm6 0h4v14h-4V5z" />
    </svg>
  );
}

export default function App() {
  const n = useNowdo();
  const [draft, setDraft] = useState("");
  const [listening, setListening] = useState(false);
  const [speechError, setSpeechError] = useState("");
  const [showGuide, setShowGuide] = useState(false);

  useEffect(() => {
    const sync = () => {
      if (window.location.hash === "#guide") {
        setShowGuide(true);
        return;
      }
      if (!n.ready) return;
      setShowGuide(shouldAutoOpenGuide(n.tasks.length));
    };
    sync();
    window.addEventListener("hashchange", sync);
    return () => window.removeEventListener("hashchange", sync);
  }, [n.ready, n.tasks.length]);

  function closeGuide() {
    markGuideSeen();
    setShowGuide(false);
  }

  async function submitCapture(text = draft) {
    const value = text.trim();
    if (!value) return;
    if (typeof Notification !== "undefined" && Notification.permission === "default") {
      void Notification.requestPermission().catch(() => undefined);
    }
    n.capture(value);
    setDraft("");
    setSpeechError("");
  }

  async function onMic() {
    if (!speechSupported()) {
      setSpeechError("这个浏览器还不支持语音，先打字。");
      return;
    }
    setListening(true);
    setSpeechError("");
    try {
      const text = await listenOnce();
      setDraft(text);
      await submitCapture(text);
    } catch {
      setSpeechError("没听清，再试一次，或直接打字。");
    } finally {
      setListening(false);
    }
  }

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    void submitCapture();
  }

  const todayStart = startOfDay(n.clock);
  const viewed = formatDateTitle(n.viewDay);
  const monthStart = startOfMonth(n.viewDay);
  const cells = monthGrid(monthStart);
  const dayCounts = useMemo(() => {
    const counts = new Map<number, number>();
    for (const task of n.tasks) {
      const day = taskDay(task);
      counts.set(day, (counts.get(day) ?? 0) + 1);
    }
    return counts;
  }, [n.tasks]);
  const swipe = useRef<{ x: number; target: "cal" | "axis" } | null>(null);

  function goMonth(delta: number) {
    const next = addMonths(monthStart, delta);
    n.setViewDay(sameMonth(next, todayStart) ? todayStart : next);
  }

  function onPointerDown(target: "cal" | "axis", event: PointerEvent<HTMLElement>) {
    swipe.current = { x: event.clientX, target };
  }

  function onPointerUp(event: PointerEvent<HTMLElement>) {
    if (!swipe.current) return;
    const dx = event.clientX - swipe.current.x;
    const target = swipe.current.target;
    swipe.current = null;
    if (Math.abs(dx) < 60) return;
    if (target === "cal") goMonth(dx > 0 ? -1 : 1);
    else n.shiftDay(dx > 0 ? -1 : 1);
  }

  return (
    <div className="app">
      <header className="top">
        <div>
          <div className="brand">nowdo</div>
          <p className="motto">一万年太久，只争朝夕</p>
          <p className="credit">designed by even</p>
        </div>
        <button type="button" className="guide-link" onClick={openGuideHash}>
          怎么用
        </button>
      </header>

      <section
        className="month-cal"
        aria-label="日历"
        onPointerDown={(event) => onPointerDown("cal", event)}
        onPointerUp={onPointerUp}
        onPointerCancel={() => {
          swipe.current = null;
        }}
      >
        <div className="month-bar">
          <button type="button" className="month-nav" aria-label="上个月" onClick={() => goMonth(-1)}>
            ‹
          </button>
          <h2>{formatMonthTitle(monthStart)}</h2>
          <button type="button" className="month-nav" aria-label="下个月" onClick={() => goMonth(1)}>
            ›
          </button>
        </div>
        <div className="month-weeks">
          {["日", "一", "二", "三", "四", "五", "六"].map((week) => (
            <span key={week}>{week}</span>
          ))}
        </div>
        <div className="month-grid">
          {cells.map((day) => (
            <button
              key={day}
              type="button"
              className={`month-cell${day === n.viewDay ? " is-on" : ""}${day === todayStart ? " is-today" : ""}${sameMonth(day, monthStart) ? "" : " is-out"}`}
              onClick={() => n.setViewDay(day)}
            >
              {new Date(day).getDate()}
              {(dayCounts.get(day) ?? 0) > 0 ? <i className="month-dot" aria-hidden="true" /> : null}
            </button>
          ))}
        </div>
      </section>

      <form className="capture" onSubmit={onSubmit}>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={listening ? "在听…" : "想到哪，说出来"}
          autoFocus
        />
        <button
          type="button"
          className={`icon-btn ${listening ? "live" : ""}`}
          onClick={() => void onMic()}
          aria-label="语音"
        >
          <MicIcon />
        </button>
      </form>
      <div className="capture-meta">
        <button
          type="button"
          className={`split-switch${n.settings.autoSplit ? " is-on" : ""}`}
          aria-pressed={n.settings.autoSplit}
          onClick={() => n.updateSettings({ autoSplit: !n.settings.autoSplit })}
        >
          <span>自动拆分</span>
          <span className="switch-track" aria-hidden="true">
            <i />
          </span>
        </button>
        {n.settings.autoSplit ? <span className="split-hint">说完会按日期和事项拆开</span> : <span className="split-hint">整句记成一条</span>}
      </div>
      {n.settings.autoSplit && draft.trim() ? <SplitPreview text={draft} clock={n.clock} /> : null}
      {speechError ? <p className="hint">{speechError}</p> : null}

      {n.doingTasks.length > 0 ? (
        <section className="section">
          <h2>正在做{n.doingTasks.length > 1 ? ` · ${n.doingTasks.length} 件并行` : ""}</h2>
          <div className="doing-list">
            {n.doingTasks.map((task) => (
              <DoingCard
                key={task.id}
                task={task}
                clock={n.clock}
                onPause={() => n.askPause(task.id)}
                onDone={() => n.askComplete(task.id)}
                onJump={() => task.jump && void openJump(task.jump)}
              />
            ))}
          </div>
        </section>
      ) : null}

      <section
        className="section"
        onPointerDown={(event) => onPointerDown("axis", event)}
        onPointerUp={onPointerUp}
        onPointerCancel={() => {
          swipe.current = null;
        }}
      >
        <h2>{axisHeading(n.viewDay, todayStart, viewed)}</h2>
        {n.todayAxis.length === 0 ? (
          <div className="empty">
            {n.viewDay < todayStart ? "这天还没有留下。" : "想到就做。先说出来。"}
          </div>
        ) : (
          <ol className="timeline">
            {n.todayAxis.map(({ task }) => (
              <AxisItem
                key={task.id}
                task={task}
                clock={n.clock}
                onContinue={() => n.askContinue(task.id)}
              />
            ))}
          </ol>
        )}
      </section>

      {n.pauseTask ? (
        <PauseSheet
          task={n.pauseTask}
          onCancel={n.cancelPause}
          onConfirm={(text) => n.confirmPause(n.pauseTask!.id, text)}
        />
      ) : null}

      {n.completePrompt ? (
        <PauseSheet
          task={n.completePrompt}
          title="做到哪了"
          confirmLabel="完成这条"
          onCancel={n.cancelComplete}
          onConfirm={(text) => n.completeSegment(n.completePrompt!.id, text)}
        />
      ) : null}

      {n.continueTask ? (
        <ContinueSheet
          task={n.continueTask}
          onStart={(sub) => void n.startTask(n.continueTask!.id, sub)}
          onRemind={(ms) => n.snooze(n.continueTask!.id, ms)}
          onClose={n.cancelContinue}
        />
      ) : null}

      {n.reminderTask ? (
        <ReminderSheet
          task={n.reminderTask}
          onDo={(sub) => {
            if (n.reminderTask?.status === "doing") n.dismissReminder();
            else void n.startTask(n.reminderTask!.id, sub);
          }}
          onRemind={(ms) => n.snooze(n.reminderTask!.id, ms)}
        />
      ) : null}

      <p className="share-note">
        网页版 nowdo，可添加到主屏幕。任务记录保存在当前设备的浏览器里，不会自动同步或备份；清理浏览器数据会删除记录。
        语音识别由浏览器提供，可能使用在线服务。请保持页面开启；关闭页面、后台运行或锁屏时，不保证准时提醒。
        <button type="button" className="guide-inline" onClick={openGuideHash}>
          看使用教程
        </button>
      </p>

      {showGuide ? <Guide onClose={closeGuide} /> : null}
    </div>
  );
}

function SplitPreview({ text, clock }: { text: string; clock: number }) {
  const today = startOfDay(clock);
  const plans = parsePlans(text, clock, { split: true });
  const rows = plans.flatMap((plan, planIndex) => {
    const when = plan.afterQuery
      ? `等 ${plan.afterQuery} 之后`
      : plan.scheduledFor === today
        ? plan.remindAt
          ? formatClock(plan.remindAt)
          : "今天"
        : formatDateTitle(plan.scheduledFor).date;
    return [plan.title, ...plan.parts].map((title, index) => ({
      key: `${planIndex}-${index}-${title}`,
      title,
      when: index === 0 ? when : undefined,
    }));
  });
  if (plans.length < 2 && (plans[0]?.parts.length ?? 0) === 0) return null;

  return (
    <ul className="split-preview">
      {rows.map((row) => (
        <li key={row.key}>
          {row.when ? <span>{row.when}</span> : null}
          {row.title}
        </li>
      ))}
    </ul>
  );
}

function axisHeading(viewDay: number, today: number, viewed: { date: string; weekday: string }) {
  if (viewDay === today) return "今天任务轴";
  if (viewDay === addDays(today, 1)) return "明天任务轴";
  if (viewDay === addDays(today, -1)) return "昨天 · 复盘";
  if (viewDay < today) return `${viewed.date} · 复盘`;
  return `${viewed.date}任务轴`;
}

function AxisItem({
  task,
  clock,
  onContinue,
}: {
  task: Task;
  clock: number;
  onContinue: () => void;
}) {
  const subs = task.subs ?? [];

  return (
    <li className={`timeline-item is-${task.status}`} id={`task-${task.id}`}>
      <div className="timeline-rail" aria-hidden="true" />
      <div className="timeline-card">
        {task.remindAt || task.waitForText ? (
          <div className="axis-when">
            {task.remindAt ? <span>{formatClock(task.remindAt)}</span> : null}
            {task.waitForText ? <span>等 {task.waitForText} 之后</span> : null}
          </div>
        ) : null}
        <h3 className="timeline-title">{task.title}</h3>
        {subs.length > 0 ? (
          <ul className="sub-list">
            {subs.map((sub) => {
              const live = subLiveMs(task, sub, clock);
              return (
                <li key={sub.id} className={`sub-line is-${sub.status}`}>
                  <span className="sub-text">{sub.text || "进行中"}</span>
                  {live > 0 ? <span className="sub-time">{formatElapsedLabel(live)}</span> : null}
                </li>
              );
            })}
          </ul>
        ) : null}
        {task.status !== "doing" ? (
          <div className="axis-actions">
            <button className="primary" type="button" onClick={onContinue}>
              继续
            </button>
          </div>
        ) : null}
      </div>
    </li>
  );
}

function subLiveMs(task: Task, sub: Task["subs"][number], clock: number) {
  if (sub.status !== "doing") return sub.elapsedMs ?? 0;
  const open = [...(task.sessions ?? [])].reverse().find((session) => !session.end);
  const live = open ? Math.max(0, clock - open.start) : 0;
  return (sub.elapsedMs ?? 0) + live;
}

function DoingCard({
  task,
  clock,
  onPause,
  onDone,
  onJump,
}: {
  task: Task;
  clock: number;
  onPause: () => void;
  onDone: () => void;
  onJump: () => void;
}) {
  const worked = taskElapsed(task, clock);
  return (
    <article className="card doing-card" id={`doing-${task.id}`}>
      <div className="kicker">
        <span>并行中</span>
        {task.jump ? <span>{formatJump(task.jump)}</span> : null}
      </div>
      <h3 className="title">{task.title}</h3>
      {currentSubText(task) ? <p className="note">{currentSubText(task)}</p> : null}
      <div className="timer">{formatDuration(worked)}</div>
      <p className="timer-sub">已做 {formatElapsedLabel(worked)}</p>
      <div className="actions">
        {task.jump ? (
          <button className="ghost" type="button" onClick={onJump}>
            跳过去
          </button>
        ) : null}
        <button className="icon-btn pause-btn" type="button" onClick={onPause} aria-label="暂停">
          <PauseIcon />
        </button>
        <button className="primary doing" type="button" onClick={onDone}>
          做完了
        </button>
      </div>
    </article>
  );
}

function currentSubText(task: Task) {
  const doing = [...(task.subs ?? [])].reverse().find((sub) => sub.status === "doing");
  const open = [...(task.subs ?? [])].reverse().find((sub) => sub.status === "open");
  return doing?.text || open?.text || latestNote(task.notes);
}

function PauseSheet({
  task,
  onCancel,
  onConfirm,
  title = "做到哪了",
  confirmLabel = "记下",
}: {
  task: Task;
  onCancel: () => void;
  onConfirm: (text: string) => void;
  title?: string;
  confirmLabel?: string;
}) {
  const [text, setText] = useState("");
  const [listening, setListening] = useState(false);

  useEffect(() => {
    setText("");
  }, [task.id]);

  return (
    <div className="overlay" onClick={onCancel}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        <div className="command-row">
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="自己记下进度"
            autoFocus
          />
          <button
            className={`icon-btn ${listening ? "live" : ""}`}
            type="button"
            aria-label="语音"
            onClick={async () => {
              if (!speechSupported()) return;
              setListening(true);
              try {
                setText(await listenOnce());
              } finally {
                setListening(false);
              }
            }}
          >
            <MicIcon />
          </button>
        </div>
        <div className="actions">
          <button className="ghost" type="button" onClick={onCancel}>
            还不停
          </button>
          <button className="primary" type="button" disabled={!text.trim()} onClick={() => onConfirm(text)}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function CommandSheet({
  title,
  task,
  onStart,
  onRemind,
  onClose,
}: {
  title: string;
  task: Task;
  onStart: (sub?: string) => void;
  onRemind: (ms: number) => void;
  onClose?: () => void;
}) {
  const [text, setText] = useState("");
  const [listening, setListening] = useState(false);
  const [error, setError] = useState("");
  const last = currentSubText(task);

  function apply(value: string, startNow = false) {
    const remind = parseReminder(value);
    const parsed = parseCapture(value);
    const sub = parsed.title && parsed.title !== task.title ? parsed.title : !remind ? value.trim() : "";
    if (remind != null) {
      onRemind(remind);
      return true;
    }
    if (sub) {
      onStart(sub);
      return true;
    }
    if (startNow) {
      onStart();
      return true;
    }
    return Boolean(remind);
  }

  return (
    <div className="overlay" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        <p>
          <strong style={{ color: "var(--ink)" }}>{task.title}</strong>
          {last ? (
            <>
              <br />
              {last}
            </>
          ) : null}
        </p>
        <div className="command-row">
          <input
            type="text"
            value={text}
            onChange={(e) => {
              setText(e.target.value);
              setError("");
            }}
            placeholder="下一条进度，或几点提醒"
            autoFocus
            onKeyDown={(event) => {
              if (event.key !== "Enter") return;
              event.preventDefault();
              if (!apply(text)) setError("写下下一条，或几点提醒");
            }}
          />
          <button
            className={`icon-btn ${listening ? "live" : ""}`}
            type="button"
            aria-label="语音"
            onClick={async () => {
              if (!speechSupported()) return;
              setListening(true);
              try {
                const spoken = await listenOnce();
                setText(spoken);
                if (!apply(spoken)) setError("写下下一条，或几点提醒");
              } finally {
                setListening(false);
              }
            }}
          >
            <MicIcon />
          </button>
        </div>
        {error ? <p className="hint">{error}</p> : null}
        <div className="actions">
          <button className="primary" type="button" onClick={() => apply(text, true)}>
            现在做
          </button>
        </div>
      </div>
    </div>
  );
}

function ContinueSheet({
  task,
  onStart,
  onRemind,
  onClose,
}: {
  task: Task;
  onStart: (sub?: string) => void;
  onRemind: (ms: number) => void;
  onClose: () => void;
}) {
  return (
    <CommandSheet title="继续" task={task} onStart={onStart} onRemind={onRemind} onClose={onClose} />
  );
}

function ReminderSheet({
  task,
  onDo,
  onRemind,
}: {
  task: Task;
  onDo: (sub?: string) => void;
  onRemind: (ms: number) => void;
}) {
  return <CommandSheet title="到点了" task={task} onStart={onDo} onRemind={onRemind} />;
}

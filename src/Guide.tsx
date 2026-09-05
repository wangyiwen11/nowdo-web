import { useEffect, useState } from "react";

const LINE = "提醒我中午11点50回家，拿充电器和鼠标，顺便取个快递";

const SCENES = [
  {
    id: "speak",
    kicker: "01",
    title: "想到就说",
    caption: "不用整理。说一句或打一句，nowdo 自己拆开。",
    hold: 5200,
  },
  {
    id: "split",
    kicker: "02",
    title: "自动拆成任务",
    caption: "日期、时间、主任务、子任务，会落在日历和任务轴上。",
    hold: 4800,
  },
  {
    id: "start",
    kicker: "03",
    title: "现在做",
    caption: "点开始，正计时跟着走。可以同时做几件。",
    hold: 4200,
  },
  {
    id: "pause",
    kicker: "04",
    title: "停下来先写做到哪了",
    caption: "暂停必须留下进度。回头才接得上，不会断掉。",
    hold: 4800,
  },
  {
    id: "resume",
    kicker: "05",
    title: "回来接着做",
    caption: "同一条主任务继续。做完的是子任务，标题不划掉。",
    hold: 4200,
  },
  {
    id: "home",
    kicker: "06",
    title: "加到主屏幕",
    caption: "浏览器打开后「添加到主屏幕」，用起来像小程序。记录只在这台设备。",
    hold: 5200,
  },
] as const;

type SceneId = (typeof SCENES)[number]["id"];

export function Guide({ onClose }: { onClose: () => void }) {
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(true);
  const scene = SCENES[index];

  useEffect(() => {
    if (!playing) return;
    const timer = window.setTimeout(() => {
      if (index >= SCENES.length - 1) {
        setPlaying(false);
        return;
      }
      setIndex((current) => current + 1);
    }, scene.hold);
    return () => window.clearTimeout(timer);
  }, [index, playing, scene.hold]);

  return (
    <div className="guide" role="dialog" aria-label="nowdo 使用教程">
      <div className="guide-top">
        <div>
          <div className="guide-brand">nowdo</div>
          <p>30 秒看怎么用</p>
        </div>
        <button type="button" className="ghost" onClick={onClose}>
          进入 nowdo
        </button>
      </div>

      <div className="guide-stage">
        <DemoPhone scene={scene.id} playing={playing} />
      </div>

      <div className="guide-copy">
        <span className="guide-kicker">{scene.kicker} / 06</span>
        <h2>{scene.title}</h2>
        <p>{scene.caption}</p>
      </div>

      <div className="guide-dots" aria-hidden="true">
        {SCENES.map((item, i) => (
          <button
            key={item.id}
            type="button"
            className={i === index ? "is-on" : ""}
            onClick={() => {
              setIndex(i);
              setPlaying(true);
            }}
          />
        ))}
      </div>

      <div className="guide-controls">
        <button
          type="button"
          className="ghost"
          onClick={() => {
            if (index >= SCENES.length - 1 && !playing) {
              setIndex(0);
              setPlaying(true);
              return;
            }
            setPlaying((value) => !value);
          }}
        >
          {playing ? "暂停" : index >= SCENES.length - 1 ? "重播" : "继续"}
        </button>
        {index < SCENES.length - 1 ? (
          <button
            type="button"
            className="primary"
            onClick={() => {
              setIndex((current) => current + 1);
              setPlaying(true);
            }}
          >
            下一步
          </button>
        ) : (
          <button type="button" className="primary" onClick={onClose}>
            自己试
          </button>
        )}
      </div>
    </div>
  );
}

function DemoPhone({ scene, playing }: { scene: SceneId; playing: boolean }) {
  const typed = useTyped(scene === "speak" || scene === "split" ? LINE : LINE, scene === "speak" && playing);

  return (
    <div className="demo-phone" aria-hidden="true">
      <div className="demo-brand">nowdo</div>
      <div className="demo-cal">
        <b>2026年9月</b>
        <div className="demo-days">
          {["日", "一", "二", "三", "四", "五", "六"].map((week) => (
            <span key={week}>{week}</span>
          ))}
          {Array.from({ length: 14 }, (_, i) => (
            <i key={i} className={i === 5 ? "is-on" : ""}>
              {i + 1}
            </i>
          ))}
        </div>
      </div>

      <div className={`demo-input${scene === "speak" ? " is-live" : ""}`}>
        <span>{scene === "speak" ? typed || "想到哪，说出来" : LINE}</span>
        <em />
      </div>

      {scene === "speak" || scene === "split" ? (
        <ul className={`demo-split${scene === "split" || typed.length > 18 ? " is-show" : ""}`}>
          <li>
            <span>今天 11:50</span>回家
          </li>
          <li>拿充电器</li>
          <li>拿鼠标</li>
          <li>取个快递</li>
        </ul>
      ) : null}

      {scene === "start" ? (
        <article className="demo-doing">
          <small>并行中</small>
          <h3>回家</h3>
          <p>拿充电器</p>
          <strong>00:12</strong>
        </article>
      ) : null}

      {scene === "pause" ? (
        <div className="demo-sheet">
          <h3>做到哪了</h3>
          <p>充电器还没拿，快递在丰巢。</p>
          <div className="demo-sheet-actions">
            <span>还不停</span>
            <b>记下</b>
          </div>
        </div>
      ) : null}

      {scene === "resume" || scene === "split" || scene === "home" ? (
        <div className="demo-axis">
          <h4>今天任务轴</h4>
          <div className="demo-task">
            <small>11:50</small>
            <h3>回家</h3>
            <ul>
              <li className={scene === "resume" || scene === "home" ? "is-done" : ""}>拿充电器</li>
              <li>拿鼠标</li>
              <li>取个快递</li>
            </ul>
            {scene !== "split" ? <em>继续</em> : null}
          </div>
        </div>
      ) : null}

      {scene === "home" ? <p className="demo-home">Safari / Chrome → 添加到主屏幕</p> : null}

      {scene === "speak" && !typed ? <p className="demo-empty">想到就做。先说出来。</p> : null}
    </div>
  );
}

function useTyped(text: string, active: boolean) {
  const [count, setCount] = useState(active ? 0 : text.length);

  useEffect(() => {
    if (!active) {
      setCount(text.length);
      return;
    }
    setCount(0);
    const timer = window.setInterval(() => {
      setCount((current) => {
        if (current >= text.length) {
          window.clearInterval(timer);
          return current;
        }
        return current + 1;
      });
    }, 42);
    return () => window.clearInterval(timer);
  }, [active, text]);

  return text.slice(0, count);
}

export function shouldAutoOpenGuide(taskCount: number) {
  if (typeof window === "undefined") return false;
  if (window.location.hash === "#guide") return true;
  if (taskCount > 0) return false;
  return window.localStorage.getItem("nowdo-web:seen-guide") !== "1";
}

export function markGuideSeen() {
  window.localStorage.setItem("nowdo-web:seen-guide", "1");
  if (window.location.hash === "#guide") {
    window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}`);
  }
}

export function openGuideHash() {
  window.location.hash = "guide";
}

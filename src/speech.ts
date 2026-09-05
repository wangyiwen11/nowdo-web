type SpeechCtor = new () => SpeechRecognitionLike;

interface SpeechRecognitionLike {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  onresult: ((event: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
  onerror: ((event: { error?: string }) => void) | null;
  onend: (() => void) | null;
  start: () => void;
  stop: () => void;
}

function getCtor(): SpeechCtor | null {
  const w = window as unknown as {
    SpeechRecognition?: SpeechCtor;
    webkitSpeechRecognition?: SpeechCtor;
  };
  return w.SpeechRecognition || w.webkitSpeechRecognition || null;
}

export function speechSupported() {
  return Boolean(getCtor());
}

export function listenOnce(lang = "zh-CN"): Promise<string> {
  const Ctor = getCtor();
  if (!Ctor) return Promise.reject(new Error("no-speech"));

  return new Promise((resolve, reject) => {
    const rec = new Ctor();
    rec.lang = lang;
    rec.interimResults = true;
    rec.continuous = false;
    let finalText = "";

    rec.onresult = (event) => {
      const last = event.results[event.results.length - 1];
      const text = last?.[0]?.transcript?.trim() ?? "";
      if (text) finalText = text;
    };
    rec.onerror = (event) => {
      reject(new Error(event.error || "speech-error"));
    };
    rec.onend = () => {
      if (finalText) resolve(finalText);
      else reject(new Error("empty"));
    };

    try {
      rec.start();
    } catch (error) {
      reject(error);
    }
  });
}

export function createListener(options: {
  onPartial?: (text: string) => void;
  lang?: string;
}) {
  const Ctor = getCtor();
  if (!Ctor) return null;

  const rec = new Ctor();
  rec.lang = options.lang ?? "zh-CN";
  rec.interimResults = true;
  rec.continuous = true;
  let last = "";

  rec.onresult = (event) => {
    const lastResult = event.results[event.results.length - 1];
    const text = lastResult?.[0]?.transcript?.trim() ?? "";
    if (text) {
      last = text;
      options.onPartial?.(text);
    }
  };

  return {
    start() {
      rec.start();
    },
    stop() {
      rec.stop();
      return last;
    },
  };
}

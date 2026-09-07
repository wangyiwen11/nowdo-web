import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../public/sw.js", import.meta.url), "utf8");
const base = "https://wangyiwen11.github.io/nowdo-web/";

function setup() {
  const handlers = new Map();
  const entries = new Map();
  const added = [];
  const deleted = [];
  const cache = {
    async addAll(urls) {
      added.push(...urls);
      for (const url of urls) {
        entries.set(url, new Response(url.endsWith("index.html")
          ? '<script type="module" src="/nowdo-web/assets/app-123.js"></script><link rel="stylesheet" href="/nowdo-web/assets/app-123.css">'
          : "cached"));
      }
    },
    async match(request) { return entries.get(typeof request === "string" ? request : request.url)?.clone(); },
    async put(request, response) { entries.set(request.url, response); },
  };
  const context = {
    URL, Response,
    self: {
      location: { href: base + "sw.js" },
      addEventListener(type, listener) { handlers.set(type, listener); },
      async skipWaiting() {},
      clients: { async claim() {} },
    },
    caches: {
      async open() { return cache; },
      async keys() { return ["nowdo-web:/nowdo-web/:v1", "another-app-v1"]; },
      async delete(key) { deleted.push(key); },
    },
    async fetch() { throw new Error("offline"); },
  };
  vm.runInNewContext(source, context);
  async function lifecycle(type) {
    let promise;
    handlers.get(type)({ waitUntil(value) { promise = value; } });
    await promise;
  }
  function fetchPage(url, mode = "navigate") {
    let promise;
    handlers.get("fetch")({ request: { url, method: "GET", mode }, respondWith(value) { promise = value; } });
    return promise;
  }
  return { lifecycle, fetchPage, added, deleted };
}

test("worker precaches the GitHub subpath shell and its real hashed bundles", async () => {
  const app = setup();
  await app.lifecycle("install");
  assert.ok(app.added.includes(base + "index.html"));
  assert.ok(app.added.includes(base + "assets/app-123.js"));
  assert.ok(app.added.includes(base + "assets/app-123.css"));
  assert.ok(app.added.every((url) => url.startsWith(base)));
});

test("offline navigation falls back to the app shell, missing assets do not get HTML", async () => {
  const app = setup();
  await app.lifecycle("install");
  const page = await app.fetchPage(base + "?source=share");
  assert.match(await page.text(), /assets\/app-123\.js/);
  const missing = await app.fetchPage(base + "missing.js", "cors");
  assert.equal(missing.type, "error");
  assert.equal(app.fetchPage("https://wangyiwen11.github.io/another-app/"), undefined);
});

test("worker activation only removes its own earlier cache", async () => {
  const app = setup();
  await app.lifecycle("activate");
  assert.deepEqual(app.deleted, ["nowdo-web:/nowdo-web/:v1"]);
});

import test from "node:test";
import assert from "node:assert/strict";
import { addDays, captureDay, parsePlan, parsePlans, parseReminder, startOfDay } from "../src/parseCapture.ts";

const at = new Date(2026, 8, 7, 9, 0, 0).getTime();
const today = startOfDay(at);
const tomorrow = addDays(today, 1);

for (const separator of ["；", ";", "，", ",", "。", "\n"]) {
  test(`different dates remain different tasks: ${JSON.stringify(separator)}`, () => {
    const plans = parsePlans(`今天整理演示素材${separator}明天下午3点检查发布文案`, at);
    assert.equal(plans.length, 2);
    assert.equal(plans[0].title, "整理演示素材");
    assert.equal(plans[0].scheduledFor, today);
    assert.equal(plans[0].remindAt, undefined);
    assert.equal(plans[1].title, "检查发布文案");
    assert.equal(plans[1].scheduledFor, tomorrow);
    assert.equal(new Date(plans[1].remindAt).getHours(), 15);
    assert.deepEqual(plans.map((plan) => plan.parts), [[], []]);
  });
}

test("tutorial example keeps one task with three ordered parts", () => {
  const [plan] = parsePlans("提醒我中午11点50回家，拿充电器和鼠标，顺便取个快递", at);
  assert.equal(plan.title, "回家");
  assert.deepEqual(plan.parts, ["拿充电器", "拿鼠标", "取个快递"]);
  assert.equal(new Date(plan.remindAt).getHours(), 11);
  assert.equal(new Date(plan.remindAt).getMinutes(), 50);
});

test("date only sets the day without inventing a reminder", () => {
  const plan = parsePlan("明天整理材料", at);
  assert.equal(plan.scheduledFor, tomorrow);
  assert.equal(plan.remindAt, undefined);
});

test("reminder command and new capture use the same full date and time", () => {
  const timestamp = new Date(2026, 8, 8, 15).getTime();
  assert.equal(parseReminder("明天下午3点", at), timestamp - at);
  assert.equal(parsePlan("明天下午3点检查发布", at).remindAt, timestamp);
  assert.equal(parsePlan("明天下午3点", at).title, "");
});

test("relative reminder does not create a fake task or get truncated", () => {
  assert.equal(parseReminder("10分钟后", at), 600000);
  assert.equal(parsePlan("10分钟后", at).title, "");
  assert.deepEqual(parsePlans("10分钟后", at), []);
  assert.equal(parseReminder("11小时后", at), 11 * 3600000);
  assert.equal(parseReminder("130分钟后", at), 130 * 60000);
  assert.equal(parsePlan("今天10分钟后检查", at).remindAt, at + 600000);
});

test("a passed clock means its next occurrence unless today was explicit", () => {
  assert.equal(parsePlan("8点检查", at).remindAt, new Date(2026, 8, 8, 8).getTime());
  assert.equal(parsePlan("今天8点检查", at).remindAt, new Date(2026, 8, 7, 8).getTime());
});

test("automatic splitting can still be disabled", () => {
  const plans = parsePlans("回家，拿充电器和鼠标", at, { split: false });
  assert.equal(plans.length, 1);
  assert.equal(plans[0].title, "回家，拿充电器和鼠标");
  assert.deepEqual(plans[0].parts, []);
});

test("a URL by itself is saved and semicolons within URLs are preserved", () => {
  for (const input of ["https://example.com/docs.html", "阅读 https://example.com/a;b"]) {
    const plans = parsePlans(input, at);
    assert.equal(plans.length, 1);
    assert.ok(plans[0].title);
    assert.equal(plans[0].jump.value, input.replace(/^阅读 /, ""));
  }
});

test("a comma between a date and its clock does not lose the date", () => {
  for (const input of ["明天，下午3点检查", "明天写文案，下午3点校对"]) {
    const plans = parsePlans(input, at);
    assert.equal(plans.length, 1);
    assert.equal(plans[0].scheduledFor, tomorrow);
    assert.equal(new Date(plans[0].remindAt).getHours(), 15);
  }
});

test("capture view follows a host created earlier in the same input", () => {
  const plans = parsePlans("明天写文案；等写文案完成后检查标题", at);
  assert.equal(captureDay(plans, [], at), tomorrow);
});

test("a Chinese semicolon ends a URL task before a new dated task", () => {
  const plans = parsePlans("今天阅读 https://example.com/docs.html；明天下午3点检查文案", at);
  assert.equal(plans.length, 2);
  assert.equal(plans[0].scheduledFor, today);
  assert.equal(plans[0].jump.value, "https://example.com/docs.html");
  assert.equal(plans[1].scheduledFor, tomorrow);
  assert.equal(plans[1].title, "检查文案");
});

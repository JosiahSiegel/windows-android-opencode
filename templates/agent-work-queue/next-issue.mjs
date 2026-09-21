#!/usr/bin/env node
// The queue driver for the agent work queue (see docs/agent-work-queue.md).
//
// No dependencies. Prints the next open item, or updates an item's result.
//
//   node next-issue.mjs [--backlog agent/backlog.json] [--brief]
//   node next-issue.mjs --status
//   node next-issue.mjs --set UX-014 --status fixed --commit abc1234 --verified "669 tests pass"
//
// Exit codes: 0 = work remains (or update applied), 3 = nothing open, 2 = usage/IO error.
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const SEVERITY = { high: 0, medium: 1, low: 2 };
const VALID_STATUS = new Set(["open", "fixed", "blocked", "wontfix"]);
const args = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : dflt;
};
const has = (name) => args.includes(name);

const backlogPath = resolve(flag("--backlog", "agent/backlog.json"));
const self = process.argv[1];

function load() {
  try {
    return JSON.parse(readFileSync(backlogPath, "utf8"));
  } catch (err) {
    console.error(`could not read ${backlogPath}: ${err.message}`);
    process.exit(2);
  }
}
function save(doc) {
  writeFileSync(backlogPath, `${JSON.stringify(doc, null, 2)}\n`);
}
function rank(item) {
  return SEVERITY[item.severity] ?? 9;
}

function brief(item) {
  const lines = [
    `# ${item.id} [${item.severity}] ${item.title}`,
    item.area ? `area: ${item.area}` : null,
    "",
    `Problem: ${item.problem}`,
    item.evidence && item.evidence.length ? `Evidence: ${item.evidence.join(", ")}` : null,
    `Acceptance: ${item.acceptance}`,
    item.check ? `Check: ${item.check}` : null,
    item.touch && item.touch.length ? `Touch: ${item.touch.join(", ")}` : null,
    "",
    "Do only this item. Reproduce it first if it is a defect, make the smallest change that meets",
    "the acceptance check, verify with the named check, commit this item alone, then record it:",
    `  node ${self} --set ${item.id} --status fixed --commit <sha> --verified "<evidence>"`,
    "If it fails the check three times, record it instead:",
    `  node ${self} --set ${item.id} --status blocked --note "<smallest unblocking action>"`,
  ];
  return lines.filter((l) => l !== null).join("\n");
}

if (has("--set")) {
  const id = flag("--set");
  const doc = load();
  const item = doc.items.find((x) => x.id === id);
  if (!item) {
    console.error(`no such item: ${id}`);
    process.exit(2);
  }
  const status = flag("--status", item.status);
  if (!VALID_STATUS.has(status)) {
    console.error(`invalid status: ${status} (expected one of ${[...VALID_STATUS].join(", ")})`);
    process.exit(2);
  }
  item.status = status;
  if (flag("--commit")) item.commit = flag("--commit");
  if (flag("--verified")) item.verified = flag("--verified");
  if (flag("--note")) item.note = flag("--note");
  save(doc);
  console.log(`${id} -> ${item.status}${item.commit ? ` (${item.commit})` : ""}`);
  process.exit(0);
}

const doc = load();
const counts = doc.items.reduce((acc, it) => {
  acc[it.status] = (acc[it.status] ?? 0) + 1;
  return acc;
}, {});
if (has("--status")) {
  console.log(JSON.stringify(counts));
  process.exit((counts.open ?? 0) > 0 ? 0 : 3);
}

const open = doc.items.filter((it) => it.status === "open").sort((a, b) => rank(a) - rank(b));
if (!open.length) {
  console.log(`Nothing open. ${JSON.stringify(counts)}`);
  process.exit(3);
}
console.log(has("--brief") ? brief(open[0]) : `${open[0].id} [${open[0].severity}] ${open[0].title} (open: ${open.length})`);

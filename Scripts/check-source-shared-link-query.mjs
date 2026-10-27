import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";
import assert from "node:assert/strict";
import path from "node:path";

const [reference, token] = process.argv.slice(2);
assert.equal(execFileSync("git", ["-C", reference, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
  "91bd24bb8513785c7364cbea29296ff7adafac41");
const source = readFileSync(path.join(reference, "frontend/src/ts/utils/misc.ts"), "utf8");
const start = source.indexOf("export function findGetParameter(");
const end = source.indexOf("\nexport function checkIfGetParameterExists", start);
assert.ok(start >= 0 && end > start);
// Execute the complete pinned query helper. location.search is the only
// platform boundary; no reimplementation of query selection is injected.
const code = stripTypeScriptTypes(source.slice(start, end).replace(/^export /, ""));
const queries = [
  "?testSettings=" + token,
  "?testSettings=bad&testSettings=" + token,
  "?testSettings=" + token + "&testSettings=bad",
  "?ignored=1&testSettings=" + encodeURIComponent(token),
  "?%74estSettings=" + token,
  "?testSettings=" + token + "=ignored",
  "?testSettings=%ZZ",
  "?testSettings",
  "?testSettings=",
  "?ignored=" + token,
];
const fixtures = queries.map(query => {
  try {
    const value = vm.runInNewContext(code + '\nfindGetParameter("testSettings");', { location: { search: query } });
    return { query, value, failed: false };
  } catch {
    return { query, value: null, failed: true };
  }
});
process.stdout.write(JSON.stringify({ fixtures }));

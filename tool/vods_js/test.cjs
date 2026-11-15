// The test of the built JS module `ongVods` under Node, run by tool/vods_js_test.sh:
//
//   node tool/vods_js/test.cjs <ong_vods.js> <expected.json>
//
// <expected.json>: the calls and what the app's code gives for each on the Dart VM (tool/vods_js/expected.dart).
// Checks that the file loads as a classic script in a context without `window`, `document` or `self`, defines
// `ongVods` and nothing else, starts nothing (no timer, no request), calls neither `eval` nor `new Function`, has the
// interface of the specification, gives the same results as the Dart code for every call, and throws an `Error`
// with the same message where the Dart code fails. Exits with 1 on any difference.
'use strict';
const fs = require('fs');
const vm = require('vm');

const [jsPath, expectedPath] = process.argv.slice(2);
if (!jsPath || !expectedPath) {
  console.error('usage: node tool/vods_js/test.cjs <ong_vods.js> <expected.json>');
  process.exit(64);
}
const source = fs.readFileSync(jsPath, 'utf8');
const cases = JSON.parse(fs.readFileSync(expectedPath, 'utf8'));

let failures = 0, passes = 0;
function check(ok, what, detail) {
  if (ok) {
    passes++;
  } else {
    failures++;
    console.log(`FAIL ${what}${detail === undefined ? '' : `\n  ${detail}`}`);
  }
}

// what a page or a worker could start: recorded, never run
const started = [];
const stubs = {};
for (const name of ['setTimeout', 'setInterval', 'setImmediate', 'queueMicrotask', 'requestAnimationFrame', 'fetch',
  'XMLHttpRequest', 'importScripts', 'postMessage', 'addEventListener']) {
  stubs[name] = function () { started.push(name); };
}

const builtins = new Set(vm.runInContext('Object.getOwnPropertyNames(globalThis)', vm.createContext({})));

/// A context where the module was just loaded, without DOM, timers or `eval`.
function fresh() {
  const context = vm.createContext({ ...stubs }, { codeGeneration: { strings: false, wasm: false } });
  vm.runInContext(source, context, { filename: 'ong_vods.js' });
  return context;
}

// ------------------------------------------------------------------ the file
check(!/\beval\(|new Function\b|\bFunction\(/.test(source), 'the file calls neither eval nor new Function');
const t0 = process.hrtime.bigint();
const context = fresh();
console.log(`loaded in ${(Number(process.hrtime.bigint() - t0) / 1e6).toFixed(1)} ms (${source.length} characters)`);
check(started.length === 0, 'nothing started on load', started.join(', '));
const globals = vm.runInContext('Object.getOwnPropertyNames(globalThis)', context)
  .filter((name) => !builtins.has(name) && !(name in stubs));
check(JSON.stringify(globals) === '["ongVods"]', 'only ongVods defined', JSON.stringify(globals));
for (const name of ['window', 'document', 'self']) {
  check(vm.runInContext(`typeof ${name}`, context) === 'undefined', `no ${name} in the context`);
}

// ------------------------------------------------------------------ the interface
const ongVods = context.ongVods;
check(JSON.stringify(Object.keys(ongVods).sort()) ===
  JSON.stringify(['load', 'offsetsHeader', 'overview', 'replaceOffsets', 'sheets', 'stream', 'version']),
  'the members of ongVods', JSON.stringify(Object.keys(ongVods)));
for (const fn of ['load', 'overview', 'stream', 'replaceOffsets']) {
  check(typeof ongVods[fn] === 'function', `${fn} is a function`);
}
check(typeof ongVods.version === 'string' && ongVods.version.length > 0, 'version', ongVods.version);
console.log(`version: ${ongVods.version}`);
check(JSON.stringify(Object.keys(ongVods.sheets).sort()) === '["highlights","songs"]', 'sheets');

// arguments that are not strings
for (const [fn, args, message] of [
  ['load', [1, ''], 'songsCsv must be a string'],
  ['load', ['', undefined], 'highlightsCsv must be a string'],
  ['overview', ['', null], 'offsetsTsv must be a string'],
  ['stream', ['', '', 5], 'videoId must be a string'],
  ['replaceOffsets', ['', '2024-01-02', []], 'offsetsJson must be a string'],
]) {
  try {
    fresh().ongVods[fn](...args);
    check(false, `${fn}(${args.map(String)}) throws`);
  } catch (e) {
    check(e.message === message, `${fn} with an argument that is not a string`, e.message);
  }
}

// ------------------------------------------------------------------ the calls
const files = new Map();
function text(arg) {
  if (typeof arg === 'string') return arg;
  if (!files.has(arg.file)) files.set(arg.file, fs.readFileSync(arg.file, 'utf8'));
  return files.get(arg.file);
}
function label(c) {
  const args = c.args.map((a) => typeof a === 'string' ? JSON.stringify(a.length > 40 ? `${a.slice(0, 40)}...` : a)
    : a.file.split('/').pop());
  return `${c.fresh ? '(fresh) ' : ''}${c.fn}(${args.join(', ')})`;
}
function firstDifference(a, b) {
  let i = 0;
  while (i < a.length && a[i] === b[i]) i++;
  return `at ${i}:\n  js:   ${JSON.stringify(a.slice(Math.max(0, i - 60), i + 80))}\n  dart: ${JSON.stringify(b.slice(Math.max(0, i - 60), i + 80))}`;
}

const timings = {};
for (const c of cases) {
  if (c.fn === 'constants') {
    check(JSON.stringify(ongVods.sheets) === JSON.stringify(c.result.sheets), 'sheets', JSON.stringify(ongVods.sheets));
    check(ongVods.offsetsHeader === c.result.offsetsHeader, 'offsetsHeader', JSON.stringify(ongVods.offsetsHeader));
    continue;
  }
  const where = c.fresh ? fresh() : context;
  const target = where.ongVods;
  const args = c.args.map(text);
  const t = process.hrtime.bigint();
  let result, error;
  try {
    result = target[c.fn](...args);
  } catch (e) {
    error = e;
  }
  const ms = Number(process.hrtime.bigint() - t) / 1e6;
  (timings[c.fn] ??= []).push(ms);
  if ('error' in c) {
    check(error !== undefined, `${label(c)} throws`, `gave ${JSON.stringify(result)?.slice(0, 200)}`);
    if (error !== undefined) {
      check(error instanceof vm.runInContext('Error', where), `${label(c)} throws an Error`,
        Object.prototype.toString.call(error));
      check(error.message === c.error, `${label(c)}: the message`, `js: ${error.message}\n  dart: ${c.error}`);
    }
  } else if (error !== undefined) {
    check(false, `${label(c)} does not throw`, error && error.message);
  } else if (typeof c.result === 'string') {
    check(result === c.result, `${label(c)}: as the Dart code`,
      typeof result === 'string' ? firstDifference(result, c.result) : `gave ${typeof result}`);
  } else {
    check(result === c.result, `${label(c)}: as the Dart code`, `js: ${result}, dart: ${c.result}`);
  }
}
for (const [fn, list] of Object.entries(timings)) {
  const sorted = [...list].sort((a, b) => a - b);
  console.log(`${fn}: ${list.length} calls, median ${sorted[sorted.length >> 1].toFixed(1)} ms, ` +
    `max ${sorted[sorted.length - 1].toFixed(1)} ms`);
}
console.log(`${passes} checks passed, ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

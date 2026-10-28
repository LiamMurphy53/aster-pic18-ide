#!/usr/bin/env node
// client for aster's claude bridge: sends one operation and prints the json reply
// usage: node Tools/aster-bridge.cjs [--dir folder] [--timeout s] [--value] <op> [json-args]
'use strict';
const fs = require('fs'), path = require('path'), os = require('os'), crypto = require('crypto');

const argv = process.argv.slice(2);
let dir = process.env.ASTER_BRIDGE || '', timeout = 150, valueOnly = false;
const rest = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--dir') dir = argv[++i];
  else if (argv[i] === '--timeout') timeout = Number(argv[++i]);
  else if (argv[i] === '--value') valueOnly = true;
  else rest.push(argv[i]);
}
const [op, raw] = rest;
if (!op) {
  console.error('usage: aster-bridge [--dir folder] [--timeout s] [--value] <op> [json-args]');
  process.exit(2);
}
if (!dir) {
  // same folder seen from the mac and from claude's linux shell
  const candidates = [path.join(os.homedir(), 'Desktop/Github/.aster-bridge'), path.join(os.homedir(), 'mnt/Github/.aster-bridge')];
  dir = candidates.find(d => fs.existsSync(d)) || candidates[0];
}
let args = {};
try { args = raw ? JSON.parse(raw) : {}; } catch (e) { console.error('args must be json: ' + e.message); process.exit(2); }

function fail(message) { console.error(message); process.exit(1); }

let status;
try { status = JSON.parse(fs.readFileSync(path.join(dir, 'status.json'), 'utf8')); } catch { fail('no bridge at ' + dir + ' (open aster and turn on project > claude bridge)'); }
if (!status.enabled) fail('aster has the bridge turned off');
if (Date.now() / 1000 - status.unix > 6) fail('aster is not responding (last heartbeat ' + status.updated + '); is it still open?');

const id = Date.now().toString(36) + '-' + crypto.randomBytes(4).toString('hex');
const requests = path.join(dir, 'requests'), response = path.join(dir, 'responses', id + '.json');
const tmp = path.join(requests, '.' + id + '.tmp');
fs.writeFileSync(tmp, JSON.stringify({ op, args }));
fs.renameSync(tmp, path.join(requests, id + '.json'));

const deadline = Date.now() + timeout * 1000;
(function wait() {
  let text;
  try { text = fs.readFileSync(response, 'utf8'); } catch {}
  if (text) {
    let reply;
    try { reply = JSON.parse(text); } catch { return setTimeout(wait, 50); }
    if (valueOnly && reply.ok) console.log(typeof reply.value === 'string' ? reply.value : JSON.stringify(reply.value, null, 2));
    else console.log(JSON.stringify(reply, null, 2));
    process.exit(reply.ok ? 0 : 1);
  }
  if (Date.now() > deadline) fail('timed out after ' + timeout + ' s waiting for ' + op + ' (request ' + id + ' may still be running)');
  setTimeout(wait, 100);
})();

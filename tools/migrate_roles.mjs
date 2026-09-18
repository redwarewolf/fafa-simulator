// One-off migration: `"role": <0-3>` -> `"role": "<POSITION KEY>"`.
//
// The four old roles were stored as raw enum ordinals, so the ten positions
// could not be added without silently reinterpreting every existing file.
// Run once from the repo root:  node tools/migrate_roles.mjs
//
// The assignment below is mechanical — it produces a valid, plausible squad,
// not a scouted one. Expect to hand-tune a handful of players afterwards.

import fs from 'node:fs';
import path from 'node:path';

const GOALIE = 0, DEFENCE = 1, MIDFIELD = 2, ATTACK = 3;

// Highest `pac` in the back line goes to the full-back slots: they are the ones
// asked to cover the whole touchline. Everyone else is a centre back.
function assignDefence(players) {
  const fastest = [...players].sort((a, b) => b.pac - a.pac).slice(0, 2);
  const flanks = players.filter((p) => fastest.includes(p));
  const out = new Map();
  if (flanks[0]) out.set(flanks[0], 'LB');
  if (flanks[1]) out.set(flanks[1], 'RB');
  for (const p of players) if (!out.has(p)) out.set(p, 'CB');
  return out;
}

// Best defender of the midfield sits; best shooter of the rest pushes on.
function assignMidfield(players) {
  const out = new Map();
  if (players.length === 0) return out;
  const holder = [...players].sort((a, b) => b.def - a.def)[0];
  out.set(holder, 'CDM');
  const rest = players.filter((p) => p !== holder);
  if (rest.length > 0) {
    const creator = [...rest].sort((a, b) => b.sho - a.sho)[0];
    out.set(creator, 'CAM');
  }
  for (const p of players) if (!out.has(p)) out.set(p, 'CM');
  return out;
}

// Best shooter leads the line, the rest fill the wings in file order.
function assignAttack(players) {
  const out = new Map();
  if (players.length === 0) return out;
  const striker = [...players].sort((a, b) => b.sho - a.sho)[0];
  out.set(striker, 'ST');
  const wings = ['LW', 'RW'];
  let i = 0;
  for (const p of players) if (!out.has(p)) out.set(p, wings[i++ % 2]);
  return out;
}

function migrateSquad(players) {
  const byRole = { [GOALIE]: [], [DEFENCE]: [], [MIDFIELD]: [], [ATTACK]: [] };
  for (const p of players) {
    if (typeof p.role !== 'number') return 0; // already migrated
    byRole[p.role]?.push(p);
  }
  const assigned = new Map();
  for (const p of byRole[GOALIE]) assigned.set(p, 'GK');
  for (const [p, k] of assignDefence(byRole[DEFENCE])) assigned.set(p, k);
  for (const [p, k] of assignMidfield(byRole[MIDFIELD])) assigned.set(p, k);
  for (const [p, k] of assignAttack(byRole[ATTACK])) assigned.set(p, k);
  for (const [p, k] of assigned) p.role = k;
  return assigned.size;
}

function rewrite(file, migrate) {
  const raw = fs.readFileSync(file, 'utf8');
  const data = JSON.parse(raw);
  const n = migrate(data);
  if (n === 0) {
    console.log(`skip  ${file} (already migrated)`);
    return;
  }
  fs.writeFileSync(file, JSON.stringify(data, null, '\t') + '\n');
  console.log(`ok    ${file} — ${n} players`);
}

const clubDir = path.join('assets', 'json', 'clubs');
for (const name of fs.readdirSync(clubDir).filter((f) => f.endsWith('.json'))) {
  rewrite(path.join(clubDir, name), (club) => migrateSquad(club.players ?? []));
}

// squads.json is not read by any script today, but leaving a second role
// encoding in the repo is how the next person gets caught out.
rewrite(path.join('assets', 'json', 'squads.json'), (squads) =>
  squads.reduce((n, s) => n + migrateSquad(s.players ?? []), 0),
);

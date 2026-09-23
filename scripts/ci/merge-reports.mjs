import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [root, shardCountText] = process.argv.slice(2);
const shardCount = Number(shardCountText);
if (!root || !Number.isInteger(shardCount) || shardCount < 1) {
  throw new Error('Usage: node merge-reports.mjs <artifact-dir> <shard-count>');
}

const ids = { suite: new Map(), group: new Map(), test: new Map() };
function id(kind, shard, old) {
  if (old === null || old === undefined) return old;
  const key = `${shard}:${old}`;
  if (!ids[kind].has(key)) ids[kind].set(key, ids[kind].size + 1);
  return ids[kind].get(key);
}

const mergedEvents = [];
const sources = new Map();
let suiteCount = 0;
let allSucceeded = true;
let timeOffset = 0;

for (let shard = 0; shard < shardCount; shard++) {
  const directory = join(root, `test-shard-${shard}`);
  const events = readFileSync(join(directory, 'test-results.json'), 'utf8')
    .trim().split(/\r?\n/).map((line) => JSON.parse(line));
  if (events[0]?.type !== 'start' || events.at(-1)?.type !== 'done') {
    throw new Error(`Shard ${shard} has an incomplete Flutter test stream`);
  }
  if (shard === 0) mergedEvents.push(events[0]);
  allSucceeded &&= events.at(-1).success === true;
  const count = events.find((event) => event.type === 'allSuites');
  if (!count) throw new Error(`Shard ${shard} has no allSuites event`);
  suiteCount += count.count;
  let lastTime = 0;
  for (const event of events.slice(1, -1)) {
    if (event.type === 'allSuites') continue;
    lastTime = Math.max(lastTime, event.time ?? 0);
    event.time = (event.time ?? 0) + timeOffset;
    if ('suiteID' in event) event.suiteID = id('suite', shard, event.suiteID);
    if ('testID' in event) event.testID = id('test', shard, event.testID);
    if ('groupID' in event) event.groupID = id('group', shard, event.groupID);
    for (const kind of ['suite', 'group', 'test']) {
      const item = event[kind];
      if (!item) continue;
      item.id = id(kind, shard, item.id);
      if ('suiteID' in item) item.suiteID = id('suite', shard, item.suiteID);
      if ('groupIDs' in item) item.groupIDs = item.groupIDs.map((value) => id('group', shard, value));
      if ('parentID' in item) item.parentID = id('group', shard, item.parentID);
    }
    mergedEvents.push(event);
  }
  timeOffset += lastTime;

  const trace = readFileSync(join(directory, 'coverage/lcov.info'), 'utf8');
  for (const block of trace.split('end_of_record')) {
    const lines = block.trim().split(/\r?\n/);
    const path = lines.find((line) => line.startsWith('SF:'))?.slice(3);
    if (!path) continue;
    if (!sources.has(path)) {
      sources.set(path, { functions: new Map(), functionHits: new Map(), lines: new Map(), branches: new Map() });
    }
    const source = sources.get(path);
    for (const line of lines) {
      if (line.startsWith('FN:')) {
        const definition = line.slice(3);
        source.functions.set(definition.slice(definition.lastIndexOf(',') + 1), definition);
      } else if (line.startsWith('FNDA:')) {
        const [hits, ...name] = line.slice(5).split(',');
        const key = name.join(',');
        source.functionHits.set(key, (source.functionHits.get(key) ?? 0) + Number(hits));
      } else if (line.startsWith('DA:')) {
        const [number, hits, checksum] = line.slice(3).split(',');
        const previous = source.lines.get(number);
        source.lines.set(number, { hits: (previous?.hits ?? 0) + Number(hits), checksum: checksum ?? previous?.checksum });
      } else if (line.startsWith('BRDA:')) {
        const [number, blockId, branch, taken] = line.slice(5).split(',');
        const key = `${number},${blockId},${branch}`;
        const previous = source.branches.get(key);
        source.branches.set(key, taken === '-' ? previous ?? null : (previous ?? 0) + Number(taken));
      }
    }
  }
}

mergedEvents.splice(1, 0, { type: 'allSuites', time: 0, count: suiteCount });
mergedEvents.push({ type: 'done', time: timeOffset, success: allSucceeded });
writeFileSync('test-results.json', `${mergedEvents.map((event) => JSON.stringify(event)).join('\n')}\n`);

const traceLines = [];
for (const [path, source] of [...sources].sort(([a], [b]) => a.localeCompare(b))) {
  traceLines.push(`SF:${path}`);
  for (const definition of source.functions.values()) traceLines.push(`FN:${definition}`);
  for (const [name, hits] of source.functionHits) traceLines.push(`FNDA:${hits},${name}`);
  if (source.functions.size) {
    traceLines.push(`FNF:${source.functions.size}`, `FNH:${[...source.functionHits.values()].filter((hits) => hits > 0).length}`);
  }
  for (const [number, { hits, checksum }] of [...source.lines].sort(([a], [b]) => Number(a) - Number(b))) {
    traceLines.push(`DA:${number},${hits}${checksum ? `,${checksum}` : ''}`);
  }
  traceLines.push(`LF:${source.lines.size}`, `LH:${[...source.lines.values()].filter(({ hits }) => hits > 0).length}`);
  for (const [key, taken] of source.branches) traceLines.push(`BRDA:${key},${taken ?? '-'}`);
  if (source.branches.size) {
    traceLines.push(`BRF:${source.branches.size}`, `BRH:${[...source.branches.values()].filter((taken) => taken > 0).length}`);
  }
  traceLines.push('end_of_record');
}
if (!sources.size) throw new Error('No lcov source records found');
mkdirSync('coverage', { recursive: true });
writeFileSync('coverage/lcov.info', `${traceLines.join('\n')}\n`);
console.log(`Merged ${shardCount} shards, ${suiteCount} suites, ${sources.size} coverage sources`);

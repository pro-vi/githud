import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

const exec = promisify(execFile);
export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const owners = ['sample','exampleorg','anotherorg'];
const fail = message => { throw new Error(message); };
const assert = (condition, message) => { if (!condition) fail(message); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const string = value => typeof value === 'string' && value.length > 0;
export const canonical = value => JSON.stringify(sort(value));
function sort(value) {
  if (Array.isArray(value)) return value.map(sort);
  if (object(value)) return Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])]));
  return value;
}
export const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const equal = (a,b) => canonical(a) === canonical(b);
function keys(value, required, label) {
  assert(object(value), `${label}: expected object`);
  assert(equal(Object.keys(value).sort(), [...required].sort()), `${label}: unknown or missing fields`);
}
function strings(value, label) {
  assert(Array.isArray(value) && value.every(string), `${label}: expected string array`);
  assert(new Set(value).size === value.length, `${label}: duplicate values`);
}
function github(value, row = false) {
  if (value === null) return;
  assert(string(value), 'URL missing');
  const url = new URL(value);
  assert(url.protocol === 'https:' && url.hostname === 'github.com' && !url.port && !url.username && !url.password, 'URL must be GitHub HTTPS');
  assert(owners.includes(url.pathname.split('/')[1]) || (!row && url.pathname === '/search'), 'URL must use synthetic owner');
}

export function assertData(metadata, fixture, id = 'quick-navigator') {
  keys(metadata, ['schema_version','id','title','status','selected_variant','plan','fixture','default_scenario','implementation','superseded_by','history','scenarios'], 'metadata');
  assert(metadata.schema_version === 1 && fixture.schema_version === 1, 'unsupported schema version');
  assert(metadata.id === id && /^[a-z][a-z0-9-]*$/.test(id), 'invalid prototype ID');
  assert(string(metadata.title) && string(metadata.plan) && string(metadata.fixture), 'missing metadata strings');
  assert(['exploring','selected','implemented','superseded'].includes(metadata.status), 'unknown status');
  assert(string(metadata.selected_variant) || (!['selected','implemented'].includes(metadata.status) && metadata.selected_variant === null), 'selected variant required');
  assert(metadata.superseded_by === null || string(metadata.superseded_by), 'invalid superseded reference');
  assert((metadata.status === 'superseded') === string(metadata.superseded_by), 'superseded reference required only when superseded');
  assert(metadata.status !== 'implemented' || object(metadata.implementation), 'implemented status requires evidence');
  if (metadata.implementation !== null) {
    keys(metadata.implementation, ['commit','design_fingerprint','evidence'], 'implementation');
    assert(/^[a-f0-9]{40}$/.test(metadata.implementation.commit), 'implementation commit must be full SHA');
    assert(/^[a-f0-9]{64}$/.test(metadata.implementation.design_fingerprint), 'invalid design fingerprint');
    assert(string(metadata.implementation.evidence), 'missing evidence path');
  }
  assert(Array.isArray(metadata.history) && metadata.history.length > 0, 'history missing');
  for (const entry of metadata.history) {
    keys(entry, ['date','actor','change','why','reference'], 'history');
    assert(Object.values(entry).every(string) && /^\d{4}-\d{2}-\d{2}$/.test(entry.date), 'invalid history entry');
  }
  keys(fixture, ['schema_version','provenance','now','self_login','row_sets'], 'fixture');
  assert(fixture.provenance === 'synthetic' && owners.includes(fixture.self_login), 'fixture must be synthetic');
  assert(string(fixture.now) && Number.isFinite(Date.parse(fixture.now)), 'fixture clock invalid');
  assert(object(fixture.row_sets) && Object.keys(fixture.row_sets).length > 0, 'row sets missing');
  for (const [name, set] of Object.entries(fixture.row_sets)) {
    const allIDs = new Set();
    keys(set, ['radar','inbound','pulse'], `row set ${name}`);
    for (const [lane, rows] of Object.entries(set)) {
      assert(Array.isArray(rows), 'lane must be array');
      for (const row of rows) {
        const base = ['id','repo','title','subtitle','timestamp','symbolName','url','changeSignature'];
        const extra = lane === 'radar' ? ['urgency','isCritical','excerpt'] : lane === 'inbound' ? ['isPR','isHeldBack'] : ['state','isDraft','isStale','isFresh','merge','headBranch'];
        keys(row, [...base,...extra], 'row');
        assert(base.filter(k => k !== 'url').every(k => string(row[k])), 'row string missing');
        assert(!allIDs.has(row.id) && row.id !== 'jump:github', 'duplicate global row ID'); allIDs.add(row.id);
        assert(owners.includes(row.repo.split('/')[0]), 'row owner must be synthetic');
        assert(lane === 'radar' || string(row.url), 'pulse/inbound URL required'); github(row.url, true);
        assert(Number.isFinite(Date.parse(row.timestamp)), 'row timestamp invalid');
        for (const k of extra.filter(k => k.startsWith('is'))) assert(typeof row[k] === 'boolean', `invalid ${k}`);
        if (lane === 'pulse') {
          assert(['ready','blocked','waiting','draft'].includes(row.state), 'unknown pulse state');
          assert(['mergeable','conflicting','unknown'].includes(row.merge), 'unknown merge state');
          assert(row.headBranch === null || typeof row.headBranch === 'string', 'invalid branch');
        }
        if (lane === 'radar') assert(Number.isFinite(row.urgency) && (row.excerpt === null || typeof row.excerpt === 'string'), 'invalid radar fields');
      }
    }
  }
  assert(Array.isArray(metadata.scenarios) && metadata.scenarios.length > 0, 'scenario catalog empty');
  strings(metadata.scenarios.map(s=>s.id),'scenario IDs');
  assert(metadata.scenarios.every(s=>/^[a-z][a-z0-9-]*$/.test(s.id)), 'invalid scenario ID');
  assert(metadata.scenarios.some(s=>s.id === metadata.default_scenario), 'default scenario missing');
  for (const scenario of metadata.scenarios) {
    keys(scenario, ['id','label','row_set','query','session','freshness','preferences','expected'], 'scenario');
    assert(string(scenario.label) && typeof scenario.query === 'string', 'invalid scenario text');
    assert(['keyboard','mouse'].includes(scenario.session) && ['fresh','loading','offline'].includes(scenario.freshness), 'unknown scenario state');
    assert(Object.hasOwn(fixture.row_sets, scenario.row_set), 'unknown row set');
    const set=fixture.row_sets[scenario.row_set];
    const rows = [...set.radar,...set.inbound,...set.pulse];
    const ids = rows.map(r => r.id);
    keys(scenario.preferences, ['showDrafts','showStale','showHeldBack','foldedOwners','groupByOwner','ownerOrder'], 'preferences');
    for (const k of ['showDrafts','showStale','showHeldBack','groupByOwner']) assert(typeof scenario.preferences[k] === 'boolean', 'invalid preference');
    for (const k of ['foldedOwners','ownerOrder']) { strings(scenario.preferences[k], k); assert(scenario.preferences[k].every(v => owners.includes(v)), 'unknown preference owner'); }
    const e = scenario.expected;
    keys(e, ['matched_ids','local_ids','count','walk','selected_id','destination','open_url','browse_ids'], 'expected');
    for (const k of ['matched_ids','local_ids','browse_ids']) { strings(e[k], k); assert(e[k].every(v => ids.includes(v)), 'expected ID outside row set'); }
    assert(equal(e.matched_ids,ids.filter(id=>e.matched_ids.includes(id))), 'matched IDs must retain source order');
    strings(e.walk, 'walk');
    const active = scenario.session === 'keyboard' && scenario.query.trim() !== '';
    assert(equal(e.walk, scenario.session === 'mouse' ? [] : [...e.local_ids, ...(active ? ['jump:github'] : [])]), 'walk must equal visible rows and terminal destination');
    assert(e.selected_id === (e.walk[0] ?? null), 'initial selection must be first walk row');
    assert(active ? equal(e.local_ids,e.matched_ids) : equal(e.local_ids,e.browse_ids), 'local result contract mismatch');
    assert(e.count === (active && e.matched_ids.length ? `${e.matched_ids.length} of ${ids.length}` : null), 'count mismatch');
    assert(active === (e.destination !== null), 'destination presence mismatch');
    github(e.destination); github(e.open_url);
    const selectedURL = e.selected_id === 'jump:github' ? e.destination : rows.find(r => r.id === e.selected_id)?.url ?? null;
    assert(e.open_url === selectedURL, 'open URL mismatch');
  }
}

export async function contained(root, base, reference) {
  assert(string(reference) && !path.isAbsolute(reference) && !reference.includes('://'), 'reference must be relative');
  const target = await fs.realpath(path.resolve(base, reference.split('#')[0]));
  const relative = path.relative(await fs.realpath(root), target);
  assert(relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative), 'reference escapes repository');
  return target;
}
export function dataBlock(html) {
  const scripts = [...html.matchAll(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi)].filter(m => /\bid\s*=\s*(?:"prototype-data"|'prototype-data'|prototype-data(?=\s|$))/i.test(m[0].split('>')[0]));
  assert(scripts.length === 1, 'expected exactly one prototype-data script');
  assert(/\btype\s*=\s*["']application\/json["']/i.test(scripts[0][0].split('>')[0]), 'prototype-data must be inert JSON');
  return scripts[0];
}
export function designFingerprint(html, metadata, fixture) {
  const block = dataBlock(html);
  const design = {...metadata};
  for (const k of ['status','history','implementation','superseded_by']) delete design[k];
  return sha256(canonical([html.slice(0,block.index)+'<!-- prototype-data -->'+html.slice(block.index+block[0].length),fixture,design]));
}
export function embed(html, metadata, fixture) {
  const block = dataBlock(html);
  const payload = {metadata,fixture,provenance:{metadata_sha256:sha256(canonical(metadata)),fixture_sha256:sha256(canonical(fixture)),design_fingerprint:designFingerprint(html,metadata,fixture)}};
  const json = canonical(payload).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
  return html.slice(0,block.index)+`<script id="prototype-data" type="application/json">${json}</script>`+html.slice(block.index+block[0].length);
}
export function assertOffline(html) {
  assert(/http-equiv=["']Content-Security-Policy["']/i.test(html) && /default-src\s+'none'/i.test(html) && /connect-src\s+'none'/i.test(html), 'offline CSP required');
  assert(!/<(?:script|img|iframe|link|video|audio|source)\b[^>]*\b(?:src|href)\s*=/i.test(html), 'external asset attributes forbidden');
  const styles=[...html.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi)].map(m=>m[1]).join('\n');
  const inlineStyles=[...html.matchAll(/\bstyle\s*=\s*(["'])(.*?)\1/gi)].map(m=>m[2]).join('\n');
  assert(!/@import\b|url\s*\(/i.test(styles+'\n'+inlineStyles), 'CSS imports/assets forbidden');
}
export async function loadPrototype(id, root = ROOT) {
  assert(typeof id === 'string' && /^[a-z][a-z0-9-]*$/.test(id), 'invalid prototype ID');
  const directory = path.join(root,'docs/design/prototypes');
  const metadataPath = await contained(directory,directory,`${id}.json`);
  const htmlPath = await contained(directory,directory,`${id}.html`);
  const metadataSource = await fs.readFile(metadataPath,'utf8');
  const metadata = JSON.parse(metadataSource);
  const fixturePath = await contained(path.join(root,'Tests/Fixtures'),directory,metadata.fixture);
  const fixtureSource = await fs.readFile(fixturePath,'utf8');
  const fixture = JSON.parse(fixtureSource);
  const html = await fs.readFile(htmlPath,'utf8');
  assertData(metadata,fixture,id); assertOffline(html);
  await contained(root,directory,metadata.plan);
  if (metadata.superseded_by) await contained(root,directory,metadata.superseded_by);
  const fingerprint = designFingerprint(html,metadata,fixture);
  if (metadata.implementation) {
    assert(metadata.implementation.design_fingerprint === fingerprint, 'stale implementation fingerprint');
    const evidence=await contained(root,root,metadata.implementation.evidence);
    assert((await fs.stat(evidence)).isFile(), 'implementation evidence must be a file');
    await exec('git',['cat-file','-e',`${metadata.implementation.commit}^{commit}`],{cwd:root});
  }
  return {metadata,fixture,html,htmlPath,metadataPath,fixturePath,metadataSource,fixtureSource,fingerprint};
}
export async function syncPrototype(id, root = ROOT, beforeWrite = async () => {}) {
  const input = await loadPrototype(id,root);
  const updated = embed(input.html,input.metadata,input.fixture);
  if (updated === input.html) return false;
  const temp = `${input.htmlPath}.${crypto.randomUUID()}.tmp`;
  try {
    await fs.writeFile(temp,updated,{flag:'wx'});
    await beforeWrite();
    assert(await contained(path.join(root,'docs/design/prototypes'),path.join(root,'docs/design/prototypes'),`${id}.html`)===input.htmlPath,'source path changed during sync');
    for (const [file,source] of [[input.htmlPath,input.html],[input.metadataPath,input.metadataSource],[input.fixturePath,input.fixtureSource]]) {
      assert(await fs.realpath(file) === file, 'source path changed during sync');
      assert(await fs.readFile(file,'utf8') === source, 'source changed during sync');
    }
    await fs.rename(temp,input.htmlPath);
  } finally { await fs.rm(temp,{force:true}); }
  return true;
}
export async function checkPrototype(id,root=ROOT) {
  const input = await loadPrototype(id,root);
  assert(input.html === embed(input.html,input.metadata,input.fixture), 'embedded data stale: run sync');
  return input;
}

export async function verifyPrototype(id,root=ROOT) {
  const input = await checkPrototype(id,root);
  const directory = await fs.mkdtemp(path.join(os.tmpdir(),'githud-prototype-'));
  const session = `githud-prototype-${crypto.randomUUID()}`;
  const call = async (...args) => {
    const {stdout} = await exec('agent-browser',['--session',session,'--allow-file-access','--json',...args],{timeout:20000,maxBuffer:4*1024*1024});
    const result = JSON.parse(stdout);
    assert(result.success !== false, `browser failure: ${stdout}`);
    return result.data?.result ?? result.data;
  };
  const state = () => call('eval','window.prototypeState()');
  const witnesses=[];
  try {
    await call('set','viewport','1280','1200');
    await call('open',pathToFileURL(input.htmlPath).href);
    await call('set','offline','on');
    const catalog = await call('eval',"Array.from(document.querySelector('#scenario').options, o => o.value)");
    assert(equal(catalog,input.metadata.scenarios.map(s=>s.id)), 'DOM catalog differs');
    for (const scenario of input.metadata.scenarios) {
      await call('select','#scenario',scenario.id);
      const observed = await state(), e=scenario.expected;
      const expected={scenario:scenario.id,query:scenario.query,session:scenario.session==='keyboard',expanded:true,matchedIDs:e.matched_ids,localIDs:e.local_ids,walk:e.walk,selectedID:e.selected_id,count:e.count,destination:e.destination,preferences:scenario.preferences};
      for(const [key,value] of Object.entries(expected)) assert(equal(observed[key],value), `${scenario.id}: ${key}: ${canonical(observed[key])} != ${canonical(value)}`);
      const DOMids=await call('eval',"Array.from(document.querySelectorAll('#results [data-row-id]'),r=>r.dataset.rowId)");
      assert(equal(DOMids,[...e.local_ids,...(e.destination?['jump:github']:[])]), `${scenario.id}: DOM row order`);
      const rowsVisible=await call('eval',"Array.from(document.querySelectorAll('#results [data-row-id]')).every(row=>{const r=row.getBoundingClientRect();if(r.width<=0||r.height<=0)return false;if(row.checkVisibility)return row.checkVisibility({checkOpacity:true,checkVisibilityCSS:true});for(let p=row;p;p=p.parentElement){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||s.visibility==='collapse'||Number(s.opacity)===0)return false;}return true;})");
      assert(rowsVisible,`${scenario.id}: materialized rows must be visible with positive area`);
      if(scenario.session==='keyboard') {
        await call('press','Enter'); const opened=await state();
        assert(opened.openedURL===e.open_url, `${scenario.id}: Enter receipt`);
        assert(!opened.expanded&&!opened.session, `${scenario.id}: Enter ends session and collapses`);
        await call('select','#scenario',scenario.id);
        if(scenario.query.length) {
          await call('press','Escape'); const cleared=await state();
          assert(cleared.query===''&&cleared.session&&equal(cleared.localIDs,e.browse_ids)&&equal(cleared.preferences,scenario.preferences),`${scenario.id}: clear restores browse`);
        }
        await call('press','Escape'); const dismissed=await state();
        assert(!dismissed.expanded&&!dismissed.session,`${scenario.id}: Escape ends session and collapses`);
      } else {
        const inputVisible=await call('eval',"(() => { const q=document.querySelector('#query'); return !!q && q.getClientRects().length>0 && getComputedStyle(q).visibility!=='hidden'; })()");
        assert(!inputVisible,`${scenario.id}: mouse query field must be hidden`);
      }
      witnesses.push({scenario:scenario.id,result:'pass'});
    }
    const matching=input.metadata.scenarios.find(s=>s.session==='keyboard'&&s.query.trim()&&s.expected.local_ids.length===1);
    if(matching) {
      await call('select','#scenario',matching.id); await call('fill','#query','no-such-prefix'); assert((await state()).selectedID==='jump:github','zero prefix destination');
      await call('fill','#query',matching.query); assert((await state()).selectedID===matching.expected.local_ids[0],'new query selects local');
      await call('press','ArrowDown'); assert((await state()).selectedID==='jump:github','arrow chooses fallback');
      await call('eval',"document.querySelector('#query').dispatchEvent(new Event('input',{bubbles:true}))");
      assert((await state()).selectedID==='jump:github','unchanged query preserves arrow choice');
      await call('press','ArrowUp'); assert((await state()).selectedID===matching.expected.local_ids[0],'arrow returns local');
    }
    await call('open','about:blank');
    await call('open',pathToFileURL(input.htmlPath).href+'#scenario=not-a-scenario'); assert((await state()).scenario===null,'unknown hash must not silently substitute a scenario');
    await call('open','about:blank');
    await call('open',pathToFileURL(input.htmlPath).href);
    await call('eval',"location.hash = 'scenario=not-a-scenario'");
    await call('wait','--fn','window.prototypeState().scenario === null');
    assert((await state()).scenario===null,'hot unknown hash must retire previous scenario');
    await call('eval',`location.hash = ${JSON.stringify('scenario='+input.metadata.default_scenario+'&height=normal')}`);
    await call('wait','--fn',`window.prototypeState().scenario === ${JSON.stringify(input.metadata.default_scenario)}`);
    assert((await state()).scenario===input.metadata.default_scenario,'valid hash restores scenario after error');
    const crowded=[...input.metadata.scenarios].sort((a,b)=>b.expected.local_ids.length-a.expected.local_ids.length)[0];
    await call('select','#scenario',crowded.id);
    for(const height of ['normal','short']) {
      await call('click',`button[data-height="${height}"]`);
      const overflow=await call('eval','document.documentElement.scrollWidth > window.innerWidth');
      assert(!overflow,`${height}: horizontal overflow`);
      await call('screenshot',path.join(directory,`${height}.png`));
    }
    await call('click','#query');
    for(let index=1;index<crowded.expected.walk.length;index++) {
      await call('press','ArrowDown');
      const visible=await call('eval',"(() => { const row=document.querySelector('#results [aria-selected=\"true\"]'); if(!row)return false; const r=row.getBoundingClientRect(); if(r.width<=0||r.height<=0||r.top<0||r.bottom>innerHeight+1)return false;if(row.checkVisibility&&!row.checkVisibility({checkOpacity:true,checkVisibilityCSS:true}))return false; for(let p=row;p;p=p.parentElement){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||s.visibility==='collapse'||Number(s.opacity)===0)return false;if(p!==row&&/auto|scroll|hidden/.test(s.overflowY)){const b=p.getBoundingClientRect();if(r.top<b.top-1||r.bottom>b.bottom+1||r.left<b.left-1||r.right>b.right+1)return false;}}return true; })()");
      assert(visible,`crowded keyboard row ${index} must scroll into view`);
    }
    await call('set','viewport','390','844');
    await call('select','#scenario',crowded.id);
    assert(!(await call('eval','document.documentElement.scrollWidth > window.innerWidth')),'narrow horizontal overflow');
    await call('screenshot',path.join(directory,'narrow.png'));
    const external=await call('eval',"performance.getEntriesByType('resource').filter(r=>/^https?:/.test(r.name)).map(r=>r.name)");
    assert(external.length===0,'external resources requested');
    for(const [file,source] of [[input.htmlPath,input.html],[input.metadataPath,input.metadataSource],[input.fixturePath,input.fixtureSource]]) assert(await fs.readFile(file,'utf8')===source,'source changed during browser verification');
  } catch(error) {
    await fs.writeFile(path.join(directory,'failure.json'),JSON.stringify({error:error.message,witnesses},null,2));
    throw new Error(`${error.message}; evidence: ${directory}`);
  } finally { await call('close'); }
  await fs.writeFile(path.join(directory,'report.json'),JSON.stringify({design_fingerprint:input.fingerprint,witnesses,evidence_class:'offline browser DOM; not native AppKit or global input'},null,2));
  return directory;
}
async function main() {
  const [command,id,...rest]=process.argv.slice(2);
  assert(rest.length===0,'unexpected arguments');
  if(command==='sync') console.log(await syncPrototype(id)?'synced':'already current');
  else if(command==='check') {
    assert(id===undefined,'check validates the registered catalog');
    const catalog=await fs.readdir(path.join(ROOT,'docs/design/prototypes'));
    assert(catalog.some(f=>f.endsWith('.json')),'missing prototype catalog');
    for(const file of catalog.filter(f=>f.endsWith('.json'))) await checkPrototype(file.slice(0,-5));
    console.log('prototype catalog checked');
  } else if(command==='verify') console.log(await verifyPrototype(id));
  else fail('usage: node scripts/prototypes.mjs sync|verify quick-navigator | check');
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) main().catch(error=>{console.error(error.message);process.exitCode=1;});

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { ROOT, assertData, canonical, embed, designFingerprint, dataBlock, assertOffline, contained, syncPrototype, checkPrototype, verifyPrototype } from '../../scripts/prototypes.mjs';

const canonicalMetadata=JSON.parse(await fs.readFile(path.join(ROOT,'docs/design/prototypes/quick-navigator.json'),'utf8'));
// Isolated authoring fixtures have no implementation commit/evidence of their own.
// Their negative cases must not depend on the living page's current lifecycle state.
const metadata={...structuredClone(canonicalMetadata),status:'selected',implementation:null};
const fixture=JSON.parse(await fs.readFile(path.join(ROOT,'Tests/Fixtures/quick-navigator-prototype.json'),'utf8'));
const html='<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; connect-src \'none\'; script-src \'unsafe-inline\'"><h1>Prototype</h1><script id="prototype-data" type="application/json">{}</script><footer>Authored</footer>';
let passed=0;
function test(name,run){run();passed++;console.log(`PASS ${name}`);}
function invalid(name,mutate){test(name,()=>{const m=structuredClone(metadata),f=structuredClone(fixture);mutate(m,f);assert.throws(()=>assertData(m,f));});}
test('valid canonical inputs',()=>{assertData(canonicalMetadata,fixture);assertData(metadata,fixture);});
test('canonical key order and array order',()=>{assert.equal(canonical({b:2,a:1}),canonical({a:1,b:2}));assert.notEqual(canonical([1,2]),canonical([2,1]));});
invalid('unknown schema',m=>m.schema_version=2);
invalid('unknown status',m=>m.status='green');
invalid('missing selected variant',m=>m.selected_variant=null);
invalid('unknown default scenario',m=>m.default_scenario='invented');
invalid('missing scenario catalog',m=>m.scenarios=[]);
invalid('duplicate scenario',m=>m.scenarios[1]=m.scenarios[0]);
invalid('unknown row set',m=>m.scenarios[0].row_set='absent');
invalid('missing metadata field',m=>delete m.title);
invalid('unknown metadata field',m=>m.updated_at='now');
invalid('missing row field',(_,f)=>delete f.row_sets.populated.pulse[0].state);
invalid('unknown row state',(_,f)=>f.row_sets.populated.pulse[0].state='green');
invalid('duplicate row within set',(_,f)=>f.row_sets.populated.pulse.push(f.row_sets.populated.pulse[0]));
invalid('null pulse URL',(_,f)=>f.row_sets.populated.pulse[0].url=null);
test('new declared scenario allowed',()=>{const m=structuredClone(metadata);m.scenarios.push({...structuredClone(m.scenarios[0]),id:'additional-case'});assertData(m,fixture);});
test('independent row sets may repeat identities',()=>{const f=structuredClone(fixture);f.row_sets.another=structuredClone(f.row_sets.populated);assertData(metadata,f);});
test('JSON lane key order does not change semantic order',()=>{const f=structuredClone(fixture);const s=f.row_sets.populated;f.row_sets.populated={pulse:s.pulse,inbound:s.inbound,radar:s.radar};assertData(metadata,f);});
test('current selected A and initial cases are explicit fixture requirements',()=>{
  assert.equal(metadata.selected_variant,'A');
  const required=['quiet','draft','held','fold','mixed','none','empty','loading','offline','browse','mouse','number','branch','repo-number','github-link','prefix-return','clear-restore','whitespace'];
  assert.ok(required.every(id=>metadata.scenarios.some(s=>s.id===id)));
});
invalid('nonsynthetic URL',(_,f)=>f.row_sets.populated.pulse[0].url='https://github.com/private/repo/pull/1');
invalid('invalid owner',(_,f)=>f.row_sets.populated.pulse[0].repo='private/repo');
invalid('nonfixture expected ID',m=>m.scenarios[0].expected.matched_ids=['invented']);
invalid('mismatched walk',m=>m.scenarios[0].expected.walk.reverse());
invalid('wrong selected ID',m=>m.scenarios[0].expected.selected_id='jump:github');
invalid('zero count',m=>m.scenarios[0].expected.count='0 of 25');
invalid('missing implementation evidence',m=>m.status='implemented');
invalid('superseded missing reference',m=>m.status='superseded');
invalid('invalid superseded reference type',m=>m.superseded_by=42);
test('one inert block required',()=>{assert.throws(()=>dataBlock('<script></script>'));assert.throws(()=>dataBlock(html+html));assert.throws(()=>dataBlock(html.replace('application/json','text/javascript')));});
test('unquoted duplicate block ID is rejected',()=>assert.throws(()=>dataBlock(html+'<script id=prototype-data type="application/json">{}</script>')));
test('offline boundaries',()=>{assertOffline(html);assert.throws(()=>assertOffline(html+'<img src="https://example.com/a">'));assert.throws(()=>assertOffline(html+'<style>@import "x";</style>'));});
test('offline check permits native URL parser',()=>assertOffline(html+'<script>const parsed = new URL("https://github.com/search?q=x");</script>'));
test('embedding idempotent and preserves outside',()=>{const result=embed(html,metadata,fixture);assert.equal(embed(result,metadata,fixture),result);assert.ok(result.startsWith(html.split('<script')[0]));assert.ok(result.endsWith('<footer>Authored</footer>'));});
test('inert injection',()=>{const m=structuredClone(metadata);m.title='</script><script>alert(1)</script>';const result=embed(html,m,fixture);assert.equal((result.match(/<script/g)||[]).length,1);assert.ok(result.includes('\\u003c/script>'));});
test('fingerprint excludes history and status, includes design',()=>{const m=structuredClone(metadata);const before=designFingerprint(html,m,fixture);m.history[0].why='new note';m.status='exploring';assert.equal(designFingerprint(html,m,fixture),before);m.scenarios[0].query='new query';assert.notEqual(designFingerprint(html,m,fixture),before);assert.notEqual(designFingerprint(html+' ',metadata,fixture),before);});

const temp=await fs.mkdtemp(path.join(os.tmpdir(),'githud-prototype-checks-'));
try {
  const directory=path.join(temp,'docs/design/prototypes');
  await fs.mkdir(directory,{recursive:true});await fs.mkdir(path.join(temp,'Tests/Fixtures'),{recursive:true});
  await fs.writeFile(path.join(temp,'docs/design/2026-09-04-quick-navigator-agenda.md'),'# quick-navigator-build');
  const mp=path.join(directory,'quick-navigator.json'),fp=path.join(temp,'Tests/Fixtures/quick-navigator-prototype.json'),hp=path.join(directory,'quick-navigator.html');
  await fs.writeFile(mp,JSON.stringify(metadata));await fs.writeFile(fp,JSON.stringify(fixture));await fs.writeFile(hp,html);
  assert.equal(await syncPrototype('quick-navigator',temp),true);assert.equal(await syncPrototype('quick-navigator',temp),false);await checkPrototype('quick-navigator',temp);passed++;console.log('PASS sync and check temporary fixture');
  const second={...structuredClone(metadata),id:'another-prototype',selected_variant:'Chosen'};
  await fs.writeFile(path.join(directory,'another-prototype.json'),JSON.stringify(second));await fs.writeFile(path.join(directory,'another-prototype.html'),html);
  await syncPrototype('another-prototype',temp);await checkPrototype('another-prototype',temp);passed++;console.log('PASS second registered prototype');
  const escaped=structuredClone(metadata);escaped.fixture='../../../outside-fixture.json';
  await fs.writeFile(path.join(temp,'outside-fixture.json'),JSON.stringify(fixture));await fs.writeFile(mp,JSON.stringify(escaped));
  await assert.rejects(checkPrototype('quick-navigator',temp),/escapes/);await fs.writeFile(mp,JSON.stringify(metadata));passed++;console.log('PASS fixture must stay inside Tests/Fixtures');
  if(process.argv.includes('--browser')) {
    const authored=await fs.readFile(path.join(ROOT,'docs/design/prototypes/quick-navigator.html'),'utf8');
    const original='const matched = source.filter(row => rowMatches(row, handle));';
    assert.ok(authored.includes(original),'mutation target must exist');
    await fs.writeFile(hp,authored.replace(original,'const matched = []; // deliberate checker mutation'));
    await syncPrototype('quick-navigator',temp);
    await assert.rejects(verifyPrototype('quick-navigator',temp),/quiet: matchedIDs/);
    passed++;console.log('PASS browser rejects deliberately broken matcher against unchanged expected cases');
    assert.ok(authored.includes('</head>'),'hidden-row mutation target must exist');
    await fs.writeFile(hp,authored.replace('</head>','<style>.row{display:none!important}</style></head>'));
    await syncPrototype('quick-navigator',temp);
    await assert.rejects(verifyPrototype('quick-navigator',temp),/quiet: materialized rows must be visible/);
    passed++;console.log('PASS browser rejects CSS-hidden results despite matching DOM IDs');
    await fs.writeFile(hp,html);await syncPrototype('quick-navigator',temp);
  }
  await fs.writeFile(hp,(await fs.readFile(hp,'utf8'))+' ');await assert.rejects(checkPrototype('quick-navigator',temp),/stale/);passed++;console.log('PASS stale authored HTML');
  await assert.rejects(syncPrototype('quick-navigator',temp,async()=>{await fs.appendFile(hp,'concurrent edit');}),/source changed/);assert.ok((await fs.readFile(hp,'utf8')).endsWith('concurrent edit'));passed++;console.log('PASS fresh source guard preserves concurrent edit');
  await assert.rejects(contained(temp,directory,'../../../../outside'),/ENOENT|escapes/);await fs.symlink(ROOT,path.join(temp,'outside'));await assert.rejects(contained(temp,temp,'outside/Package.swift'),/escapes/);passed++;console.log('PASS paths and symlinks cannot escape');
  const m=structuredClone(metadata);m.status='implemented';m.implementation={commit:'a'.repeat(40),design_fingerprint:'0'.repeat(64),evidence:'docs/design/2026-09-04-quick-navigator-agenda.md'};await fs.writeFile(mp,JSON.stringify(m));await assert.rejects(checkPrototype('quick-navigator',temp),/stale implementation/);passed++;console.log('PASS stale implementation refused');
} finally {await fs.rm(temp,{recursive:true,force:true});}
console.log(`${passed} prototype checks passed`);

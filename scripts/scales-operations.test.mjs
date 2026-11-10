import test from 'node:test';
import assert from 'node:assert/strict';
import {availabilityPayload, availabilityDraft, clockMinutes} from '../shared/scale-availability.ts';
import {scaleOperationError} from '../shared/scale-operations.ts';
const base = {
  id: 'fake',
  version: 0,
  kind: 'weekly',
  weekday: 0,
  startDate: '2027-02-28',
  endDate: '2027-03-01',
  startTime: '18:00',
  endTime: '22:00',
  reason: '',
};
test('weekly window includes midnight end but not start; rejects reversed times', () => {
  assert.equal(clockMinutes('24:00', true), 1440);
  assert.throws(() => clockMinutes('24:00'));
  assert.throws(() => clockMinutes('19:61'));
  assert.throws(() => availabilityPayload({...base, endTime: '17:00'}));
  assert.equal(availabilityPayload({...base, endTime: '24:00'}).endMinute, 1440);
});
test('period accepts Brazilian and ISO dates, validates calendar and chronological range', () => {
  assert.equal(availabilityPayload({...base, kind: 'unavailable', startDate: '28/02/2027', endDate: '01/03/2027'}).startsLocal, '2027-02-28T18:00');
  for (const d of ['29/02/2027', '2027-04-31', 'wrong']) assert.throws(() => availabilityPayload({...base, kind: 'unavailable', startDate: d}));
  assert.throws(() => availabilityPayload({...base, kind: 'unavailable', endDate: '2027-02-27'}));
});
test('stored period is edited using actual church timezone', () => {
  const a = {
    id: 'stored',
    version: 3,
    kind: 'unavailable',
    starts_at: '2027-03-01T01:00:00Z',
    ends_at: '2027-03-01T02:00:00Z',
    reason: 'Pessoal',
    active: true,
  };
  const draft = availabilityDraft('new', 'America/Manaus', a);
  assert.equal(draft.startDate, '2027-02-28');
  assert.equal(draft.startTime, '21:00');
  assert.equal(draft.version, 3);
  assert.equal(draft.id, 'stored');
});
test('errors are actionable and never reveal provider details', () => {
  assert.match(scaleOperationError('scale_changed', '40001'), /atualiz/i);
  assert.match(scaleOperationError('scale_deadline', '22023'), /prazo/i);
  assert.doesNotMatch(scaleOperationError('secret database password', 'XX000'), /secret|password/);
});
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const source = ts
  .transpileModule(readFileSync(new URL('../shared/use-volunteer-scales.ts', import.meta.url), 'utf8'), {
    compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext},
  })
  .outputText.replace(/^import .*;\r?\n/gm, '')
  .replace('export function useVolunteerScales', 'function useVolunteerScales');
function harness(rpc) {
  let slots = [],
    effects = [],
    index = 0,
    dirty = true,
    org = 'org-a',
    result;
  const hooks = {
    useState(initial) {
      const i = index++;
      if (!(i in slots)) slots[i] = {value: typeof initial === 'function' ? initial() : initial};
      return [
        slots[i].value,
        (value) => {
          const next = typeof value === 'function' ? value(slots[i].value) : value;
          if (!Object.is(next, slots[i].value)) {
            slots[i].value = next;
            dirty = true;
          }
        },
      ];
    },
    useRef(initial) {
      const i = index++;
      if (!(i in slots)) slots[i] = {current: initial};
      return slots[i];
    },
    useEffect(fn, deps) {
      const i = index++,
        previous = slots[i];
      if (!previous || deps.some((v, j) => !Object.is(v, previous.deps[j]))) {
        slots[i] = {deps, cleanup: previous?.cleanup};
        effects.push(() => {
          slots[i].cleanup?.();
          slots[i].cleanup = fn();
        });
      }
    },
  };
  let nonce = 0;
  const hook = new Function('useState', 'useRef', 'useEffect', 'scaleOperationError', source + ';return useVolunteerScales')(
    hooks.useState,
    hooks.useRef,
    hooks.useEffect,
    scaleOperationError,
  );
  async function flush() {
    for (let pass = 0; pass < 25; pass++) {
      if (dirty) {
        index = 0;
        effects = [];
        dirty = false;
        result = hook(rpc, org, true, () => String(++nonce));
        for (const effect of effects) effect();
      }
      await new Promise((r) => setImmediate(r));
      if (!dirty) return result;
    }
    throw Error('render loop');
  }
  return {
    flush,
    get current() {
      return result;
    },
    changeOrg(value) {
      org = value;
      dirty = true;
    },
  };
}
test('lost response keeps same request; new payload creates a new identity', async () => {
  const calls = [];
  const h = harness({
    rpc: async (n, a) => {
      calls.push(a);
      return ['list', 'availability'].includes(a.p_action) ? {data: {items: [], total: 0}} : {error: {message: 'network'}};
    },
  });
  await h.flush();
  await h.current.command('reply', {id: 'invite', version: 1, response: 'accepted'});
  await h.current.command('reply', {id: 'invite', version: 1, response: 'accepted'});
  await h.current.command('reply', {id: 'invite', version: 1, response: 'declined'});
  const writes = calls.filter((a) => a.p_action === 'reply');
  assert.equal(writes[0].p_data.request, writes[1].p_data.request);
  assert.notEqual(writes[1].p_data.request, writes[2].p_data.request);
  assert.ok(writes.every((a) => !('p_unit' in a)));
});
test('previous church response cannot replace the current church data', async () => {
  let release;
  const wait = new Promise((r) => (release = r));
  const h = harness({
    rpc: async (n, a) => {
      if (a.p_org === 'org-a') await wait;
      return {data: {unit: a.p_org, items: [], total: 0}};
    },
  });
  await h.flush();
  h.changeOrg('org-b');
  await h.flush();
  assert.equal(h.current.page.unit, 'org-b');
  release();
  await h.flush();
  assert.equal(h.current.page.unit, 'org-b');
});

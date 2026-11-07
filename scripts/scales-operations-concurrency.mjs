import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
if (process.argv[2] !== '--local-synthetic') throw Error('Somente fixtures fictícias no Docker local/CI.');
const org = randomUUID(),
  unit = randomUUID(),
  owner = randomUUID(),
  user = randomUUID(),
  person = randomUUID(),
  team = randomUUID(),
  role = randomUUID(),
  member = randomUUID(),
  service = randomUUID(),
  invite = randomUUID(),
  q = (v) => "'" + String(v).replaceAll("'", "''") + "'";
function db(sql, observe = () => {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(
      'docker',
      [
        'exec',
        '-i',
        'supabase_db_vinha',
        'psql',
        '-X',
        '-q',
        '-A',
        '-t',
        '-U',
        'postgres',
        '-d',
        'postgres',
        '-v',
        'ON_ERROR_STOP=1',
        '-v',
        'VERBOSITY=verbose',
      ],
      {stdio: ['pipe', 'pipe', 'pipe']},
    );
    let out = '',
      err = '';
    const timer = setTimeout(() => {
      p.kill();
      reject(Error('Timeout do teste isolado'));
    }, 15000);
    p.stdout.on('data', (c) => {
      out += c;
      observe(out);
    });
    p.stderr.on('data', (c) => (err += c));
    p.on('error', reject);
    p.on('close', (code) => {
      clearTimeout(timer);
      resolve({code, out, err});
    });
    p.stdin.end("set statement_timeout='10s';set lock_timeout='7s';" + sql);
  });
}
async function good(sql) {
  const r = await db(sql);
  assert.equal(r.code, 0, r.err);
  return r.out.trim();
}
const identity = (id) => `set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub: id, role: 'authenticated'}))},true);`;
const vol = (action, data) => `select public.scale_volunteer(${q(org)},${q(action)},${q(JSON.stringify(data))}::jsonb);`;
const op = (action, data) => `select public.scale_operations(${q(org)},${q(unit)},${q(action)},${q(JSON.stringify(data))}::jsonb);`;
await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values ${[owner, user].map((id) => `(${q(id)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q(id + '-scale-race@example.invalid')},now(),now(),now())`).join(',')};
insert into public.organizations(id,name,slug,status) values(${q(org)},'Escalas concorrentes fictícias',${q('scale-race-' + org)},'active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Igreja fictícia','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(${q(org)},${q(owner)},${q(unit)},'owner','active'),(${q(org)},${q(user)},${q(unit)},'member','active');
insert into public.membership_unit_access(membership_id,unit_id,access_level) select id,default_unit_id,'read' from public.organization_memberships where organization_id=${q(org)} and user_id=${q(user)};
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,status) values(${q(person)},${q(org)},${q(unit)},${q(user)},'Voluntário fictício','active');
insert into private.scale_teams(id,organization_id,unit_id,name) values(${q(team)},${q(org)},${q(unit)},'Equipe fictícia');
insert into private.scale_roles(id,organization_id,unit_id,team_id,name) values(${q(role)},${q(org)},${q(unit)},${q(team)},'Função fictícia');
insert into private.scale_members(id,organization_id,unit_id,team_id,person_id,role_id) values(${q(member)},${q(org)},${q(unit)},${q(team)},${q(person)},${q(role)});
insert into private.scale_services(id,organization_id,unit_id,title,series_id,timezone,arrival_at,starts_at,ends_at,status,created_by) values(${q(service)},${q(org)},${q(unit)},'Serviço fictício',${q(service)},'America/Sao_Paulo',now()+interval '2 days',now()+interval '2 days 30 minutes',now()+interval '2 days 2 hours','published',${q(owner)});
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id) values(${q(service)},${q(org)},${q(unit)},${q(team)},${q(role)},1,${q(member)});
insert into private.scale_invites(id,service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,deadline) values(${q(invite)},${q(service)},${q(org)},${q(unit)},${q(team)},${q(role)},1,${q(member)},${q(person)},now()+interval '1 day');commit;`);
const token = JSON.parse(
  (await good(`begin;${identity(owner)}${op('view', {service})}commit;`))
    .split('\n')
    .filter((x) => x.startsWith('{'))
    .at(-1),
).token;
const request = randomUUID(),
  reply = {id: invite, version: 1, response: 'accepted', request};
let release;
const barrier = new Promise((r) => (release = r));
const first = db(`begin;${identity(user)}${vol('reply', reply)}select 'SCALE_REPLY_LOCK';select pg_sleep(1.2);commit;`, (out) => {
  if (out.includes('SCALE_REPLY_LOCK')) release();
});
await Promise.race([
  barrier,
  first.then((r) => {
    throw Error('Não atingiu barreira: ' + r.err);
  }),
]);
const second = await db(`begin;${identity(owner)}${op('revise', {service, token, reason: 'Revisão concorrente fictícia', request: randomUUID()})}commit;`),
  winner = await first;
assert.equal(winner.code, 0, winner.err);
assert.notEqual(second.code, 0);
assert.match(second.err, /40001|scale_changed/s);
assert.equal(await good(`select response||':'||active::text from private.scale_invites where id=${q(invite)};`), 'accepted:true');
const repeats = await Promise.all([0, 1].map(() => db(`begin;${identity(user)}${vol('reply', reply)}commit;`)));
assert.ok(repeats.every((r) => r.code === 0));
assert.equal(await good(`select count(*) from private.scale_service_history where service_id=${q(service)} and action='reply';`), '1');
console.log('Escalas: resposta concorrente preservada, revisão obsoleta rejeitada e repetição idempotente. Apenas fixtures locais fictícias.');

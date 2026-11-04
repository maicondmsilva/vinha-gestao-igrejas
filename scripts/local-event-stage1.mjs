import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco Docker local fictício.');
const sql=readFileSync('supabase/migrations/20261104024216_eventos_etapa1.sql','utf8').replace(/^\ufeff/,''),run=s=>spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:s,encoding:'utf8',timeout:60000});
function execute(s){const r=run(s);if(r.status!==0){console.error(r.stdout);console.error(r.stderr);process.exit(1)}return r.stdout}
if(process.argv.includes('--install'))execute('begin;'+sql+'\ncommit;');
if(process.argv.includes('--refresh')){if(execute("select to_regclass('private.event_images') is null;").includes('t\n'))execute('begin;'+sql.slice(sql.indexOf('-- Event image files'))+'\ncommit;');const functions=sql.match(/create (?:or replace )?function [\s\S]*?\$\$;/g)||[];execute('begin;'+functions.map(s=>s.replace(/^create (?:or replace )?function/,'create or replace function')).join('\n')+"\ncommit;notify pgrst,'reload schema';");}
if(process.argv.includes('--refresh'))execute("do $$begin if not exists(select 1 from pg_trigger where tgname='event_publication_ready') then create trigger event_publication_ready before update of status on private.church_app_events for each row execute function private.event_publication_guard();end if;end $$;");
if(process.argv.includes('--test')){const out=execute(readFileSync('supabase/tests/event_stage1.sql','utf8'));console.log(out);if(out.includes('not ok'))process.exit(1)}

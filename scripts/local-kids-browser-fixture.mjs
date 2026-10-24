import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
import {localSupabaseConfig} from './local-supabase-config.mjs';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente homologação local fictícia.');
const config=localSupabaseConfig();
if(process.stdin.isTTY)process.stdin.setRawMode(true);
console.log('Aguardando credencial fictícia por stdin; valores não serão exibidos.');
const lines=createInterface({input:process.stdin,terminal:false});let input;
for await(const line of lines){input=JSON.parse(line);lines.close();break}
if(process.stdin.isTTY)process.stdin.setRawMode(false);
if(!input||!/^visual-kids-[a-z0-9-]+@example\.invalid$/.test(input.email)||typeof input.password!=='string'||input.password.length<24)throw Error('Credencial sintética inválida.');
const admin=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const created=await admin.auth.admin.createUser({email:input.email,password:input.password,email_confirm:true});if(created.error)throw Error('Conta fictícia não criada.');
const client=createClient(config.API_URL,config.PUBLISHABLE_KEY||config.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
if((await client.auth.signInWithPassword(input)).error)throw Error('Login sintético falhou.');
const slug='kids-visual-'+randomUUID();
const boot=await client.rpc('bootstrap_organization',{p_organization_name:'Kids — homologação fictícia',p_organization_slug:slug,p_headquarters_name:'Sede Kids de teste',p_full_name:'Operador Kids fictício'});
if(boot.error)throw Error('Organização sintética não criada.');
const units=await admin.from('organization_units').select('id').eq('organization_id',boot.data);const unit=units.data?.[0]?.id;
if(!unit)throw Error('Unidade sintética indisponível.');
const p=await admin.from('people').insert([
 {organization_id:boot.data,unit_id:unit,full_name:'Clara — criança fictícia',birth_date:'2018-05-12',journey_status:'Visitante'},
 {organization_id:boot.data,unit_id:unit,full_name:'Helena — responsável fictícia',birth_date:'1989-04-08',phone:'(00) 00000-0000',journey_status:'Visitante'},
]).select('id,full_name');if(p.error)throw Error('Pessoas sintéticas não criadas.');
const child=p.data.find(p=>p.full_name.startsWith('Clara')),profile=randomUUID();
const saved=await client.rpc('kids_save',{p_organization:boot.data,p_unit:unit,p_request:randomUUID(),p_action:'profile',p_id:profile,p_version:0,p_data:{personId:child.id,status:'active'}});
if(saved.error)throw Error('Kids sintético não criado: '+saved.error.code);
await client.auth.signOut();
console.log(JSON.stringify({organization:boot.data,user:created.data.user.id,unit,slug,profile,url:'http://127.0.0.1:4100/painel?pagina=kids&tenant='+slug+'&unidade='+unit}));

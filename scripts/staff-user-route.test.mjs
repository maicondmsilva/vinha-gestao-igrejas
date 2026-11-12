import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {staffUserRoutes,parseStaffUser} from '../app/lib/staff-user-core.ts';

const unit='c0000000-0000-4000-8000-000000000001',person='c0000000-0000-4000-8000-000000000002',member='c0000000-0000-4000-8000-000000000003',login='c0000000-0000-4000-8000-000000000004';
const base={role:'leader',unit,account:{name:'Ana Teste',phone:'11999990000',email:'ana@example.invalid'}};

function harness({save,link,authCreate,authUpdate,get}={}){
 const calls=[];
 const rpc=async(name,args)=>{calls.push(['rpc',args.p_action,args.p_data]);
  if(args.p_action==='save')return save?save(args.p_data):{data:{ok:true,membership:null,person,needsLogin:true,loginUser:null},error:null};
  if(args.p_action==='link_login')return link?link(args.p_data):{data:{ok:true,membership:member},error:null};
  if(args.p_action==='get')return get?get():{data:{membership:{id:member},email:'ana@example.invalid'},error:null};
  return{data:{ok:true,items:[]},error:null}};
 const admin={
  createUser:async attrs=>{calls.push(['createUser',attrs]);return authCreate?authCreate(attrs):{data:{user:{id:login}},error:null}},
  updateUserById:async(id,attrs)=>{calls.push(['updateUserById',id,attrs]);return authUpdate?authUpdate(attrs):{data:{user:{id}},error:null}},
  getUserById:async id=>({data:{user:{id,email:'ana@example.invalid'}},error:null}),
  deleteUser:async id=>{calls.push(['deleteUser',id]);return{data:{},error:null}}};
 const routes=staffUserRoutes({access:async()=>({org:'verified-org',rpc}),admin:()=>admin});
 return{calls,routes};
}
const req=(method,body,url='https://vinha.test/api/users')=>new Request(url,{method,body:body===undefined?undefined:JSON.stringify(body)});

test('validação: papel, e-mail, senha e campos extras',()=>{
 assert.ok(parseStaffUser(base));
 assert.equal(parseStaffUser({...base,role:'owner'}),null);
 assert.equal(parseStaffUser({...base,account:{...base.account,email:'sem-arroba'}}),null);
 assert.equal(parseStaffUser({...base,account:{...base.account,password:'curta'}}),null);
 assert.equal(parseStaffUser({...base,organization:'forjada'}),null);
 assert.equal(parseStaffUser({...base,unit:'nao-e-uuid'}),null);
});

test('cria login só depois do banco autorizar',async()=>{
 const h=harness(),r=await h.routes.POST(req('POST',{...base,account:{...base.account,password:'segredo123'}}));
 assert.equal(r.status,201);
 assert.deepEqual(h.calls.map(c=>c[0]==='rpc'?c[1]:c[0]),['save','createUser','link_login']);
 assert.equal(h.calls[1][1].email_confirm,true);
 assert.equal(h.calls[2][2].passwordSet,true);
 assert.equal(h.calls[2][2].user,login);
});

test('ministério vem da sessão, não do navegador',async()=>{
 const seen=[];const routes=staffUserRoutes({access:async()=>({org:'verified-org',rpc:async(n,a)=>{seen.push(a.p_org);return{data:{items:[]},error:null}}}),admin:()=>({})});
 await routes.search(req('GET',undefined,'https://vinha.test/api/users/search?q=ana&org=forjada'));
 assert.deepEqual(seen,['verified-org']);
});

test('senha com menos de 8 recusada',async()=>{
 const h=harness(),r=await h.routes.POST(req('POST',{...base,account:{...base.account,password:'1234567'}}));
 assert.equal(r.status,400);assert.equal(h.calls.length,0);
});

test('pessoa nova sem senha não cria login',async()=>{
 const h=harness(),r=await h.routes.POST(req('POST',base));
 assert.equal(r.status,400);assert.match(await r.text(),/senha/i);
 assert.ok(!h.calls.some(c=>c[0]==='createUser'));
});

test('resposta nunca traz a senha',async()=>{
 const h=harness(),r=await h.routes.POST(req('POST',{...base,account:{...base.account,password:'segredo123'}}));
 assert.doesNotMatch(await r.text(),/segredo123/);
});

test('falha do Auth não deixa vínculo, e falha ao ligar apaga o login criado',async()=>{
 const a=harness({authCreate:()=>({data:{user:null},error:{message:'down',status:500}})});
 const r=await a.routes.POST(req('POST',{...base,account:{...base.account,password:'segredo123'}}));
 assert.equal(r.status,503);assert.ok(!a.calls.some(c=>c[1]==='link_login'));
 const b=harness({link:()=>({data:null,error:{code:'42501',message:'x'}})});
 const s=await b.routes.POST(req('POST',{...base,account:{...base.account,password:'segredo123'}}));
 assert.equal(s.status,403);assert.deepEqual(b.calls.at(-1),['deleteUser',login]);
});

test('e-mail em uso vira mensagem clara',async()=>{
 const h=harness({save:()=>({data:null,error:{code:'23505',message:'email_in_use'}})});
 const r=await h.routes.POST(req('POST',{...base,account:{...base.account,password:'segredo123'}}));
 assert.equal(r.status,409);assert.match(await r.text(),/já pertence a outra conta/);
 const g=harness({authCreate:()=>({data:{user:null},error:{message:'A user with this email address has already been registered',status:422,code:'email_exists'}})});
 const s=await g.routes.POST(req('POST',{...base,account:{...base.account,password:'segredo123'}}));
 assert.equal(s.status,409);
});

test('versão antiga vira pedido para atualizar a ficha',async()=>{
 const h=harness({save:()=>({data:null,error:{code:'40001',message:'stale'}})});
 const r=await h.routes.PATCH(req('PATCH',{...base,version:'v1'},'https://vinha.test/api/users/'+member),member);
 assert.equal(r.status,409);assert.match(await r.text(),/Atualize a ficha/);
});

test('senha em branco na edição não chama updateUserById',async()=>{
 const h=harness({save:()=>({data:{ok:true,membership:member,person,needsLogin:false,loginUser:login},error:null})});
 const r=await h.routes.PATCH(req('PATCH',{...base,version:'v1',account:{...base.account,password:''}}),member);
 assert.equal(r.status,200);assert.ok(!h.calls.some(c=>c[0]==='updateUserById'));
});

test('senha nova na edição marca troca obrigatória',async()=>{
 const h=harness({save:()=>({data:{ok:true,membership:member,person,needsLogin:false,loginUser:login},error:null})});
 const r=await h.routes.PATCH(req('PATCH',{...base,version:'v1',account:{...base.account,password:'novasenha9'}}),member);
 assert.equal(r.status,200);
 assert.deepEqual(h.calls.find(c=>c[0]==='updateUserById').slice(1),[login,{password:'novasenha9'}]);
 assert.equal(h.calls.at(-1)[1],'mark_password');
});

test('e-mail alterado na ficha muda o login',async()=>{
 const h=harness({save:()=>({data:{ok:true,membership:member,person,needsLogin:false,loginUser:login},error:null})});
 await h.routes.PATCH(req('PATCH',{...base,version:'v1',account:{...base.account,email:'nova@example.invalid'}}),member);
 assert.deepEqual(h.calls.find(c=>c[0]==='updateUserById').slice(1),[login,{email:'nova@example.invalid',email_confirm:true}]);
});

test('excluir chama remove com o vínculo da URL',async()=>{
 const h=harness(),r=await h.routes.DELETE(req('DELETE'),member);
 assert.equal(r.status,200);assert.deepEqual(h.calls[0],['rpc','remove',{membership:member}]);
 assert.equal((await h.routes.DELETE(req('DELETE'),'nao-e-uuid')).status,400);
});

test('convite responde 410',()=>{
 const src=readFileSync(new URL('../app/api/users/invites/route.ts',import.meta.url),'utf8');
 assert.match(src,/410/);assert.match(src,/Convites encerrados/);
 assert.doesNotMatch(readFileSync(new URL('../app/lib/supabase/staff-routes.ts',import.meta.url),'utf8'),/create_staff_invitation/);
});

test('rotas usam a chave administrativa só no servidor',()=>{
 const src=readFileSync(new URL('../app/lib/supabase/staff-routes.ts',import.meta.url),'utf8');
 assert.match(src,/supabaseAdminClient/);
 assert.doesNotMatch(readFileSync(new URL('../app/lib/staff-user-core.ts',import.meta.url),'utf8'),/NEXT_PUBLIC|SERVICE_ROLE|SECRET_KEY/);
});

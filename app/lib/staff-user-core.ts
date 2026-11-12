// Usuários: criar, editar, excluir e buscar sem convite.
// O banco (public.staff_user) decide quem pode; o login (Supabase Auth) só é criado ou alterado depois.
// Sem dependências do Next para que os testes usem banco e Auth falsos.

type DbError={code?:string;message?:string}|null;
export type StaffRpc=(name:string,args:Record<string,unknown>)=>Promise<{data:any;error:DbError}>;
type AuthError={message?:string;status?:number;code?:string}|null;
export type StaffAuthAdmin={
 createUser:(attrs:{email:string;password:string;email_confirm:boolean;user_metadata:Record<string,string>})=>Promise<{data:{user:{id:string}|null};error:AuthError}>;
 updateUserById:(id:string,attrs:Record<string,unknown>)=>Promise<{data:unknown;error:AuthError}>;
 getUserById:(id:string)=>Promise<{data:{user:{id:string;email?:string}|null};error:AuthError}>;
 deleteUser:(id:string)=>Promise<{data:unknown;error:AuthError}>;
};
export type StaffDeps={access:(request:Request)=>Promise<{response?:Response;org?:string;rpc?:StaffRpc}>;admin:()=>StaffAuthAdmin};

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const roles=['admin','pastor','secretary','finance','leader','member','viewer'];
const date=/^\d{4}-\d{2}-\d{2}$/;
const json=(body:unknown,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store, private'}});

export type StaffUserInput={person?:string;version?:string;role:string;unit:string|null;
 account:{name:string;phone:string;email:string;password:string};
 address?:Record<string,string>;extra?:Record<string,string|boolean|null>};

const text=(v:unknown,max:number)=>typeof v==='string'&&v.length<=max?v.trim():null;
export function parseStaffUser(value:unknown):StaffUserInput|null{
 if(!value||typeof value!=='object'||Array.isArray(value))return null;
 const v=value as Record<string,unknown>;
 if(Object.keys(v).some(k=>!['person','version','role','unit','account','address','extra'].includes(k)))return null;
 if(typeof v.role!=='string'||!roles.includes(v.role))return null;
 if(v.unit!==undefined&&v.unit!==null&&(typeof v.unit!=='string'||!uuid.test(v.unit)))return null;
 if(v.person!==undefined&&(typeof v.person!=='string'||!uuid.test(v.person)))return null;
 if(v.version!==undefined&&(typeof v.version!=='string'||v.version.length>64))return null;
 const a=v.account as Record<string,unknown>|undefined;
 if(!a||typeof a!=='object')return null;
 const name=text(a.name,160),email=text(a.email,254)?.toLowerCase(),phone=a.phone===undefined?'':text(a.phone,30),password=a.password===undefined?'':typeof a.password==='string'?a.password:null;
 if(!name||name.length<2||!email||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)||phone===null||password===null)return null;
 if(password&&(password.length<8||password.length>72))return null;
 let address:Record<string,string>|undefined;
 if(v.address!==undefined){
  if(!v.address||typeof v.address!=='object')return null;address={};
  for(const k of ['postal_code','street','number','complement','district','city','state']){const x=(v.address as Record<string,unknown>)[k];if(x===undefined||x===null)continue;const t=text(x,160);if(t===null)return null;address[k]=t}
 }
 let extra:Record<string,string|boolean|null>|undefined;
 if(v.extra!==undefined){
  if(!v.extra||typeof v.extra!=='object')return null;extra={};
  for(const [k,x] of Object.entries(v.extra as Record<string,unknown>)){
   if(k==='is_pastor'){if(typeof x!=='boolean')return null;extra[k]=x;continue}
   if(!['gender','cpf','birth_date','marriage_date','baptism_date'].includes(k))return null;
   if(x===null||x===''){extra[k]=null;continue}
   const t=text(x,20);if(t===null)return null;
   if(k.endsWith('_date')&&!date.test(t))return null;
   extra[k]=t;
  }
 }
 return{person:v.person as string|undefined,version:v.version as string|undefined,role:v.role,unit:(v.unit as string)||null,account:{name,phone,email,password},address,extra};
}

function dbFail(error:DbError){
 const c=error?.code;
 if(c==='23505')return json({error:'Este e-mail já pertence a outra conta.'},409);
 if(c==='40001')return json({error:'Esta ficha foi alterada por outra pessoa. Atualize a ficha e tente de novo.'},409);
 if(c==='42501')return json({error:'Você não pode fazer esta alteração neste usuário.'},403);
 if(c==='P0002')return json({error:'Usuário não encontrado. Atualize a lista.'},404);
 if(c==='0A000')return json({error:'Convites encerrados. Crie o usuário em Usuários e permissões.'},410);
 if(c==='22023'||c==='22P02'||c==='22007'||c==='22008')return json({error:'Revise os dados informados.'},400);
 return json({error:'Não foi possível concluir agora. Tente novamente em instantes.'},503);
}
function authFail(error:AuthError){
 const m=(error?.message||'')+' '+(error?.code||'');
 if(/already|exists|registered/i.test(m))return json({error:'Este e-mail já pertence a outra conta.'},409);
 if(/password/i.test(m)&&error?.status===422)return json({error:'A senha não foi aceita. Use pelo menos 8 caracteres, misturando letras e números.'},400);
 return json({error:'Não foi possível criar ou alterar o login agora. Tente novamente em instantes.'},503);
}
async function readBody(request:Request){const raw=await request.text();if(raw.length>16384)return undefined;try{return JSON.parse(raw)}catch{return undefined}}
const bad=()=>json({error:'Revise os dados informados.'},400);
const saveData=(input:StaffUserInput,membership?:string)=>({
 ...(membership?{membership}:{}),...(input.person?{person:input.person}:{}),...(input.version!==undefined?{version:input.version}:{}),
 role:input.role,unit:input.unit,account:{name:input.account.name,phone:input.account.phone,email:input.account.email},
 ...(input.address?{address:input.address}:{}),...(input.extra?{extra:input.extra}:{})});

export function staffUserRoutes(deps:StaffDeps){
 const call=(rpc:StaffRpc,org:string,action:string,data:Record<string,unknown>)=>rpc('staff_user',{p_org:org,p_action:action,p_data:data});

 // Depois de o banco gravar: cria o login (pessoa sem login) ou ajusta e-mail/senha do login existente.
 async function finish(rpc:StaffRpc,org:string,input:StaffUserInput,saved:{membership:string|null;person:string;needsLogin:boolean;loginUser:string|null},created:boolean){
  const admin=deps.admin(),pw=input.account.password;
  if(saved.needsLogin){
   if(!pw)return json({error:'Informe uma senha para o primeiro acesso (mínimo de 8 caracteres).',person:saved.person},400);
   const made=await admin.createUser({email:input.account.email,password:pw,email_confirm:true,user_metadata:{full_name:input.account.name}});
   if(made.error||!made.data.user)return authFail(made.error);
   const userId=made.data.user.id;
   const linked=await call(rpc,org,'link_login',{person:saved.person,user:userId,role:input.role,unit:input.unit,passwordSet:true});
   if(linked.error){await admin.deleteUser(userId);return dbFail(linked.error)}
   return json({membership:linked.data?.membership,person:saved.person},created?201:200);
  }
  if(saved.loginUser){
   const current=await admin.getUserById(saved.loginUser);
   const email=current.data.user?.email?.toLowerCase();
   if(email&&email!==input.account.email){
    const changed=await admin.updateUserById(saved.loginUser,{email:input.account.email,email_confirm:true});
    if(changed.error)return json({error:'O cadastro foi salvo, mas o e-mail de login não mudou. Tente salvar de novo.'},changed.error.status===422?409:503);
   }
   if(pw){
    const changed=await admin.updateUserById(saved.loginUser,{password:pw});
    if(changed.error)return authFail(changed.error);
    if(saved.membership){const marked=await call(rpc,org,'mark_password',{membership:saved.membership});if(marked.error)return dbFail(marked.error)}
   }
  }
  return json({membership:saved.membership,person:saved.person},created?201:200);
 }

 async function guard(request:Request){const a=await deps.access(request);if(a.response||!a.rpc||!a.org)return{response:a.response||json({error:'Acesso negado.'},403)};return{rpc:a.rpc,org:a.org}}

 return{
  async POST(request:Request){
   const input=parseStaffUser(await readBody(request));if(!input)return bad();
   if(!input.person&&!input.account.password)return json({error:'Informe uma senha para o primeiro acesso (mínimo de 8 caracteres).'},400);
   const g=await guard(request);if('response' in g)return g.response!;
   const saved=await call(g.rpc,g.org,'save',saveData(input));if(saved.error)return dbFail(saved.error);
   return finish(g.rpc,g.org,input,saved.data,true);
  },
  async PATCH(request:Request,id:string){
   if(!uuid.test(id))return bad();
   const input=parseStaffUser(await readBody(request));if(!input||input.version===undefined)return bad();
   const g=await guard(request);if('response' in g)return g.response!;
   const saved=await call(g.rpc,g.org,'save',saveData({...input,person:undefined},id));if(saved.error)return dbFail(saved.error);
   return finish(g.rpc,g.org,input,saved.data,false);
  },
  async DELETE(request:Request,id:string){
   if(!uuid.test(id))return bad();
   const g=await guard(request);if('response' in g)return g.response!;
   const r=await call(g.rpc,g.org,'remove',{membership:id});if(r.error)return dbFail(r.error);
   return json({ok:true});
  },
  async GET(request:Request,id:string){
   if(!uuid.test(id))return bad();
   const g=await guard(request);if('response' in g)return g.response!;
   const r=await call(g.rpc,g.org,'get',{membership:id});if(r.error)return dbFail(r.error);
   return json(r.data);
  },
  async search(request:Request){
   const q=(new URL(request.url).searchParams.get('q')||'').trim().slice(0,80);
   const g=await guard(request);if('response' in g)return g.response!;
   const r=await call(g.rpc,g.org,'search',{q});if(r.error)return dbFail(r.error);
   return json(r.data);
  },
 };
}

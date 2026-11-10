import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync,readdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import ts from 'typescript';
import {selectActiveMembership,trustedSessionRequest,verifiedPlatformIdentity} from '../app/lib/access-security.ts';

const root=fileURLToPath(new URL('../',import.meta.url));
const a={organization_id:'a',organization_slug:'igreja-a',status:'active'};
const b={organization_id:'b',organization_slug:'igreja-b',status:'active'};
test('organization selection never crosses membership or ignores an explicit invalid hint',()=>{
 assert.equal(selectActiveMembership([a,b],'a','b'),a);
 assert.equal(selectActiveMembership([a,b],'igreja-b','a'),b);
 assert.equal(selectActiveMembership([a,b],'outside','a'),null);
 assert.equal(selectActiveMembership([a,b],'','outside'),null);
});
test('ambiguous, empty and suspended membership cannot be selected implicitly',()=>{
 assert.equal(selectActiveMembership([a,b],'',null),null);
 assert.equal(selectActiveMembership([],'',null),null);
 assert.equal(selectActiveMembership([{...a,status:'suspended'}],'a',null),null);
 assert.equal(selectActiveMembership([a],'',null),a);
 assert.equal(selectActiveMembership([a,b],'','b'),b);
});
test('session writes require exact origin, independent of forged identity or forwarded headers',()=>{
 const request=(headers={})=>new Request('https://app.vinhaigrejas.com.br/api/people',{method:'POST',headers});
 assert.equal(trustedSessionRequest(request()),false);
 assert.equal(trustedSessionRequest(request({origin:'https://evil.invalid','x-forwarded-host':'app.vinhaigrejas.com.br'})),false);
 assert.equal(trustedSessionRequest(request({origin:'https://central.vinhaigrejas.com.br'})),false);
 assert.equal(trustedSessionRequest(request({origin:'https://app.vinhaigrejas.com.br', 'sec-fetch-site':'cross-site'})),false);
 assert.equal(trustedSessionRequest(request({origin:'https://app.vinhaigrejas.com.br'})),true);
 assert.equal(trustedSessionRequest(new Request('https://example.invalid/api/session')),true);
});
test('native staff app: bearer token without cookies is accepted; a cookie session still needs the origin',()=>{
 const jwt='Bearer aaa.bbb.ccc',request=(headers={})=>new Request('https://app.vinhaigrejas.com.br/api/push/campaigns',{method:'POST',headers});
 assert.equal(trustedSessionRequest(request({authorization:jwt})),true);
 assert.equal(trustedSessionRequest(request({authorization:jwt,cookie:'sb-access=1'})),false);
 assert.equal(trustedSessionRequest(request({authorization:'Bearer not-a-jwt'})),false);
 assert.equal(trustedSessionRequest(request({authorization:'Basic abc'})),false);
});
function client({role='owner',level='aal2',user={id:'verified-user',email:'operator@example.invalid'},userError=null,rpcError=null,aalError=null,operators}={}){
 return {auth:{getUser:async()=>({data:{user},error:userError}),mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:level},error:aalError})}},
 rpc:async()=>({data:operators||[{role,full_name:'Operator'}],error:rpcError})};
}
test('Central requires verified user, database operator, known role and successful aal2 check',async()=>{
 assert.equal(await verifiedPlatformIdentity(client({user:null}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({userError:new Error('offline')}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({level:'aal1'}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({aalError:new Error('failed')}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({rpcError:new Error('failed')}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({operators:[]}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({role:'invented'}),'GET'),null);
 assert.equal(await verifiedPlatformIdentity(client({operators:[{role:'owner'},{role:'admin'}]}),'GET'),null);
 assert.equal((await verifiedPlatformIdentity(client(),'GET')).user.id,'verified-user');
});
test('generic Central writes remain restricted, and dependency failures do not grant access',async()=>{
 for(const role of ['support','read_only']) {
  assert.ok(await verifiedPlatformIdentity(client({role}),'GET'));
  assert.equal(await verifiedPlatformIdentity(client({role}),'POST'),null);
 }
 for(const role of ['admin','owner']) assert.ok(await verifiedPlatformIdentity(client({role}),'POST'));
 const broken=client();broken.auth.getUser=async()=>{throw new Error('offline')};
 assert.equal(await verifiedPlatformIdentity(broken,'GET'),null);
});
test('shared authenticators have no legacy identity/bootstrap fallback',()=>{
 const source=readFileSync(join(root,'app/api/_auth.ts'),'utf8');
 assert.doesNotMatch(source,/oai-authenticated-user|INSERT INTO platform_users|vinha-demo/);
 for(const name of ['sessionFrom','platformSessionFrom']){
  const ast=ts.createSourceFile('auth.ts',source,ts.ScriptTarget.Latest,true);
  const fn=ast.statements.find(s=>ts.isFunctionDeclaration(s)&&s.name?.text===name);
  assert.ok(fn);
  assert.match(fn.body.getText(ast),/!supabaseServerConfigured/);
  assert.match(fn.body.getText(ast),/!trustedSessionRequest/);
  assert.doesNotMatch(fn.body.getText(ast),/env\.DB|getSession\(/);
 }
 for(const path of ['app/lib/supabase/church-session.ts','app/lib/supabase/church-access.ts']){
  const content=readFileSync(join(root,path),'utf8');
  assert.match(content,/selectActiveMembership/);
  assert.match(content,/auth.getUser\(/);
 }
});
test('no application page relies on the broken framework Link interceptor',()=>{
 const walk=dir=>readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(join(dir,e.name)):[join(dir,e.name)]);
 for(const path of walk(join(root,'app')).filter(p=>p.endsWith('.tsx'))){
  assert.doesNotMatch(readFileSync(path,'utf8'),/from ['"]next\/link['"]/,path);
  assert.doesNotMatch(readFileSync(path,'utf8'),/mailto:suporte@vinha\.app/,path);
 }
});
test('password recovery no longer depends on legacy API or claims a fictitious protocol',()=>{
 const page=readFileSync(join(root,'app/recuperar-acesso/page.tsx'),'utf8');
 assert.match(page,/auth.resetPasswordForEmail/);
 assert.match(page,/finally\{setBusy\(false\)\}/);
 assert.doesNotMatch(page,/api\/access\/recovery|done.protocol/);
 assert.match(page,/body.get\('requestType'\)!=='access'/);
 assert.match(page,/não comprova a entrega/);
});
test('Vercel disables shared API/private page caching and protects framing',()=>{
 const config=JSON.parse(readFileSync(join(root,'vercel.json'),'utf8'));
 const general=config.headers.find(h=>h.source==='/(.*)').headers;
 assert.ok(general.some(h=>h.key==='X-Content-Type-Options'&&h.value==='nosniff'));
 assert.ok(general.some(h=>h.key==='Content-Security-Policy'&&h.value.includes("frame-ancestors 'none'")));
 for(const path of ['/api/:path*','/admin-vinha/:path*','/painel/:path*','/cadastro']){
  const rule=config.headers.find(h=>h.source===path);
  assert.ok(rule?.headers.some(h=>h.key==='Cache-Control'&&h.value.includes('private, no-store')),path);
  assert.ok(rule?.headers.some(h=>h.key==='Vercel-CDN-Cache-Control'&&h.value==='no-store'),path);
 }
});

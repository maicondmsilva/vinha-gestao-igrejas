import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
test('login com troca obrigatória vai para trocar-senha',()=>{const s=read('app/SupabaseLogin.tsx');assert.match(s,/rpc\('password_change_required'\)/);assert.match(s,/\/conta\/trocar-senha/)});
test('trocar-senha chama updateUser e password_change_done',()=>{const s=read('app/conta/trocar-senha/page.tsx');assert.match(s,/updateUser\(\{password/);assert.match(s,/rpc\('password_change_done'\)/)});
test('link vencido mostra pedir novo link',()=>{const s=read('app/conta/nova-senha/page.tsx')+read('app/AuthCard.tsx');assert.match(s,/Link vencido/);assert.match(s,/Pedir novo link/);assert.match(s,/otp_expired/)});
test('regras da senha visíveis e mínimo de 8',()=>{const s=read('app/AuthCard.tsx');assert.match(s,/Mínimo de 8 caracteres/);assert.match(s,/As duas senhas são iguais/);assert.match(s,/Mostrar senha|Ocultar senha/);assert.doesNotMatch(read('app/conta/nova-senha/page.tsx'),/minLength=\{10\}/)});
test('telas usam a identidade Vinha',()=>{const s=read('app/AuthCard.tsx'),css=read('app/auth-screens.css');assert.match(s,/Gestão que frutifica/);assert.match(css,/#193f30/);assert.match(css,/#d9b960/);for(const p of ['app/recuperar-acesso/page.tsx','app/conta/nova-senha/page.tsx','app/conta/trocar-senha/page.tsx'])assert.match(read(p),/AuthCard/,p);for(const m of css.matchAll(/font-size:(\d+)px/g))assert.ok(Number(m[1])>=12,m[0])});

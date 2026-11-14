import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {authError, loginProblems, passwordHint, registrationSteps, signupProblems, stepMissing} from '../shared/login-rules.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
test('senha: tamanho, letras e números e confirmação', () => {
  assert.equal(passwordHint('abc', 'abc').ok, false);
  assert.equal(passwordHint('abcdefgh', 'abcdefgh').ok, false, 'sem número');
  assert.equal(passwordHint('abcd1234', 'abcd1235').ok, false, 'senhas diferentes');
  assert.equal(passwordHint('abcd1234', 'abcd1234').ok, true);
});
test('cadastro em etapas cobre todos os campos e aponta o que falta', () => {
  const all = registrationSteps.flatMap((s) => s.fields).sort(),
    fields = read('shared/member-profile.ts')
      .match(/\['([a-z_]+)','/g)
      .map((x) => x.slice(2, -3))
      .sort();
  assert.deepEqual(all, fields, 'nenhum campo do cadastro fica de fora');
  assert.deepEqual(stepMissing({full_name: 'Ana', birth_date: ''}, ['full_name', 'birth_date']), ['birth_date']);
  assert.deepEqual(stepMissing({}, ['complement']), [], 'complemento é opcional');
});
test('tela de entrada e agenda com identidade Vinha', () => {
  const login = read('android-app/src/LoginScreen.tsx'),
    agenda = read('android-app/src/AgendaScreens.tsx'),
    sql = read('supabase/migrations/20261114140000_agenda_categoria_salvos.sql');
  for (const t of ['Que bom ver você', 'Faça parte por aqui', 'Esqueci minha senha', 'Mostrar senha', 'Conhecer o app sem entrar', 'termos de uso'])
    assert.ok(login.includes(t), t);
  assert.match(agenda, /Salvos \(/);
  assert.match(agenda, /category_color/);
  assert.match(sql, /revoke all on function public\.member_saved_events\(uuid,text,uuid\) from public,anon/);
});

test('criar conta: diz exatamente o que falta e traduz os erros', () => {
  const ok = {name: 'Ana Lúcia Prado', phone: '(16) 99999-9999', unit: 'u', email: 'ana@exemplo.com', password: 'segredo12', confirm: 'segredo12', terms: true};
  assert.deepEqual(signupProblems(ok), []);
  assert.deepEqual(signupProblems({...ok, name: 'Ana'}), ['Digite seu nome e sobrenome.']);
  assert.deepEqual(signupProblems({...ok, phone: '9999'}), ['Digite o WhatsApp com DDD.']);
  assert.deepEqual(signupProblems({...ok, unit: ''}), ['Escolha a igreja à qual você pertence.']);
  assert.deepEqual(signupProblems({...ok, confirm: 'outra123'}), ['As duas senhas precisam ser iguais.']);
  assert.deepEqual(signupProblems({...ok, terms: false}), ['Marque que você aceita os termos de uso e a política de privacidade.']);
  assert.equal(signupProblems({name: '', phone: '', unit: '', email: 'x', password: '1', confirm: '', terms: false}).length, 6);
  assert.deepEqual(loginProblems('ana@exemplo.com', ''), ['Digite sua senha.']);
  assert.match(authError('User already registered', true), /já tem conta/);
  assert.match(authError('Email not confirmed', false), /confirmar o e-mail/);
  assert.match(authError('Invalid login credentials', false), /não conferem/);
  const ui = read('android-app/src/LoginScreen.tsx'),
    app = read('android-app/src/MprApp.tsx');
  assert.doesNotMatch(ui, /disabled=\{!canSubmit/, 'botão não fica travado sem explicação');
  for (const t of ['Nome completo', 'WhatsApp', 'você completa depois', 'Repita a senha', 'Li e aceito']) assert.ok(ui.includes(t), t);
  assert.match(app, /data:\{full_name:/, 'nome, WhatsApp e igreja vão junto na criação da conta');
});

test('e-mails de conta no padrão Vinha e páginas de retorno', async () => {
  const {templates} = await import('./auth-emails.mjs');
  for (const k of ['confirmation', 'recovery', 'magic_link', 'email_change', 'invite', 'reauthentication']) {
    assert.ok(templates[k].html.includes('#163d2f') && templates[k].html.includes('Vinha'), k + ' com a identidade Vinha');
    assert.ok(!/[ ]/.test(templates[k].subject));
  }
  assert.match(templates.confirmation.html, /\{\{ \.Data\.church_name \}\}/, 'confirmação cita a igreja do membro');
  assert.match(templates.confirmation.html, /\{\{ \.ConfirmationURL \}\}/);
  assert.match(templates.reauthentication.html, /\{\{ \.Token \}\}/);
  const app = read('android-app/src/MprApp.tsx');
  assert.match(app, /emailRedirectTo:'https:\/\/app\.vinhaigrejas\.com\.br\/conta-confirmada'/);
  assert.match(app, /redirectTo:'https:\/\/app\.vinhaigrejas\.com\.br\/nova-senha'/);
  assert.match(read('app/nova-senha/page.tsx'), /updateUser\(\{password\}\)/);
  assert.match(read('app/conta-confirmada/page.tsx'), /E-mail confirmado!/);
});

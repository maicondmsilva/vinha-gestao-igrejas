# Usuários: ficha, criação sem convite, senha e e-mails · Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A gestão cria, edita e exclui usuários numa ficha que edita o mesmo cadastro do membro, sem convite. O cadastro pelo app dá acesso na hora, a reprovação avisa a pessoa, e as telas de senha e os e-mails seguem a identidade Vinha.

**Architecture:**
- **Banco:** as regras ficam em `private.staff_user` (dados e permissões).
- **Servidor:** a rota só mexe no login (Supabase Auth, chave administrativa) **depois** que o banco autorizou. Se a criação do login falhar, o vínculo é desfeito.
- **Telas:** uma ficha (`UserSheet.tsx`) aberta pela lista atual.
- **E-mails:** um HTML base único em código.

**Tech Stack:** Supabase (Postgres, pgTAP, Auth Admin), vinext/React, nodemailer (SMTP de notificações), testes `node --test`, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-12-usuarios-ficha-design.md`

## Global Constraints
- Um login por pessoa, o mesmo no app e no painel.
- Senha com no mínimo 8 caracteres. Nunca é devolvida, registrada em auditoria ou mostrada depois de salva.
- Senha definida pelo painel ⇒ `password_change_required=true`; a troca no primeiro acesso é obrigatória. Senha em branco na edição ⇒ não altera.
- Sem botão de gerar senha.
- Excluir = remover o vínculo (`organization_memberships`) e as permissões avulsas. Login e membro continuam.
- O dono não é excluído; ninguém exclui a si mesmo; administrador só é excluído pelo dono; ninguém concede papel acima do próprio.
- E-mails saem de `notificacoes@vinhaigrejas.com.br` com o HTML base Vinha (cabeçalho `#193f30`, borda `#d9b960`, "Vinha · Gestão que frutifica").
- Textos em português, com a identidade Vinha (sem nomes ou layout da InChurch).

## Review Focus
1. **E-mail já usado por outro login** ao criar ou editar: recusa com "Este e-mail já pertence a outra conta", sem expor dados da outra pessoa. Teste na Task 3.
2. **Falha do Supabase Auth depois de o banco aceitar**: a rota desfaz o vínculo e responde erro; não fica vínculo sem login. Teste na Task 3 (falso cliente que falha).
3. **Duas pessoas editando a mesma ficha**: a versão protege (409 "Atualize a ficha"). Teste na Task 1.
4. **Link de recuperação vencido ou já usado**: a tela mostra "Link vencido" com o botão "Pedir novo link", não uma página em branco. Teste na Task 6.
5. **SMTP fora do ar na reprovação**: o alerta no app é gravado mesmo assim, e o e-mail fica na fila com nova tentativa. Teste na Task 5.

---

### Task 1: Banco · ficha, exclusão, busca e senha obrigatória

**Files:**
- Create: `supabase/migrations/20261113100000_usuarios_ficha.sql`
- Test: `supabase/tests/staff_user.sql`

**Interfaces:**
- Produces:
  - `public.staff_user(p_org uuid, p_action text, p_data jsonb) returns jsonb`, com as ações:
    - `get {membership}` → `{membership:{id,role,status,unit_id,version}, person:{…people, address, marriage_date, is_pastor}, groups:{cells[],teams[],kids[]}, hasLogin, email}`;
    - `search {q}` → `{items:[{person,name,email,cpf_masked,unit,hasLogin,membership}]}`;
    - `save {membership?, person?, version, role, unit, account:{name,phone,email}, address:{…}, extra:{gender,cpf,birth_date,marriage_date,baptism_date,is_pastor}}` → `{ok,membership,person,needsLogin:boolean,loginUser:uuid|null}`;
    - `remove {membership, version}` → `{ok}`;
    - `link_login {membership, user}` → `{ok}`, chamada pela rota depois de criar o login.
  - Colunas novas: `people.marriage_date date`, `people.is_pastor boolean not null default false`, `organization_memberships.password_change_required boolean not null default false`.
  - `public.password_change_done() returns void` (apaga a marca do próprio usuário).
  - Migração cancela os convites `pending` (`status='revoked'`).

- [ ] **Step 1: Write the failing tests** em `supabase/tests/staff_user.sql`. Os nomes (`lives_ok`/`throws_ok`/`is`) já dizem o que cada um confere:
  - `dono abre a ficha completa` (a ficha traz nome, celular e endereço do membro);
  - `salvar grava no membro e no vínculo` (`people.phone` alterado e `organization_memberships.role` alterado);
  - `versão antiga recusada` (40001);
  - `pastor não promove a administrador` (42501);
  - `não exclui o dono` / `não exclui a si mesmo` / `admin só pelo dono` (42501);
  - `excluir remove vínculo e permissões, mantém membro` (`people` continua, `permission_grants` vazio);
  - `busca encontra por nome, e-mail e CPF` (CPF mascarado `***.456.789-**`);
  - `pessoa nova cria membro e pede login` (`needsLogin=true`);
  - `convites pendentes cancelados`;
  - `password_change_done apaga a marca`.
- [ ] **Step 2: Run** no banco de teste. Expected: FAIL (função inexistente).
- [ ] **Step 3: Implement** a migração.
  - Permissão: papel dono/admin/pastor (como `staff-routes.ts` hoje) **ou** `private.permission_any(org, '{settings.users:edit}')`.
  - Papel concedido limitado ao do autor (ordem `owner > admin > pastor > secretary = finance = leader > member > viewer`).
  - Auditoria `staff.user.saved` / `staff.user.removed`.
- [ ] **Step 4: Run** `staff_user.sql` e as suítes existentes `access_identity_privileges.sql` e `permissions_base.sql`. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Usuários: ficha, exclusão e busca no banco`.

### Task 2: Cadastro pelo app nasce ativo; reprovação gera aviso e fila de e-mail

**Files:**
- Create: `supabase/migrations/20261113110000_cadastro_app_ativo_reprovacao.sql`
- Test: `supabase/tests/member_profile_link.sql` (novos casos) e `supabase/tests/member_self_service.sql` (ajustes)

**Interfaces:**
- Produces:
  - Tabela `private.member_review_emails(id, organization_id, request_id, user_id, recipient, subject, items jsonb, reason, status text check in('pending','sent','failed'), attempts int, next_at timestamptz, created_at)`.
  - Função `private.member_review_email_batch(p_limit int) returns setof private.member_review_emails`, que reserva os itens pendentes para envio.
  - Função `public.member_review_email_mark(p_id uuid, p_ok boolean, p_error text)` (só `service_role`).
  - Na reprovação (total ou parcial), `member_profile_review2` grava um item na caixa do app (`member_inbox`, com destino `profile` e o texto "O que precisa ajustar") e um item `pending` na fila de e-mail.

- [ ] **Step 1: Write the failing tests:**
  - `cadastro pelo app nasce ativo` (`organization_memberships.status='active'` logo após `submit`);
  - `reprovação gera alerta no app com os campos e o motivo`;
  - `reprovação parcial lista só os campos não aprovados`;
  - `reprovação coloca e-mail na fila`;
  - `aprovação total não gera aviso de ajuste`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement:**
  - alterar `member_self_service`, onde hoje o vínculo nasce `pending`, por substituição exata do trecho (como nas migrações anteriores);
  - incluir o aviso e a fila em `member_profile_review2`.
- [ ] **Step 4: Run** as suítes. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Cadastro pelo app ativo na hora; reprovação avisa o membro`.

### Task 3: Rotas do painel · criar, editar, excluir, buscar

**Files:**
- Modify: `app/lib/supabase/staff-routes.ts` (novas `userGET`, `userPOST`, `userPATCH`, `userDELETE`, `userSearchGET`; remover `invitesPOST`)
- Create: `app/api/users/[id]/route.ts`, `app/api/users/search/route.ts`
- Modify: `app/api/users/invites/route.ts` → responde 410 "Convites encerrados. Crie o usuário em Usuários e permissões."
- Test: `scripts/staff-user-route.test.mjs`

**Interfaces:**
- Consumes: `public.staff_user` (Task 1) e `supabaseAdminClient()` de `app/lib/supabase/server-admin.ts`.
- Produces:
  - `POST /api/users` com `{person?, account:{name,phone,email,password?}, role, unit, address, extra}` → 201 `{membership, person}`;
  - `PATCH /api/users/{id}`, mesmo corpo mais `version` → 200;
  - `DELETE /api/users/{id}?version=n` → 200;
  - `GET /api/users/{id}` → a ficha;
  - `GET /api/users/search?q=` → a busca.

- [ ] **Step 1: Write the failing tests**, com falsos clientes de banco e de Auth no padrão de `scripts/member-agenda.test.mjs`:
  - `cria login só depois do banco autorizar` (a ordem das chamadas é `staff_user` → `auth.admin.createUser` → `link_login`);
  - `senha com menos de 8 recusada` (400);
  - `resposta nunca traz a senha`;
  - `falha do Auth desfaz o vínculo` (chama `staff_user('remove')`);
  - `e-mail em uso vira mensagem clara` (409);
  - `senha em branco na edição não chama updateUserById`;
  - `senha nova na edição marca troca obrigatória`;
  - `convite responde 410`.
- [ ] **Step 2: Run** `node --experimental-strip-types --test scripts/staff-user-route.test.mjs`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Criar o login com `auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name}})`.
  - Senha nova na edição: `updateUserById(id,{password})` e marcar `password_change_required` por `staff_user('save')`.
  - Mudança de e-mail: `updateUserById(id,{email,email_confirm:true})`.
- [ ] **Step 4: Run** o teste, `pnpm run test:security` e `pnpm run check:types:core`. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Usuários: rotas de criar, editar e excluir sem convite`.

### Task 4: Ficha do usuário (tela)

**Files:**
- Create: `app/UserSheet.tsx`, `app/user-sheet.css`
- Modify: `app/StaffDirectory.tsx`:
  - clicar no usuário abre `UserSheet`;
  - o botão "Novo usuário" abre a busca e depois a ficha;
  - sai a lista e o formulário de convites.
- Test: `scripts/user-sheet.test.mjs` (estático) e a captura Playwright

**Interfaces:**
- Consumes: rotas da Task 3; `UserPermissions` (aba Permissões, já existe, modo `embedded`).
- Produces: `UserSheet({membershipId?:string; person?:string; close:()=>void; saved:(msg:string)=>void})`.

- [ ] **Step 1: Write the failing tests:**
  - `ficha tem os quatro blocos e permissões` (os textos "Conta", "Endereço", "Informações adicionais", "Grupos" e "Permissões" aparecem);
  - `campo senha diz que em branco mantém` (texto "Deixe em branco para manter a senha atual");
  - `sem botão de gerar senha` (não contém "Gerar");
  - `StaffDirectory não usa convites` (não contém `/api/users/invites`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** a ficha em painel lateral (tela cheia no celular), com o padrão visual de `pending-profiles.css` e `people-form.css`. Ações: Salvar, Excluir (confirmação "Tirar o acesso de {nome}? O cadastro de membro continua.") e Voltar.
- [ ] **Step 4: Run** os testes e as capturas: ficha nova, ficha existente e celular. Expected: PASS, sem rolagem horizontal.
- [ ] **Step 5: Commit** com a mensagem `Usuários: ficha completa do usuário`.

### Task 5: E-mails Vinha e envio da reprovação

**Files:**
- Create: `shared/vinha-email.ts`, `docs/email/vinha-base.html`, `app/lib/member-review-email.ts`
- Modify: a rotina de envio usada por Eventos (`app/lib/event-email.ts` é chamada pela rota agendada `app/api/notifications/route.ts`), para também processar `member_review_email_batch`
- Modify: os modelos de e-mail do Supabase Auth (14), pela API de configuração do projeto (`PATCH /v1/projects/{ref}/config/auth`): mesmo rodapé e botão, links para `/recuperar-acesso` e `/conta/nova-senha`
- Test: `scripts/vinha-email.test.mjs`

**Interfaces:**
- Produces:
  - `vinhaEmail({title:string; intro:string; items?:string[]; action?:{label:string;url:string}; church?:string}): {html:string; text:string}`;
  - `sendMemberReviewEmails(client, env, limit=20): Promise<{sent:number; failed:number}>`.

- [ ] **Step 1: Write the failing tests:**
  - `e-mail tem marca e cores Vinha` (contém `#193f30`, `#d9b960` e `Gestão que frutifica`);
  - `itens viram lista`;
  - `texto escapa HTML` (`<script>` vira texto);
  - `sem SMTP, marca falha e reagenda` (`member_review_email_mark(id,false,…)`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Use `eventEmailConfigured(env)` para saber se o SMTP está pronto. O botão leva a `/membro/{slug}?corrigir=1`.
- [ ] **Step 4: Run** os testes. Envie um e-mail real de teste no ambiente de teste e confira o visual na caixa.
- [ ] **Step 5: Commit** com a mensagem `E-mails Vinha: base única e aviso de reprovação`.

### Task 6: Telas de senha com identidade Vinha e troca obrigatória

**Files:**
- Modify: `app/recuperar-acesso/page.tsx`, `app/conta/nova-senha/page.tsx`
- Create: `app/auth-screens.css`, `app/conta/trocar-senha/page.tsx`
- Modify: `app/SupabaseLogin.tsx` (depois do login, se `password_change_required`, vai para `/conta/trocar-senha`) e `app/lib/supabase/access.ts` (expõe a marca no `access_context`)
- Test: `scripts/auth-screens.test.mjs` e capturas

**Interfaces:**
- Consumes: `public.password_change_done()` (Task 1).

- [ ] **Step 1: Write the failing tests:**
  - `login com troca obrigatória vai para trocar-senha`;
  - `trocar-senha chama updateUser e password_change_done`;
  - `link vencido mostra pedir novo link` (texto "Link vencido" e o botão "Pedir novo link");
  - `regras da senha visíveis` (texto "Mínimo de 8 caracteres").
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** o cartão central com a marca Vinha (letreiro "Vinha · Gestão que frutifica", verde `#193f30`, faixa dourada `#d9b960`) e os estados: enviando, enviado, vencido e alterado. Botão mostrar/ocultar senha.
- [ ] **Step 4: Run** os testes e as capturas no computador e no celular. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Telas de senha com a identidade Vinha e troca no primeiro acesso`.

### Task 7: Publicação

- [ ] Rodar todas as suítes pgTAP no banco de teste, os testes do CI, `format:check`, `check:types:core` e o build.
- [ ] Aplicar as migrações das Tasks 1–2 na produção.
- [ ] Abrir o PR, aguardar o CI, juntar na `main` e atualizar a `develop`.
- [ ] Teste de ponta a ponta no ambiente de teste: criar usuário com senha, entrar, trocar a senha, reprovar uma solicitação do app e conferir o e-mail recebido.

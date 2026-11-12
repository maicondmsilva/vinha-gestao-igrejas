# Vínculos familiares · Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ligar pessoas por parentesco (com o vínculo inverso automático), mostrar a família no formulário e na ficha, sugerir responsáveis no Kids e permitir que o membro peça a inclusão de um familiar pelo app.

**Architecture:**
- **Tabela:** `private.person_relationships`, guardada nos dois sentidos.
- **Função:** `private.person_family`, que decide permissões e mantém o par inverso.
- **Rota:** `/api/people/family`.
- **Telas:** um componente `FamilyLinks.tsx`, usado no formulário e na ficha.
- **Pedido pelo app:** reaproveita `member_family_requests` com o tipo novo `relative`.

**Tech Stack:** Supabase (Postgres, pgTAP), vinext/React, testes `node --test`, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-12-vinculos-familiares-design.md`

## Global Constraints
- **Parentescos** (valores gravados): `conjuge`, `pai_mae`, `filho`, `irmao`, `avo`, `neto`, `tio`, `sobrinho`, `padrasto_madrasta`, `enteado`, `responsavel_legal`, `tutelado`, `outro`.
- **Inversos:**
  - `pai_mae↔filho`, `avo↔neto`, `tio↔sobrinho`;
  - `padrasto_madrasta↔enteado`, `responsavel_legal↔tutelado`;
  - `conjuge`, `irmao` e `outro` são o próprio inverso.
- **Rótulos na tela:**
  - Cônjuge, Pai/Mãe, Filho(a), Irmão(ã);
  - Avô/Avó, Neto(a), Tio(a), Sobrinho(a);
  - Padrasto/Madrasta, Enteado(a);
  - Responsável legal, Tutelado(a), Outro.
- **Permissões:**
  - ver exige `private.person_record_view` nas duas pessoas;
  - criar, editar ou remover exige `private.person_record_manage` nas duas;
  - cadastro rápido segue a regra de inclusão de `people`.
- O app mostra ao membro só o **nome e o parentesco** dos familiares.
- Visual no padrão novo (letras ≥ 13px, `var(--tenant)`).

## Review Focus
1. **Familiar de outra igreja do mesmo ministério:** o vínculo é permitido se a pessoa pode ver e editar as duas. A lista mostra a igreja do familiar. Teste na Task 1.
2. **Excluir ou reprovar uma pessoa que tem vínculos:** os vínculos dela somem dos dois lados (chave estrangeira com `on delete cascade` e filtro de `status<>'rejected'`). Teste na Task 1.
3. **Trocar o parentesco de um vínculo existente:** o inverso é atualizado junto, sem deixar sobra. Teste na Task 1.
4. **Duas pessoas editando a família ao mesmo tempo:** a versão protege (40001). Teste na Task 1.
5. **Pedido do app para alguém que já existe** (mesmo nome e nascimento): quem analisa pode ligar à pessoa existente em vez de criar outra. Teste na Task 4.

---

### Task 1: Banco · vínculos, inverso, permissões e sugestão de responsáveis

**Files:**
- Create: `supabase/migrations/20261113120000_vinculos_familiares.sql`
- Test: `supabase/tests/person_family.sql`

**Interfaces:**
- Produces:
  - `public.person_family(p_org uuid, p_action text, p_data jsonb) returns jsonb`, com as ações:
    - `list {person}` → `{items:[{id,person,name,relation,age,journey,unit,same_household,marriage_date,version}], canEdit}`;
    - `set {person, related, relation, same_household, marriage_date?, copy_address?, version}` → `{ok,id,version}`;
    - `remove {id, version}` → `{ok}`;
    - `quick_create {person, name, birth_date?, journey, relation, same_household}` → `{ok,related}`;
    - `suggest_guardians {child}` → `{items:[{person,name,relation}]}`.
  - Coluna `people.marriage_date` (com `add column if not exists`; a migração de Usuários também a cria).

- [ ] **Step 1: Write the failing tests**:
  - `pai_mae cria filho do outro lado`, repetido para cada par da lista de inversos;
  - `par único` (23505);
  - `não liga a si mesmo` (23514);
  - `trocar parentesco atualiza o inverso`;
  - `remove apaga os dois sentidos`;
  - `sem editar uma das pessoas, recusa` (42501);
  - `sem ver, não lista` (42501);
  - `copy_address copia o endereço`;
  - `cônjuge grava data de casamento nos dois`;
  - `cadastro rápido cria pessoa na igreja da principal`;
  - `sugestão traz pai_mae, avo e responsavel_legal`;
  - `pessoa reprovada some da lista`;
  - `versão antiga recusada` (40001).
- [ ] **Step 2: Run** no banco de teste. Expected: FAIL.
- [ ] **Step 3: Implement.** O inverso é uma função `private.relation_inverse(text) returns text` (imutável). A auditoria grava `people.family.saved` e `people.family.removed`.
- [ ] **Step 4: Run** `person_family.sql`, `members_rls.sql` e `permissions_people_events_communication.sql`. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Vínculos familiares no banco`.

### Task 2: Rota e componente de família (painel)

**Files:**
- Create: `app/api/people/family/route.ts`, `app/lib/family.ts` (validação, rótulos, inversos para a tela), `app/FamilyLinks.tsx`, `app/family-links.css`
- Modify: `app/DashboardApp.tsx`:
  - etapa 2 do `PersonModal`: troca o aviso "Vínculos familiares serão disponibilizados…" por `<FamilyLinks person={id} editable/>`; num cadastro novo, mostra "Salve o cadastro para adicionar familiares";
  - `PersonProfile`: seção "Família" com `<FamilyLinks person={id}/>`.
- Test: `scripts/family.test.mjs`

**Interfaces:**
- Consumes: `public.person_family` (Task 1).
- Produces:
  - `familyCommand(value:unknown)` e `familyQuery(request:Request)`, que validam o pedido no padrão de `app/lib/worship.ts`;
  - `relationLabels: Record<string,string>`;
  - `FamilyLinks({person:string; editable?:boolean})`.

- [ ] **Step 1: Write the failing tests:**
  - `parentesco fora da lista recusado`;
  - `ids inválidos recusados`;
  - `rótulos para todos os parentescos`;
  - `rota confere a igreja da sessão` (texto `p_org:auth.access!.membership.organization_id`);
  - `formulário não mostra mais o aviso antigo`.
- [ ] **Step 2: Run** `node --experimental-strip-types --test scripts/family.test.mjs`. Expected: FAIL.
- [ ] **Step 3: Implement** `FamilyLinks`:
  - lista em cartões com iniciais, nome (abre a ficha), parentesco, idade, igreja e a etiqueta "Mora junto";
  - "Adicionar familiar": busca em Pessoas (`/api/people?q=`) ou "Cadastrar rápido", depois parentesco, "mora junto" e "copiar endereço";
  - editar e remover com confirmação.
- [ ] **Step 4: Run** os testes e as capturas no computador e no celular, com e sem familiares. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Pessoas: família no cadastro e na ficha`.

### Task 3: Kids · sugestão de responsáveis

**Files:**
- Modify: a tela de cadastro de criança e responsáveis do Kids, em `app/KidsFoundation.tsx` (busca de responsável)
- Test: `scripts/kids-foundation.test.mjs` (novo caso)

**Interfaces:**
- Consumes: `person_family('suggest_guardians')` pela rota da Task 2 (`GET /api/people/family?suggest=1&child=`).

- [ ] **Step 1: Write the failing test:** `kids mostra sugeridos da família` (o componente chama `suggest=1` e mostra a seção "Da família").
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement:**
  - mostrar a seção "Da família" acima da busca, com o botão "Usar como responsável";
  - escolher um sugerido só preenche o formulário de responsável: a aprovação do Kids continua como hoje.
- [ ] **Step 4: Run** `scripts/kids-foundation.test.mjs` e a suíte pgTAP `kids_foundation.sql`. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Kids: responsáveis sugeridos pela família`.

### Task 4: Aplicativo · minha família e pedido de inclusão

**Files:**
- Create: `supabase/migrations/20261113130000_familia_app.sql`
- Modify: `app/MemberFamilyPortal.tsx` (seção "Minha família" e o botão "Pedir inclusão de familiar")
- Modify: `app/PendingProfiles.tsx` (seção "Familiares", com aprovar ou ligar a uma pessoa existente)
- Test: `supabase/tests/person_family.sql` (casos do app) e `scripts/member-family.test.mjs`

**Interfaces:**
- Produces:
  - `member_family_requests.kind` aceita `relative`, com `data` igual a `{name, birth_date, relation, same_household}`;
  - `member_family_admin` ganha a ação `review_relative {id, decision:'approve'|'reject', person?:uuid, reason}`;
  - `member_self_service` (ação `family`) devolve `[{name,relation}]`.

- [ ] **Step 1: Write the failing tests:**
  - `membro vê só nome e parentesco`;
  - `pedido relative entra pendente`;
  - `aprovar cria pessoa e vínculo`;
  - `aprovar ligando a pessoa existente não duplica`;
  - `reprovar avisa o membro`, usando a caixa de avisos do plano de Usuários, Task 2, quando ela já existir;
  - `PendingProfiles tem seção Familiares`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** a migração (ampliar o `check` de `kind`, as novas ações) e as telas.
- [ ] **Step 4: Run** as suítes `member_family.sql`, `person_family.sql` e `member_self_service.sql`, e os testes `scripts/member-family.test.mjs` e `scripts/member-self-service.test.mjs`. Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `App: minha família e pedido de inclusão de familiar`.

### Task 5: Publicação
- [ ] Todas as suítes no banco de teste, mais o CI local, o format e o build.
- [ ] Aplicar as migrações na produção.
- [ ] PR, CI, juntar na `main`, atualizar a `develop`.
- [ ] Conferir no ambiente de teste: ligar mãe e filho e ver os dois lados, cadastro rápido de filho, sugestão no Kids, pedido pelo app aprovado.

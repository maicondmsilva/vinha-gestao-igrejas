# Kids no telão, etiqueta e rascunho do perfil: plano de implementação

> **Para agentes:** use superpowers:executing-plans. Execução nativa, autorizada pelo responsável pelo projeto.

**Objetivo:** chamado Kids no telão (Holyrics) com o número da etiqueta, e rascunho do perfil salvo na plataforma.
**Arquitetura:** tudo no banco. O gatilho de `kids_guardian_calls` usa `pg_net` para chamar `api.holyrics.com.br`, com os segredos guardados no Vault. O painel e os apps só chamam funções RPC.
**Tecnologias:** Postgres/Supabase (pg_net, supabase_vault, pgTAP), Next.js (painel), React Native (apps).
**Especificação:** `docs/superpowers/specs/2026-11-14-kids-telao-rascunho-design.md`

## Restrições gerais
- Texto do telão: `Kids: responsável pela criança nº N, compareça à <sala>`, fechando sozinho em 60 s. Teste: `Teste do telão Kids pela Vinha`, por 10 s.
- A chave e o token do Holyrics nunca são devolvidos ao cliente.
- O rascunho só é visível para a própria conta. Vence em 30 dias e é apagado ao enviar.
- Toda a interface fica em português e na identidade da Vinha.

## Pontos de atenção
1. Duas salas fazendo entrada ao mesmo tempo no mesmo encontro não podem gerar números repetidos (trava por encontro e índice único).
2. Uma igreja sem telão configurado, ou com ele desligado, chama normalmente, sem erro e sem envio.
3. O banco local sem pg_net não pode quebrar: só registra.
4. Rascunho de outra conta: ler ou salvar dá vazio ou negado.
5. Rascunho com mais de 30 dias não volta.

### Tarefa 1: Etiqueta e telão no banco
**Arquivos:** `supabase/migrations/20261114230000_kids_etiqueta_telao.sql`, teste `supabase/tests/kids_projector.sql`.
**Interfaces produzidas:**
- `kids_attendance.tag_number int`;
- `kids_call` com `list` passa a devolver `tag` e `room` por item, e `tags: {attendanceId: number}`;
- `kids_call` com `call` aceita `projector boolean`;
- `public.kids_projector(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb`, com:
  - `get`, que devolve `{enabled, configured, updatedAt}`;
  - `save`, com `{enabled, apiKey?, token?}`;
  - `test`;
- `public.member_kids_present(p_org uuid) returns jsonb`, que devolve `{items:[{profile, child, tag, room}]}`.

Etapas:
- [ ] **Testes pgTAP:**
  - os números são 1 e 2;
  - `get` não expõe os segredos;
  - `save` é negado para quem não é coordenação;
  - o chamado com telão configurado grava um log `alert`;
  - a resposta grava um log `hide`;
  - sem configuração, nada é registrado;
  - `member_kids_present` mostra o número só ao responsável.
- [ ] Criar a migração e aplicá-la no banco local. Os testes devem passar.
- [ ] Commit.

### Tarefa 2: Rascunho do perfil
**Arquivos:**
- migração `supabase/migrations/20261114231000_rascunho_perfil.sql`;
- teste `supabase/tests/member_profile_draft.sql`;
- `android-app/src/MprApp.tsx`, com o efeito de rascunho nas linhas 35 e 42 e a função `submit` na 45.

**Interface:** `public.member_profile_draft(p_org uuid, p_action text, p_data jsonb default '{}') returns jsonb`, com:
- `get`, que devolve `{data, updatedAt}`;
- `save`, que recebe um objeto de até 4 KB, só com texto;
- `clear`.

Etapas:
- [ ] **Testes:**
  - salvar e ler na própria conta;
  - outra conta lê vazio;
  - um rascunho de 31 dias some;
  - `member_self_service submit` apaga o rascunho;
  - o rascunho não aparece na fila de revisão.
- [ ] Implementar e fazer os testes passarem.
- [ ] **App:**
  - carrega da plataforma;
  - salva 1,5 s depois que a pessoa para de digitar;
  - o SecureStore fica só como cópia de segurança sem conexão.
- [ ] Commit.

### Tarefa 3: Telas
**Arquivos:**
- painel: `app/KidsProjector.tsx` e `app/api/kids/projector/route.ts`, dentro da área Kids;
- Vinha Equipe: `staff-app/src/KidsBoard.tsx`;
- app da igreja: `android-app/src/KidsCallAlert.tsx` e a tela Kids em `FamilyScreens`;
- teste: `scripts/kids-calls.test.mjs`.

Etapas:
- [ ] **Painel:** Kids › Telão (Holyrics), com ligar ou desligar, chave, token, salvar, testar e um passo a passo.
- [ ] **Equipe:** mostrar "nº N" em cada criança e a opção "Mostrar no telão".
- [ ] **App:** cartão "Etiqueta nº N · Sala" para cada filho presente.
- [ ] Rodar os tipos (core, apps), os testes do CI, a formatação e o build.
- [ ] Commit, PR, CI, merge, aplicar em homologação e produção e gerar os APKs.

# Plano de subida da Vinha: GitHub, Supabase e Vercel

## 1. Objetivo

Migrar a Vinha do ambiente atual do Sites/Cloudflare para uma operação SaaS com:

- GitHub como fonte oficial do código e do histórico de mudanças;
- Vercel para homologação, previews e produção web;
- Supabase para autenticação, PostgreSQL, Storage e serviços de dados;
- ambientes totalmente separados para desenvolvimento, homologação e produção;
- promoção para produção somente depois de testes e aprovação.

## 2. Diagnóstico atual

- Repositório GitHub configurado: `maicondmsilva/vinha-gestao-igrejas`.
- Branch local atual: `main`, um commit à frente do GitHub e com alterações locais ainda não consolidadas.
- O build atual é concluído com sucesso usando `vinext build`.
- Não existem workflows em `.github/workflows`.
- O projeto ainda usa Vinext/Vite, plugin do Sites, Cloudflare Worker, D1 e R2.
- Existem 76 arquivos diretamente dependentes de `cloudflare:workers`, `env.DB` ou `env.FILES`.
- O banco funcional mais completo está representado por 49 migrações SQLite/Drizzle em `drizzle/`.
- O Supabase de produção `aoxibaaydfgffrdqtkva` está saudável, na região de São Paulo, mas contém somente a fundação de identidade e operação da plataforma: 7 migrações e 9 tabelas públicas.
- Ainda não existe um ambiente Supabase persistente de homologação.

Conclusão: a Vinha ainda não pode ser importada diretamente na Vercel como produção. Primeiro precisamos converter a aplicação para o runtime da Vercel e migrar o modelo D1/SQLite para PostgreSQL/Supabase.

## 3. Arquitetura recomendada

| Camada | Desenvolvimento | Homologação | Produção |
|---|---|---|---|
| Git | branches `feature/*` e `fix/*` | branch `develop` | branch `main` |
| Vercel | execução local e previews de PR | projeto `vinha-staging` | projeto `vinha-production` |
| URL | URL local ou preview temporário | `staging.vinhaigrejas.com.br` | `vinhaigrejas.com.br` e `app.vinhaigrejas.com.br` |
| Supabase | stack local via CLI/Docker | projeto hospedado atual, temporariamente | novo projeto de produção próximo ao lançamento |
| Dados | dados sintéticos | dados sintéticos e cenários de teste | dados reais |
| Pagamentos | sandbox | sandbox | credenciais de produção |

Durante o desenvolvimento, usar Supabase local e somente um projeto hospedado de homologação para permanecer no plano gratuito. Quando houver dados reais, a recomendação volta a ser dois projetos Supabase, criando uma barreira física entre homologação e produção.

## 4. Fluxo de branches e publicação

1. Criar uma branch `develop` a partir do ponto estável.
2. Cada mudança nasce em `feature/nome-da-funcionalidade` ou `fix/nome-do-problema`.
3. O Pull Request da feature aponta para `develop`.
4. O GitHub executa build, análise estática, testes e validação das migrações.
5. A Vercel cria um preview temporário para o Pull Request.
6. Após aprovação, a mudança entra em `develop` e atualiza `staging.vinhaigrejas.com.br`.
7. A equipe executa os testes de homologação.
8. A versão aprovada recebe uma tag de release e um Pull Request de `develop` para `main`.
9. O merge em `main` publica a Vercel de produção e aplica somente as migrações aprovadas no Supabase de produção.

Proteções obrigatórias para `main` e `develop`:

- bloquear push direto;
- exigir Pull Request;
- exigir pelo menos uma aprovação;
- invalidar aprovação após novos commits;
- exigir resolução das conversas;
- exigir sucesso do CI, preview e testes;
- proibir force push e exclusão;
- em `main`, exigir que a homologação tenha sido concluída.

## 5. Estratégia do banco de dados

### 5.1 Fonte oficial do esquema

O diretório `supabase/migrations/` será a única fonte oficial do esquema PostgreSQL. As migrações `drizzle/` atuais serão usadas como material de conversão, não como uma segunda cadeia de produção.

### 5.2 Migração D1/SQLite para PostgreSQL

1. Inventariar tabelas, índices, chaves, consultas e armazenamento usados pelos 76 arquivos dependentes de Cloudflare.
2. Converter tipos SQLite para PostgreSQL: inteiros booleanos, timestamps, JSON, chaves e constraints.
3. Consolidar as 49 migrações históricas em uma base PostgreSQL revisada.
4. Preservar e ampliar o isolamento multi-tenant com `organization_id`/`church_id` e RLS.
5. Substituir consultas `env.DB.prepare(...)` por uma camada única de acesso ao Supabase/Postgres.
6. Migrar `env.FILES`/R2 para Supabase Storage, com buckets e políticas por organização.
7. Gerar tipos TypeScript a partir do Supabase depois de cada mudança de esquema.

### 5.3 Dados por ambiente

- Desenvolvimento e homologação nunca recebem cópia bruta dos dados reais.
- Criar `supabase/seed.sql` com igreja, unidades, membros, evento, escala, Kids, financeiro e operadores fictícios.
- E-mails, CPFs, telefones, consentimentos e dados de crianças devem ser sintéticos.
- Storage de homologação recebe somente imagens e documentos de teste.
- Não haverá sincronização bidirecional entre homologação e produção.
- Somente esquema e código são promovidos; dados de teste não são promovidos.

### 5.4 Migrações seguras

Adotar o padrão expandir-migrar-remover:

1. adicionar estruturas novas sem quebrar a versão atual;
2. publicar código compatível com estrutura antiga e nova;
3. migrar ou preencher dados;
4. validar métricas e integridade;
5. remover a estrutura antiga em uma release posterior.

Antes de cada release de produção:

- executar todas as migrações do zero no banco local;
- aplicar em homologação;
- executar smoke tests e testes de RLS;
- revisar plano de backup e restauração;
- aplicar em produção antes ou junto do código compatível;
- executar verificação pós-migração.

Rollback de código será feito pela Vercel. Rollback de banco usará migração corretiva ou restauração de backup; não dependerá de apagar migrações já aplicadas.

## 6. Supabase por ambiente

### Produção futura

- Criar um projeto limpo próximo ao lançamento ou promover, após limpeza, o projeto hospedado atual.
- Restringir URLs de redirecionamento aos domínios oficiais.
- Usar chaves publicáveis no navegador e chaves privilegiadas somente no servidor.
- Revisar RLS, índices, backups, logs e alertas antes do lançamento.
- Configurar buckets, políticas, e-mails transacionais e webhooks de produção.

### Homologação

- Usar temporariamente o projeto hospedado atual como `Vinha Homologação`, sem dados reais.
- Aplicar a mesma cadeia de migrações da produção.
- Configurar Auth com `staging.vinhaigrejas.com.br`.
- Usar credenciais sandbox de Mercado Pago, Asaas e Safe2Pay.
- Usar e-mails e webhooks de teste.
- Limitar acesso à equipe autorizada.

### Previews de Pull Request

Fase inicial: previews da Vercel usam o Supabase de homologação com dados isolados por organização de teste.

Fase avançada: ativar Supabase Branching para criar um banco efêmero por Pull Request. Cada branch terá URL, chaves, Auth, Storage e banco próprios, sem dados da produção. Essa opção será adotada quando o plano Supabase e o volume de desenvolvimento justificarem o custo.

## 7. Preparação da aplicação para Vercel

1. Criar uma branch técnica `feature/vercel-supabase-migration`.
2. Fazer um checkpoint das alterações locais atuais sem misturá-las à migração.
3. Converter a aplicação de Vinext/Sites para Next.js padrão compatível com Vercel.
4. Remover do runtime de produção:
   - `@openai/sites-vite-plugin`;
   - `@cloudflare/vite-plugin`;
   - `cloudflare:workers`;
   - bindings D1/R2;
   - `worker.ts` como ponto principal.
5. Substituir o agendamento do Worker por Vercel Cron ou Supabase Cron/Edge Function, com autenticação de serviço e idempotência.
6. Migrar todas as rotas de API para Postgres/Supabase.
7. Migrar uploads e downloads para Supabase Storage.
8. Garantir que PDF, QR Code, webhooks e pagamentos funcionem no runtime Node da Vercel.
9. Criar scripts consistentes:
   - `dev`;
   - `build`;
   - `lint`;
   - `typecheck`;
   - `test`;
   - `test:e2e`;
   - `db:reset`;
   - `db:test`.
10. Criar health checks para aplicação, banco e integrações essenciais.

## 8. Variáveis e segredos

Variáveis mínimas, com valores diferentes em cada ambiente:

- `NEXT_PUBLIC_SUPABASE_URL`;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`;
- `SUPABASE_SERVICE_ROLE_KEY` somente no servidor;
- `NEXT_PUBLIC_APP_URL`;
- `APP_ENV`;
- segredos de criptografia;
- credenciais e tokens de webhook dos provedores financeiros;
- credenciais de e-mail, push e mensageria;
- tokens dos agendamentos internos.

Regras:

- nunca versionar `.env.local` ou credenciais;
- manter `.env.example` apenas com nomes e exemplos neutros;
- usar segredos distintos entre homologação e produção;
- girar qualquer chave já exposta em log, commit ou interface;
- impedir que a chave de serviço seja importada em componentes de navegador.

## 9. GitHub Actions

Criar workflows separados:

### `ci.yml` — todo Pull Request

- instalar dependências com lockfile;
- lint;
- typecheck;
- testes unitários;
- build;
- iniciar Supabase local e executar `db reset`;
- testar políticas RLS e isolamento entre igrejas;
- varredura de segredos e dependências.

### `deploy-staging.yml` — branch `develop`

- validar migrações;
- aplicar migrações no Supabase de homologação;
- acionar/acompanhar deploy da Vercel de homologação;
- executar smoke tests pós-deploy;
- registrar o resultado no GitHub Environment `staging`.

### `deploy-production.yml` — branch `main`

- exigir aprovação no GitHub Environment `production`;
- confirmar backup e estado saudável;
- aplicar migrações aprovadas;
- publicar ou promover o deploy da Vercel;
- executar smoke tests;
- interromper promoção e alertar em caso de falha.

## 10. Domínios e DNS

Na Hostinger, manter os nameservers e criar os registros indicados pela Vercel:

- `vinhaigrejas.com.br` → landing page/produção;
- `www.vinhaigrejas.com.br` → redirecionamento para o domínio principal;
- `app.vinhaigrejas.com.br` → painel das igrejas;
- `central.vinhaigrejas.com.br` → administração interna da Vinha;
- `staging.vinhaigrejas.com.br` → homologação.

Antes de alterar DNS de produção, preservar e conferir MX, SPF, DKIM e DMARC do e-mail da Hostinger. O domínio de homologação será configurado primeiro; produção só será apontada após aceite formal.

## 11. Fases de execução e critérios de saída

### Fase A — estabilizar o repositório

- consolidar alterações locais;
- sincronizar GitHub;
- criar `develop`, padrões de branch, proteção e templates de PR;
- criar CI básico.

Critério: clone limpo constrói a aplicação e todo PR recebe validação automática.

### Fase B — banco PostgreSQL reproduzível

- converter esquema D1/SQLite;
- criar seed sintético;
- levantar Supabase local;
- criar o projeto Supabase de homologação;
- validar RLS e multi-tenancy.

Critério: banco vazio é reconstruído integralmente por migrations + seed, sem ação manual.

### Fase C — compatibilidade Vercel

- converter runtime para Next.js padrão;
- migrar 76 arquivos dependentes de Cloudflare;
- migrar R2 para Storage;
- substituir agendamentos;
- adicionar testes das rotas críticas.

Critério: build e execução funcionam sem plugins Sites/Cloudflare.

### Fase D — homologação online

- criar Vercel `vinha-staging`;
- conectar branch `develop`;
- configurar segredos de homologação;
- configurar `staging.vinhaigrejas.com.br`;
- executar testes completos.

Critério: login, multi-tenant, membros, financeiro, células, Kids, eventos, escalas, comunicação, PDFs e arquivos aprovados em homologação.

### Fase E — produção controlada

- criar Vercel `vinha-production`;
- conectar `main`;
- revisar Supabase Produção;
- configurar segredos e domínios;
- executar ensaio de release e rollback;
- publicar em janela controlada.

Critério: smoke tests aprovados, monitoramento saudável e nenhuma regressão crítica.

### Fase F — operação contínua

- alertas, auditoria, backups e testes periódicos de restauração;
- métricas de erro, latência, filas, webhooks e pagamentos;
- revisão de segurança e desempenho do Supabase após migrações;
- procedimento documentado para incidentes e releases.

## 12. Ordem prática do próximo trabalho

1. Resolver o commit local pendente e sincronizar o GitHub.
2. Criar `develop` e a estrutura de CI.
3. Usar o projeto Supabase atual como homologação temporária e manter produção sem provisionamento até próximo do lançamento.
4. Produzir a migração-base PostgreSQL a partir das tabelas D1.
5. Criar seed seguro e testes de RLS.
6. Migrar a aplicação por módulos para a nova camada de dados.
7. Converter o runtime para Next.js/Vercel.
8. Publicar primeiro em `staging.vinhaigrejas.com.br`.
9. Homologar e corrigir.
10. Só então configurar e promover a produção.

## 13. Regra de ouro da promoção

Nenhuma mudança vai diretamente do computador para produção. Todo release deverá percorrer:

`feature/fix` → Pull Request → CI → Preview → `develop` → homologação → aprovação → `main` → produção.


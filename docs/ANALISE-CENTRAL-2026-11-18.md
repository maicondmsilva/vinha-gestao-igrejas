# Central da Vinha — análise e nova estrutura (18/11/2026)

## 1. O que foi analisado

| Área | Situação encontrada | O que mudou |
| --- | --- | --- |
| **Layout** | Cada uma das 27 páginas montava o próprio menu lateral, com itens diferentes entre si. Havia ainda uma barra fixa no rodapé com cerca de 21 atalhos em pílula, que cobria o conteúdo e quebrava no celular. Fontes de 7 a 10 px, títulos em serifa misturados com sem serifa. Não havia topo com o operador logado nem botão de sair. | **Estrutura única** (`CentralShell`): menu lateral agrupado (Clientes, Aplicativos, Comercial, Financeiro, Atendimento, Automações, Vinha), topo com caminho da página, alertas do chat, operador (iniciais, nome, papel) e Sair. Menu vira gaveta no celular. Tipografia mínima de 13 px, títulos sem serifa, botões principais no verde Vinha. Barra de atalhos do rodapé removida. |
| **Arquitetura** | Três componentes de navegação separados (`ChatNavigation`, `TrialNavigation`, `FinancialNavigation`), cada um com sua própria busca de dados e seu próprio intervalo de atualização. | Lógica reunida no `CentralShell`: uma consulta de demonstrações e uma de chat a cada 60 s, só com a aba visível. Contadores aparecem como selo no item do menu. Os três componentes foram removidos. |
| **Segurança** | Boa. Todas as rotas `/api/platform/*` usam `centralRoute`, que exige segundo fator (aal2), um único registro de operador ativo e papel válido. Escrita só para responsável e administração; "somente consulta" não grava. A única rota pública é a ativação de conta, por desenho. | Mantido. As novas rotas de aplicativos seguem o mesmo padrão: origem conferida, corpo limitado a 6 KB e versão contra edição simultânea. A rota da lista de build só aceita uma chave de pelo menos 32 caracteres, comparada em tempo constante. |

### Comparação com o painel das igrejas

O painel já tinha menu único, foto do usuário e barra recolhível. A Central agora segue a mesma linguagem: sidebar verde escura, item ativo em creme, cartões brancos com borda suave e topo fixo com desfoque. Ela tem identidade própria ("Administração da plataforma") para não ser confundida com o painel de uma igreja.

## 2. Aplicativo personalizado: liberar rápido e atualizar todos

### Princípios

- **Um código para todos.** Telas, regras e correções são as mesmas para todos os ministérios. O que muda por ministério é só o perfil: nome no celular, ícone, cores e logo (vêm do painel), tema claro ou escuro (definido na Central) e os identificadores de loja.
- **Atualização para todos sem perder personalização.** Há um único projeto de atualizações (`vinha-app`), e cada ministério recebe as atualizações pelo seu próprio canal (`production-<perfil>`). O robô publica a mesma atualização em todos os canais. Nome, cores, logo e tema continuam vindo da Vinha ao abrir o app, por isso nunca se misturam.
- **Toda a personalização é feita pela equipe da Vinha.** Nome no celular, nome dentro do app, tema, cores, logo do ministério, abertura (foto ou vídeo) e ícone do celular são definidos só na Central › Aplicativos. No painel do ministério esses dados aparecem apenas para consulta: Configurações mostra o quadro "Identidade do aplicativo", o cadastro inicial não pede mais nome do app, cores nem logo, e Comunicação › Mídia do app só informa qual abertura está ativa. O banco recusa alterações feitas por fora da Central. As logos de cada igreja (unidades), usadas em relatórios, continuam com o ministério.

### Fluxo de liberação de um novo ministério

1. **Contratação:** em Ministérios, na ficha do cliente, marcar "Aplicativo personalizado". O ministério aparece em Aplicativos como "A liberar".
2. **Liberação:** na Central, em Aplicativos, a equipe define o nome no celular (até 30 letras) e o tema, confere a prévia do celular e clica em **Liberar aplicativo**. O perfil é criado sozinho, por exemplo `arvoredavida`.
3. **Identidade:** na seção Identidade do aplicativo, a equipe preenche nome dentro do app, cores, logo, abertura e ícone. Os arquivos vão direto para o armazenamento público dos apps (`vinha-app-assets`), por um link de envio assinado que o servidor emite depois de conferir o operador. O servidor confere o ícone no próprio arquivo enviado (PNG de 1024 × 1024 px).
4. **APK de teste:** no GitHub, em Actions › **Aplicativos dos ministérios**, rodar a ação *gerar-teste* com o perfil. Depois, marcar a etapa "Em teste".
5. **Lojas:** informar os identificadores Android e iOS (contas de desenvolvedor do próprio ministério), rodar *gerar-loja* e marcar "Na loja". Após a aprovação, marcar "Publicado".
6. **Atualizações:** rodar *atualizar* sem informar perfil. Todos os apps recebem a melhoria, sem nova revisão de loja, desde que a mudança não seja nativa.

As etapas são Contratado → Configurando → Em teste → Na loja → Publicado (ou Pausado). Cada gravação fica registrada no histórico de auditoria (`platform.app_saved`).

### Configuração necessária (uma vez)

| Onde | Nome | Para quê |
| --- | --- | --- |
| GitHub › Settings › Secrets › Actions | `EXPO_TOKEN` | Acesso do robô à conta Expo/EAS da Vinha |
| GitHub › Settings › Secrets › Actions | `EXPO_PROJECT_ID` | ID do projeto único `vinha-app` no EAS |
| GitHub › Settings › Secrets › Actions **e** Vercel (Production) | `VINHA_APPS_MANIFEST_TOKEN` | Mesma chave aleatória com pelo menos 32 caracteres, nos dois lugares. O robô usa essa chave para ler a lista de apps liberados na Central. |

Sem esses segredos, o robô para no primeiro passo com uma mensagem clara, e a lista de build recusa o acesso (403).

### O que muda sem e com nova versão do app

| Mudança | Como chega ao app |
| --- | --- |
| Nome dentro do app, cores, logo, abertura e tema | Pela Central; o membro vê na próxima vez que abrir o app |
| Telas e funções (código) | Robô com a ação *atualizar*, perfil em branco: todos os apps de uma vez, sem passar pela loja |
| Ícone, nome no celular, permissões e recursos nativos | Robô com *gerar-teste* e, depois, *gerar-loja*, seguido do envio à loja |

## 3. Banco de dados

- Migração `20261118090000_central_aplicativos.sql`:
  - tabela privada `private.ministry_apps`, com RLS ativo e sem acesso direto;
  - função `public.platform_apps` com as ações `list`, `save` e `manifest`;
  - o MPR é registrado como perfil `mpr` na etapa "Em teste".
- Migração `20261118120000_central_identidade_app.sql`:
  - função `platform_app_identity` (ler, nome e cores, logo, abertura e ícone), com segundo fator, escrita só para responsável e administração, controle de versão e auditoria;
  - travas em `organization_settings_save`, `save_organization_onboarding`, `save_church_brand` (logo do ministério) e `ministry_media_admin` (abertura);
  - coluna `ministry_apps.icon_url`; o robô recebe `iconUrl` na lista de geração.
- As duas migrações estão aplicadas em **produção e homologação**.

## 4. Testes

- `scripts/central-v2.test.mjs`: menu único, links válidos, páginas sem menu próprio, rotas protegidas, chave da lista de build, tema e canal por perfil.
- `supabase/tests/central_apps.sql` (18 verificações):
  - recusa sem segundo fator e para contas de igreja;
  - somente consulta não grava;
  - conflito de versão;
  - identificadores de loja obrigatórios ao publicar;
  - validação do identificador Android;
  - tema aplicado ao ministério;
  - auditoria.
- `supabase/tests/central_app_identity.sql` (28 verificações): Central lê e grava nome, cores, logo, abertura e ícone; painel, cadastro inicial e Comunicação não alteram mais a identidade; ícone só depois de liberar o app; leitura não grava.

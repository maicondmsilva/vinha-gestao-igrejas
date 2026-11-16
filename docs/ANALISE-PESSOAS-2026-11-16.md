# Análise do módulo Pessoas · 16/11/2026

Escopo: layout, arquitetura e organização do código, código sem uso, desempenho (lentidão), integração com o app da igreja e o Vinha Equipe, e segurança.
Cada item marcado como "remover" teve o impacto em outros módulos e nos dois apps conferido duas vezes (busca de uso no painel, em `shared/`, em `android-app/` e em `staff-app/`).

## 1. Lentidão: causas, em ordem de impacto

| #   | Causa                                                                                                                              | Evidência                                                                                                                                                                              | Efeito                                                                                                                                                                                                              |
| --- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1  | **Servidor nos EUA e banco no Brasil.** As funções da Vercel rodam em `iad1` (Washington) e o Supabase em `sa-east-1` (São Paulo). | Implantação de produção `dpl_36ap…`: `regions: ["iad1"]`; projeto Supabase: `region: sa-east-1`.                                                                                       | Cada ida ao banco cruza o continente (cerca de 120 ms). Uma chamada de Pessoas faz de 6 a 8 idas em sequência, o que soma cerca de 1 s por chamada **antes de qualquer processamento**. Afeta **todos os módulos**. |
| L2  | **O painel baixa 100 cadastros completos ao abrir, em qualquer página.**                                                           | `DashboardApp.tsx`: `fetch(peopleRequestUrl({limit:'100'}))` no carregamento. Cada cadastro traz endereço, contato de emergência, notas pastorais e termos (5 consultas extras).       | Da lista só se usa o total, na Visão geral, e ela abastece duas telas antigas que estão quebradas (item C2).                                                                                                        |
| L3  | **Os contadores das abas fazem 4 chamadas completas.**                                                                             | `PeopleDirectory.tsx`: Todos, Membros, Em integração e Visitantes viram 4 `GET /api/people?limit=1`. Cada uma repete autorização, contagem, numeração e as 5 consultas complementares. | 4 de cerca de 10 chamadas ao abrir Pessoas servem só para mostrar quatro números.                                                                                                                                   |
| L4  | **A lista traz dados que a tela não mostra.**                                                                                      | `GET /api/people` busca endereços, contatos, notas e termos de cada pessoa da página.                                                                                                  | Consultas e dados desnecessários; a ficha completa só é usada ao abrir a pessoa.                                                                                                                                    |
| L5  | **Autorização repetida a cada chamada.**                                                                                           | `authorizeSupabaseChurch`: `auth.getUser()` (ida ao serviço de autenticação), `access_context`, às vezes `permission_any` e `unit_module_enabled`. São 3 a 4 idas sequenciais.         | Multiplica o L1.                                                                                                                                                                                                    |
| L6  | **Um pacote único com o painel inteiro.**                                                                                          | `DashboardApp` gera 849 KB de JavaScript e 246 KB de CSS. Os 50 imports são fixos e nenhum módulo é carregado sob demanda.                                                             | Abrir Pessoas baixa também Financeiro, Kids, Eventos, Escalas… Pesa principalmente no celular.                                                                                                                      |

O banco **não** é o gargalo: a produção tem 5 pessoas, e os índices de `people` aparecem como "não usados" por haver pouco dado.
A regra de acesso (`person_record_view(id)` por linha) é aceitável hoje, mas cresce linearmente; vale observar quando passar de alguns milhares de cadastros.

**Contagem ao abrir Pessoas hoje:** cerca de 10 chamadas à API.

- Do painel: sessão, igrejas e as 100 pessoas.
- Da lista: a página da lista, 4 contadores, perfis pendentes, pedidos do app e aniversariantes.

Cada uma faz de 3 a 4 idas de autorização e de 2 a 8 de trabalho, todas EUA ↔ Brasil.

## 2. Código sem uso (conferido duas vezes)

`app/DashboardApp.tsx` tem 85 KB. **43 KB (51%) são componentes que nada mais chama**:

- `Dashboard`, `People` (a lista antiga de Pessoas, já substituída por `PeopleDirectory`), `Events`, `Branding` e `FamiliesAndTerms`;
- `MemberApp`, `KidsArea` e `KidsTools` (o Kids antigo);
- `PrinterSettings`, `LegacyPermissions`, `UnitAccessModal`, `Metric`, `Title` e `cellSectionUrl`.

**Método:**

1. Montei o grafo de chamadas a partir do componente principal.
2. Busquei cada nome no restante do painel, em `shared/` e nos dois apps.
3. Refiz a checagem dos imports. Na segunda passagem corrigi um erro de contagem da primeira; o resultado final está abaixo.

**Imports que sobram:**

- Imports sem uso no `DashboardApp`: `AccountingCenter`, `financeHref`, `financeSections` e `cellSections`. Só `useMemo` passa a sobrar quando o código morto sai.
- `app/AccountingCenter.tsx` (7,9 KB) só é importado ali e nunca usado. É um arquivo inteiro morto.

**Rotas antigas (Cloudflare D1) desligadas:** 49 rotas em `app/api` passam por `withLegacyContainment` e respondem sempre **503 "não liberado"**.

- `/api/kids` (sem subcaminho) é usada só pelo Kids antigo, que é código morto. Pode sair junto, sem impacto: os apps e o Kids novo usam `/api/kids/photo`, `/api/kids/setup`, `/api/kids-operations` e outras.
- As demais rotas desligadas **ainda são chamadas por telas vivas** (item C2). Não devem ser removidas antes de decidir o destino dessas telas.

## 3. Telas quebradas ligadas a Pessoas

| Tela no menu                                                           | O que acontece                                                                                                                                      | Recomendação                                                                                                                                                                                           |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Famílias e termos** (`FamilyTermManager`)                            | Chama `/api/terms`, `/api/children` e `/api/documents/pdf`, todas desligadas (503). Mostra textos fixos ("Versão 1.0 · vigente desde 25 ago 2026"). | Já existe o substituto: Pessoas › Termos (`ConsentTemplates`), os vínculos na ficha (`FamilyLinks`) e os termos por pessoa (`PersonConsents`). **Tirar do menu e redirecionar para Pessoas › Termos.** |
| **Aplicativo do membro** (`MemberAppPlatform` + `MemberNotifications`) | Chama `/api/app/registrations` e `/api/app/notifications`, ambas desligadas.                                                                        | A configuração do app já está em Configurações › Serviços e em Comunicação. **Revisar e retirar.**                                                                                                     |

Fora de Pessoas, mas encontrado na mesma busca, outras telas vivas chamam rotas desligadas:

- `CommunicationHub` e app-chat;
- `EventOperations`;
- `CellOperations`;
- `FinanceProviders`, `PaymentSettings` e `ReconciliationPanel`;
- `SecurityAccessCenter`;
- `/vinculos/*`, `/escalas/lideranca`, `/configuracoes/notificacoes/*` e `/suporte`.

Cada uma será tratada na análise do seu módulo.

## 4. Arquitetura e organização

- **Arquivo central sobrecarregado.** `DashboardApp.tsx` mistura a moldura do painel, o formulário de cadastro (`PersonModal`, 8 KB), a ficha (`PersonProfile`), o tipo `Person` (importado por `PeopleDirectory`) e telas antigas. **Proposta:** mover para `app/pessoas/` (`PersonModal.tsx`, `PersonProfile.tsx`, `types.ts`) e deixar o `DashboardApp` só com a moldura e a navegação.
- **Pastas planas.** `app/` tem 154 `.tsx` e 79 `.css` na raiz. Pessoas está espalhada em `People*.tsx`, `Person*.tsx`, `Member*.tsx`, `lib/people-*.ts` e `lib/supabase/people-tools-routes.ts`. **Proposta:** agrupar por módulo (`app/pessoas/…`), de forma gradual, sem mudar o comportamento.
- **API:** as rotas `/api/people/*` são finas e delegam ao banco (RPCs com `security definer` e checagem própria). Esse padrão é bom e deve ser mantido.
- **Testes:** há testes de banco (pgTAP) e de tela (node) para pessoas, aniversariantes, ferramentas, resumo e gravação. A cobertura é boa.

## 5. Layout

A lista de Pessoas tem:

- cabeçalho com "Importar planilha" e "Nova pessoa";
- abas com contadores e filtros avançados;
- seleção em lote e exportação para Excel;
- aniversariantes, perfis pendentes do app e pedidos do app no topo.

Pontos a melhorar:

- **Topo da lista:** perfis pendentes, pedidos do app e aniversariantes aparecem empilhados antes da lista. Seria melhor uma faixa de "pendências" recolhível.
- **Cadastro:** são 4 etapas num modal grande. Seria melhor transformar a ficha em painel lateral com seções.
- **Visual:** precisa de uma verificação no celular após as mudanças de desempenho.

## 6. Integração com os apps

- **App da igreja:**
  - O cadastro e as alterações chegam como pedido (`member_self_service`), e a secretaria revisa em Pessoas › perfis pendentes.
  - A foto vai para a ficha (`member_photo`).
  - O rascunho fica no servidor (`member_profile_draft`).
  - A família e os termos estão ligados à ficha.
  - Não há duplicação: o app usa RPCs próprias e nenhuma das rotas antigas.
- **Vinha Equipe:**
  - Visitante por QR (`visitor_checkin` e `visitor_staff`), que cria e atualiza a pessoa;
  - Kids lê responsáveis e crianças pelas RPCs do Kids.
  - Não usa `/api/people`.
- **Remoção segura:** nenhuma das remoções propostas afeta os apps.

## 7. Segurança

| Nível | Achado                                                                                                                                                                                                           | Recomendação                                                                                                           |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Médio | **A lista expõe dados demais.** Quem tem só "ver pessoas" (inclusive por permissão concedida a voluntário) recebe na lista o CPF, o endereço, o contato de emergência e os termos de todas as pessoas da página. | Lista enxuta (nome, situação, grupo, contato e foto). A ficha completa só ao abrir a pessoa. Isso também resolve o L4. |
| Médio | **Cadastro de visitante sem captcha.** O QR público cria cadastros com limite de 200 a cada 10 minutos por igreja.                                                                                               | Captcha leve (Cloudflare Turnstile) ou limite menor por aparelho.                                                      |
| Baixo | **Senha vazada.** A proteção contra senhas vazadas (HaveIBeenPwned) está desligada no Supabase Auth.                                                                                                             | Ligar em Authentication › Policies.                                                                                    |
| Ok    | **Funções sem login.** As 8 abertas são intencionais: agenda pública, verificar termo, convite, imagem pública, suporte, fuso, página e cadastro de visitante.                                                   | Manter.                                                                                                                |
| Ok    | **Rotas de Pessoas.** Todas autorizam (`people.read`/`people.write`, ou permissão concedida) e o banco confere de novo. As notas pastorais só vão para dono e pastor.                                            | Manter.                                                                                                                |
| Info  | **Implantações com erro.** A branch `apk-teste` (só APKs) gera uma implantação com erro na Vercel a cada envio.                                                                                                  | Ignorar essa branch na Vercel (Ignored Build Step).                                                                    |

## 8. Plano proposto (em ordem)

1. **Região da Vercel em São Paulo (`gru1`)**, junto do banco e dos usuários.
   - Uma linha no `vercel.json`, fácil de reverter.
   - Maior ganho, e vale para todos os módulos.
2. **Total da Visão geral sem baixar 100 cadastros.** Carregar as pessoas só onde ainda forem necessárias.
3. **Contadores em uma chamada só**, com a contagem por situação feita no banco.
4. **Lista enxuta e ficha completa sob demanda.** Resolve desempenho e segurança.
5. **Retirar o código morto:**
   - os 14 componentes do `DashboardApp`;
   - `AccountingCenter.tsx`;
   - os imports sem uso;
   - a rota `/api/kids` antiga.
6. **Famílias e termos e Aplicativo do membro:** tirar do menu e redirecionar para os substitutos.
7. **Organização:** mover o cadastro e a ficha para `app/pessoas/`.
8. **Carregar cada módulo sob demanda** (`React.lazy`): o pacote inicial cai de cerca de 850 KB para a moldura mais o módulo aberto.
9. **Segurança:** captcha no visitante e proteção contra senha vazada.

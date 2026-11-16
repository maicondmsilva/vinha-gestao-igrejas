# Grupos, Cargos e Funções na Vinha — análise

Data: 16/11/2026 · Escopo: banco, painel, app da igreja, Vinha Equipe, permissões e mercado.

## 1. A pergunta

Na igreja há títulos e responsabilidades diferentes, que hoje se misturam:

- **Pastor(a), Presbítero, Diácono(isa), Evangelista, Missionário(a), Obreiro(a)**: o que a pessoa **é** na igreja, independente de onde serve.
- **Líder de Célula, Supervisor de Rede, Líder de Obreiros, Líder do Ministério de Louvor**: o que a pessoa **faz num grupo específico**. "Líder de Célula" não existe sozinho: é líder **da Célula Esperança**.
- **Guitarra, Recepção, Professor Kids**: a posição numa escala ou sala, que já existe nos módulos Escalas e Kids.

A recomendação é separar em três conceitos, como os melhores sistemas fazem, mas mostrar tudo junto no cadastro e no app.

| Conceito | Pergunta que responde | Exemplos | Onde vive |
|---|---|---|---|
| **Cargo** | O que a pessoa é na igreja? | Pastor(a), Presbítero, Diácono(isa), Obreiro(a), Missionário(a) | Na pessoa (pode ter mais de um, com data de consagração) |
| **Grupo** | De onde a pessoa participa? | Célula Esperança, Rede Jovens, Ministério de Louvor, Obreiros, Kids | Células, Redes, Ministérios/Departamentos |
| **Função no grupo** | O que ela faz naquele grupo? | Líder, Vice-líder, Líder em treinamento, Anfitrião, Supervisor, Integrante | No vínculo pessoa ↔ grupo |

Assim: **Supervisor de Rede** = função *Supervisor* no grupo *Rede Jovens*; **Líder de Obreiros** = função *Líder* no ministério *Obreiros*; **Pastor** = cargo. A Posição na escala (Guitarra, Bateria) continua no módulo Escalas, ligada ao ministério.

## 2. Como está hoje no sistema

| O que existe | Tabela | Problema |
|---|---|---|
| "Grupo / ministério" no cadastro | `people.group_name` (texto livre) | Escrito à mão: "Louvor", "louvor ", "Min. Louvor" viram três grupos; não liga a nada; filtros e relatórios ficam imprecisos. |
| Pastor | `people.is_pastor` (sim/não) | Só um cargo, sem os outros, sem data, sem histórico. |
| Células e participantes | `church_cells`, `church_cell_participants` | Bom. Líder em `leader_person_id` **e** `leader_name` (texto) — dois lugares. Sem vice-líder, anfitrião ou líder em treinamento. |
| Redes | `church_cell_networks` | Um supervisor só (`supervisor_person_id` + `supervisor_name`). Sem pastor de rede nem discipulador. |
| Ministérios e departamentos do app | `community_groups` + `community_participation` | O membro pede para participar no app; não há função (todos são "aprovados"); não liga às equipes de Escalas. |
| Equipes de escala | `scale_teams`, `scale_members`, `scale_roles` | `scale_roles` é posição (Guitarra), não liderança. O "Louvor" das Escalas não é o mesmo "Louvor" do app. |
| Equipe Kids | `kids_team` (supervisor, recepção, professor, auxiliar) | Já tem função própria; fica como está. |
| Grupos de avisos | `people_groups` | Listas para comunicação e modelos de usuário. Não são ministérios. |
| Marcadores | `people.tags` | Algumas igrejas usam como cargo improvisado. |
| Permissões | `permission_grants` (`group_kind`: cell, network, scale_team, kids_class) | Já limita acesso por grupo, mas é dado à mão; não acompanha quando a pessoa vira ou deixa de ser líder. Não há "ministério". |

Resumo: **seis cadastros de grupo separados** e nenhum lugar que responda "quais são as funções do Davi na igreja?".

## 3. Mercado

| Sistema | Como organiza | O que aproveitar |
|---|---|---|
| **Planning Center** (EUA, referência) | *Tipos de grupo* (Pequenos grupos, Ministério de mulheres…) → grupos → papéis: Administrador, Gerente do tipo de grupo, Líder do grupo, Membro. O líder só vê os grupos que lidera. | Tipo de grupo + função dentro do grupo + acesso que acompanha a função. |
| **ChurchTools** (Alemanha) | Tudo é *Grupo* de um *Tipo* (Pequeno grupo, Serviço, Característica, Ação); cada tipo tem *Funções* (Líder, Colaborador, Participante, Pedido); **as permissões são dadas pela função no tipo de grupo**, e a atribuição individual é exceção. Até "características" como "Batizado" viram grupo. | Permissão herdada da função — o modelo mais limpo para a Vinha. |
| **Elvanto** (Austrália) | *Departamento* → *Subdepartamento* → *Posição* (Ministérios criativos › Banda › Guitarra); "Reporta-se a" por posição. | Ministério com subequipes e posições, igual Louvor → Banda → Guitarra das Escalas. |
| **Sistemas brasileiros** (InChurch, Eklesia, Prover, Ecclesiato, Sige, sistemas de secretaria denominacionais) | Em geral: cadastro de ministérios/departamentos e células separado; o "cargo eclesiástico" é campo simples no membro; manuais de secretaria (ex.: Metodista) listam à parte quem ocupa cargo de liderança em cada ministério. | O mercado nacional trata cargo e liderança de forma solta. **Diferencial possível**: cargo com histórico + função por grupo + acesso automático. |

Conclusão de mercado: os líderes internacionais convergem para **grupo com tipo + função no grupo + permissão pela função**; o cargo eclesiástico (forte na realidade brasileira) quase nenhum trata bem. A Vinha pode unir os dois.

## 4. Proposta para a Vinha

### 4.1 Cargos (novo)
- Catálogo por igreja, já preenchido com sugestões e editável: Pastor(a) presidente, Pastor(a), Pastor(a) auxiliar, Presbítero, Diácono(isa), Evangelista, Missionário(a), Obreiro(a), Líder, Membro. Nome masculino/feminino ("Pastor"/"Pastora") pelo gênero da pessoa.
- Na pessoa: um ou mais cargos, com data de consagração e igreja (unidade). Ao encerrar, fica no histórico.
- `is_pastor` vira o cargo "Pastor(a)" (migração automática, sem perda).

### 4.2 Grupos (unificar a visão, não a operação)
Não convém fundir as tabelas de células, escalas e Kids — cada uma tem regras próprias e testes. A proposta é:
- **Ministérios e departamentos** (`community_groups`) passam a ser o cadastro oficial de ministério: Louvor, Obreiros, Intercessão, Recepção, Mídia, Kids…, com líder e funções.
- Cada **equipe de escala** pode ser ligada a um ministério (ex.: Ministério de Louvor → equipes "Banda" e "Vocal"). Quem é escalado no Louvor aparece como integrante do ministério.
- **Células e Redes** continuam como estão, ganhando funções.
- Uma **visão única por pessoa** junta tudo: células, redes, ministérios, equipes de escala e equipe Kids.

### 4.3 Funções no grupo (novo)
Catálogo por tipo de grupo, editável, com uma marca de "liderança":

| Tipo | Funções sugeridas |
|---|---|
| Célula | Líder ★, Vice-líder ★, Líder em treinamento, Anfitrião, Participante |
| Rede | Pastor(a) de rede ★, Supervisor(a) ★, Discipulador(a) |
| Ministério / departamento | Líder ★, Vice-líder ★, Coordenador(a), Integrante |
| Kids | (mantém Supervisor, Recepção, Professor, Auxiliar) |

★ = função de liderança (aparece no organograma e pode dar acesso).

### 4.4 Acesso que acompanha a função
- Cada função de liderança pode ter um **modelo de permissão** (os modelos de usuário já existem), sempre limitado ao próprio grupo: Líder de célula → relatórios e participantes **da sua célula**; Supervisor de rede → células **da sua rede**; Líder do Louvor → escalas e repertório **do Louvor**.
- Ao tornar alguém líder, o sistema propõe dar o acesso; ao tirar a função, o acesso sai junto. Acessos dados à mão continuam funcionando.
- Novo `group_kind` "ministry" em `permission_grants`.

### 4.5 No cadastro do membro (painel)
- "Grupo / ministério" deixa de ser texto livre: **busca com os grupos cadastrados**, separados por tipo (Células, Redes, Ministérios), com a função ao lado. Pode escolher mais de um.
- Nova seção **Cargos e funções**: chips do tipo "Pastora · desde 2015", "Líder — Célula Esperança", "Integrante — Louvor (Guitarra)".
- O texto antigo de `group_name` é convertido: quando bate com um grupo existente, vira vínculo; quando não bate, fica como observação e aparece numa lista "para conferir".
- Filtros novos em Pessoas: por cargo, por função de liderança e por ministério.

### 4.6 No app da igreja
- **Meu perfil**: "Minhas funções" (cargos e grupos) e a carteirinha com o cargo.
- **Liderança da igreja**: página com pastores e líderes por ministério e célula (só o que a igreja marcar como público), com botão de contato.
- As áreas de líder já existentes (painel do líder de célula, agenda de atendimento, equipe Kids) passam a ser liberadas pela função, sem configuração à parte.
- Pedidos para participar de ministério continuam; o líder do ministério aprova pelo app.

### 4.7 Relatórios
Organograma (Pastores → Redes → Supervisores → Células → Líderes), número de líderes por rede, células sem vice-líder, ministérios sem líder, histórico de cargos.

## 5. Impacto por módulo

| Módulo | Impacto | Risco |
|---|---|---|
| Pessoas | Campo de grupo vira busca; nova seção de cargos e funções; filtros; importação de planilha aceita cargo e grupo pelo nome. | Médio: conversão do texto antigo — feita com lista de conferência, sem apagar nada. |
| Células | Funções no participante; `leader_person_id` passa a vir da função Líder (o `leader_name` texto vira só exibição). | Médio: o painel do líder no app usa `leader_person_id`; manter compatível na transição. |
| Redes | Mais de um supervisor/pastor por rede. | Baixo. |
| Escalas | Equipe ligada a ministério; líder do ministério enxerga as escalas dele. | Baixo. |
| Louvor | Repertório liberado ao líder do ministério. | Baixo. |
| Kids | Sem mudança nas funções; a equipe Kids aparece nas funções da pessoa. | Baixo. |
| Comunicação | Avisos e push para "todos os líderes", "líderes de célula", "integrantes do Louvor", "Obreiros". | Baixo — amplia os públicos salvos. |
| Usuários e permissões | Modelo por função e escopo "ministério". | **Alto**: mexe em acesso. Exige testes de banco para conceder e retirar e nunca ampliar fora do grupo. |
| App da igreja / Vinha Equipe | Telas de perfil, liderança e liberação por função. | Médio: novo APK. |
| Relatórios | Organograma e indicadores de liderança. | Baixo. |
| Portal da Vinha | Nova seção "Grupos, cargos e funções". | — |

## 6. Plano em fases

1. **F1 — Cargos**: catálogo, cargos na pessoa, migrar `is_pastor`, cadastro e ficha, filtro. *(pequeno)*
2. **F2 — Ministérios e funções**: catálogo de funções, função em células/redes/ministérios, ligação equipe de escala ↔ ministério, visão única por pessoa. *(médio)*
3. **F3 — Cadastro com busca de grupos**: troca do texto livre, conversão de `group_name` com lista de conferência, importação. *(médio)*
4. **F4 — App**: Minhas funções, carteirinha com cargo, página Liderança, liberação por função. *(médio, novo APK)*
5. **F5 — Acesso pela função**: modelo por função, concessão e retirada automáticas, escopo ministério. *(médio, alto cuidado)*
6. **F6 — Relatórios e públicos de comunicação**. *(pequeno)*

## 7. Decisões a tomar

1. Uma pessoa pode ter **vários cargos** ao mesmo tempo (ex.: Pastora e Missionária)? *Sugestão: sim.*
2. O acesso pela função deve ser **automático** ou **proposto para aprovação**? *Sugestão: proposto, com um clique para confirmar.*
3. A página **Liderança** no app mostra telefone dos líderes? *Sugestão: só botão de mensagem; telefone se o líder autorizar.*
4. O nome "Cargo" serve para todas as igrejas ou cada uma escolhe (Cargo, Título, Ofício)? *Sugestão: usar a linguagem ministerial já existente (`ministry_language`).*

## Fontes de mercado

- Planning Center — [Introdução para administradores](https://help.planningcenter.com/en/138441-introduction-for-administrators.html), [Tipos de grupo](https://help.planningcenter.com/en/create-and-manage-group-types.html), [Permissões em Groups](https://help.planningcenter.com/en/permissions-in-groups.html)
- ChurchTools — [Grupos](https://church.tools/en/groups/), [Mudanças no módulo de grupos (fórum)](https://forum.church.tools/topic/9158/gruppenmodul-änderungen-am-22-02-2023/9), [Tipos de grupo (fórum)](https://forum.church.tools/post/26817)
- Elvanto — [Departamentos](https://help.elvanto.com/hc/en-us/articles/7482088553751), [Configurar departamento](https://help.elvanto.com/hc/en-us/articles/7625190507415)
- Brasil — [InPeace](https://www.b2bstack.com.br/product/inpeace), [Portal Eklesia](https://apps.apple.com/app/id1122843862), [Prover](https://gazetadopovo.com.br/conteudo-publicitario/sistema-prover/gestao-de-igrejas/), [Ecclesiato](https://www.tabnews.com.br/viniciusw/resolvi-uma-dor-da-minha-igreja-e-isso-virou-um-sistema), [Sige Igrejas](https://www.capterra.com/p/10043068/Sige-Igrejas/), [Manual de secretaria Metodista](https://4re.metodista.org.br/wp-content/uploads/2018/04/Secretaria_-_GI.pdf)

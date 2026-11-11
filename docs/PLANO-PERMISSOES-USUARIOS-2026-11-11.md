# Plano de permissões e usuários · Vinha

Data: 11/11/2026. Referência visual: telas de Usuários e Permissões da InChurch enviadas pelo dono do produto.

## 1. Como funciona hoje

| Peça | Onde está | O que faz |
|---|---|---|
| Papel fixo da pessoa na organização | `organization_memberships.role` (enum `membership_role`) | 8 papéis: `owner`, `pastor`, `admin`, `secretary`, `finance`, `leader`, `member`, `viewer`. |
| Abrangência por igreja | `membership_unit_access` (`read` / `manage` / `admin` + `include_children`) | Limita a pessoa a uma igreja e, opcionalmente, às filhas. Equivale à "Abrangência" (Igreja / Regional / Denominação) da InChurch. |
| Módulo contratado | `private.target_unit_module_enabled` | Bloqueia o módulo quando a igreja não tem o plano. |
| Acessos avulsos de equipe | `private.staff_grants` (`agenda`, `checkin`, `publishing`, `push`) | Libera 4 tarefas específicas para quem não é administrador. |
| Acesso por equipe de escala | `private.scale_grants.capabilities` | Capacidades por equipe de escala. |
| Acesso por rede de células | `private.cell_supervisor_grants` | Supervisor enxerga uma rede. |
| Vínculo usuário do app ↔ membro | `people.auth_user_id` | Liga a conta de login ao cadastro do membro. |

### Problemas encontrados

1. **Regras espalhadas e fixas no banco.** Há cerca de 120 verificações de papel espalhadas pelas funções, com 17 combinações diferentes. Exemplos: `owner/admin/pastor` (36 vezes), `owner/admin` (26), `owner/admin/pastor/leader` (11) e `owner/admin/finance` no financeiro. Mudar "quem pode o quê" exige uma migração.
2. **Sem granularidade por ação.** Não dá para liberar "ver relatórios financeiros, sem lançar" nem "lançar, sem excluir".
3. **Três mecanismos diferentes de acesso avulso** (`staff_grants`, `scale_grants` e `cell_supervisor_grants`), com telas e regras próprias.
4. **Nomes inconsistentes nas telas.** Exemplo: `leader` aparece como "Líder Kids" na Central de Segurança.
5. **Sem um lugar único** para ver tudo o que uma pessoa pode fazer, e sem um ponto único de auditoria.

## 2. Proposta

### 2.1 Tipo de usuário (perfil base)

Igual à InChurch, o tipo define se a pessoa recebe permissões de gestão:

| Tipo de usuário | Para quem | Permissões de gestão |
|---|---|---|
| **Usuário do app** | Membro que se cadastrou no aplicativo | Nenhuma: só o próprio perfil e o que o app oferece ao membro |
| **Membro de equipe** | Líder de célula, equipe de escala, recepção, Kids | Só as seções liberadas, limitadas a grupos (células, redes, equipes) |
| **Administrador local** | Gestão de uma igreja/campus | Seções liberadas na própria igreja |
| **Administrador regional** | Gestão de uma regional e das igrejas abaixo | Seções liberadas na regional e filhas |
| **Administrador do ministério** | Gestão de toda a organização | Seções liberadas em todas as igrejas |

O **dono** (`owner`) continua protegido: não pode ser rebaixado sem outro dono ativo (regra que já existe).

### 2.2 Matriz de permissões (como na tela da InChurch)

Para cada **seção do sistema**, quatro colunas:

1. **Seção:** liga ou desliga o acesso.
2. **Abrangência:** Igreja, Regional (inclui filhas) ou Ministério. Reaproveita a árvore de igrejas e o `include_children`.
3. **Limitar a grupos (opcional):** células, redes, equipes de escala ou turmas Kids. Unifica os três mecanismos avulsos de hoje.
4. **Autorizado a:** ver · criar · editar · excluir, mais ações especiais quando a seção tiver (aprovar, exportar, conciliar, fechar mês).

Seções iniciais, agrupadas como no menu:

- **Pessoas:** Membros, Visitantes, Perfis pendentes (aprovar), Usuários e permissões, Importação
- **Igreja:** Igrejas/Filiais, Configurações, Identidade visual
- **Células (GV):** Células, Redes, Relatórios de célula, Transferências
- **Programação:** Agenda, Eventos, Inscrições e check-in, Ingressos
- **Comunicação:** Avisos, Push, Banners, Transmissões, Chat (moderação)
- **Escalas:** Equipes, Escalas, Substituições
- **Kids:** Turmas, Check-in/out, Ocorrências
- **Financeiro:** Lançamentos, Contas a receber/pagar, Conciliação, Fechamento mensal, Relatórios, Recebimentos digitais, Cadastros (contas, categorias, centros, fornecedores)
- **Conteúdo e Ensino:** Mídias, Trilhas/cursos

### 2.3 Modelos prontos (atalhos)

O tipo de usuário vem com modelos que preenchem a matriz e depois podem ser ajustados: **Pastor**, **Secretaria**, **Tesouraria**, **Líder de célula**, **Supervisor de rede**, **Líder de escala**, **Líder Kids** e **Comunicação**. Cada papel atual vira um modelo com exatamente o acesso de hoje, então ninguém ganha nem perde acesso na migração.

### 2.4 Estrutura no banco

- `private.permission_catalog`: código da seção (por exemplo `finance.entries`), módulo, nome, ações aceitas e se aceita "limitar a grupos". O catálogo é a fonte única de verdade.
- `private.user_permissions`: vínculo da pessoa com a organização, seção, igreja de abrangência e `include_children`, ações, tipo de limite e grupos.
- `private.permission_templates`: os modelos.
- **Função única** `private.can(org, unidade, seção, ação [, grupo])`, usada por todos os módulos. Ela confere, nesta ordem: sessão válida → organização ativa → módulo contratado → abrangência → permissão da seção e ação → grupo, quando houver.
- **Auditoria:** toda mudança de tipo, permissão ou modelo vai para `audit_logs`, com quem mudou e o antes/depois.
- **Regra de segurança:** ninguém concede o que não tem. Só o dono e o Administrador do ministério mexem em "Usuários e permissões".

### 2.5 Tela "Pessoas › Usuários"

- Lista de usuários com filtros: tipo, igreja, "sem vínculo com membro".
- Ficha do usuário (inspirada na InChurch): dados básicos, **Tipo de usuário**, membro vinculado e, quando o tipo não for "Usuário do app", a **matriz de permissões** com "Selecionar tudo | Limpar" e "Aplicar modelo".
- Um resumo em texto do que a pessoa pode fazer ("Pode ver e lançar no Financeiro da Igreja Sede; não pode excluir").

### 2.6 Cadastro pelo app e vínculo com o membro

Fluxo: o membro se cadastra no app → aparece em **Perfis pendentes** → ao ser aprovado, o usuário é ligado ao cadastro de membro.

- **Ligação automática:** só quando **e-mail e CPF** batem com **um único** membro da organização.
- **Revisão manual:** quando só um dos dois bate, ou quando há mais de um candidato. A tela mostra os candidatos lado a lado.
- **Membro novo:** sem candidato, a aprovação cria o cadastro de membro (com o tipo Membro, Frequentador ou Visitante, como na InChurch) e já faz a ligação.
- **Registro:** a ligação fica no histórico do membro e na auditoria.

## 3. Fases

| Fase | Entrega | Risco |
|---|---|---|
| P1 | Catálogo, tabelas, função `can()` e modelos iguais aos papéis atuais. `can()` responde "papel atual **ou** permissão explícita" | Nenhuma mudança de comportamento |
| P2 | Tela Pessoas › Usuários: tipo de usuário, matriz, modelos e auditoria | Só tela nova |
| P3 | Módulos passam a usar `can()`, um por vez, começando pelo **Financeiro** (inclui as permissões "excluir lançamento" e "relatórios por célula") | Por módulo, com testes de banco |
| P4 | "Limitar a grupos" unificado (células, redes, equipes, turmas) substitui os 3 mecanismos avulsos | Migração dos acessos atuais |
| P5 | Vínculo app ↔ membro por e-mail + CPF na aprovação de perfis | Revisão manual nos casos duvidosos |

## 4. Regra permanente para novos desenvolvimentos

Toda funcionalidade nova responde, antes de ser construída:

1. Precisa de permissão nova ou cabe numa seção existente?
2. Quais ações (ver, criar, editar, excluir, aprovar, exportar)?
3. Aceita abrangência regional e "limitar a grupos"?
4. Quais modelos recebem a permissão por padrão?
5. Há teste de banco provando que quem não tem a permissão é recusado?

Essas perguntas entram no modelo de PR (seção "Permissões") e no documento de arquitetura. Uma ação sensível não pode ser publicada sem a permissão declarada no catálogo.

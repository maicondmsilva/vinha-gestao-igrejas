# Agenda de atendimento, relatório e acompanhamento — análise

Data: 16/11/2026 · Escopo: banco, painel, app da igreja, Vinha Equipe, permissões e impactos. Nada foi alterado ainda; o vídeo do Portal fica como está.

## 1. Como funciona hoje

| Peça | Onde | Situação atual |
|---|---|---|
| Atendentes | `pastoral_attendants` | Pessoa, rótulo (Pastor, Líder…), durações, tipos (conversa, aconselhamento, oração, visita), modos, confirmação automática. |
| Disponibilidade | `pastoral_hours`, `pastoral_dates`, `pastoral_blocks` | Semana padrão, horários de uma data específica e bloqueios (férias, viagem). |
| Pedido do membro | `pastoral_member` (app › Falar com a liderança) | Respeita os horários: só horários livres, **24 h de antecedência**, no máximo **2 pedidos em aberto**, cancelamento até **12 h** antes. |
| Agendamento pelo atendente | `pastoral_staff` › `schedule` | Cria o atendimento já confirmado e o membro só marca "Ciente". |
| Quem o atendente pode agendar | mesma função | Com permissão de agenda ou marcado como pastor: qualquer pessoa. Os demais: só participantes da própria célula. |
| Anotação | `pastoral_appointments.notes` | Um texto livre de até 4.000 caracteres, visto pelo próprio atendente e por quem tem a permissão "Notas pastorais". |
| Avisos ao membro | caixa de notificações do app | Confirmações e recusas aparecem na caixa do app. **Não há notificação no celular (push).** |
| Novos convertidos | `people.converted_at` e `followup_*` | Data da decisão, acompanhante, situação (pendente, contatado, em célula, integrado, encerrado) e uma nota curta. |

## 2. Problemas encontrados

1. **O atendente agenda fora dos horários.** O agendamento feito pelo atendente ou pela secretaria só evita choque com outro atendimento. Ele **não confere** a semana padrão, as datas específicas nem os bloqueios: dá para marcar às 23 h ou no meio das férias.
2. **Conflito entre papéis.** Um líder que também é atendente pode ter um atendimento com o pastor (como pessoa atendida) e outro com um membro (como atendente) no mesmo horário. O sistema só confere a agenda dele como atendente.
3. **Sem controle de público.** Todo atendente ativo aparece para todos os membros em "Falar com a liderança". Não dá para dizer "o Pastor atende só líderes" ou "o líder atende só a sua célula".
4. **Limites fixos.** 24 h de antecedência, 2 pedidos em aberto e cancelamento até 12 h valem para todos. Não há limite de atendimentos por dia nem intervalo entre um atendimento e outro.
5. **O membro não aceita de fato.** Quando o atendente agenda, o membro só marca "Ciente": não pode recusar nem pedir outro horário, e não recebe notificação no celular nem lembrete.
6. **O relatório é um texto solto.** Não tem assunto, encaminhamento, próximo passo nem nível de sigilo, e não forma um histórico na ficha da pessoa.
7. **A privacidade é tudo ou nada.** Quem tem "Notas pastorais" lê as anotações de todos os atendentes.
8. **"Novos convertidos" mistura duas coisas.** A etapa (visitante, em integração, membro) e a fé (nunca se decidiu, decidiu-se aqui, já convertido em outra igreja). Um visitante evangélico de longa data entra errado, e um visitante que nunca se decidiu fica fora do acompanhamento.
9. **Sem calendário.** O atendente vê listas, não a semana dele, e os acompanhamentos não aparecem junto dos atendimentos.

## 3. Proposta

### 3.1 Respeitar os horários
- Todo agendamento confere a semana padrão, as datas específicas e os bloqueios, inclusive quando quem agenda é o atendente ou a secretaria.
- Para atender fora do padrão, o atendente **abre o horário daquela data** (já existe em "datas específicas") e então agenda. Fica registrado.
- Conferência de choque pelos **dois papéis**: o horário fica ocupado se a pessoa já é atendente ou atendida naquele momento.
- Limites por atendente, com os valores atuais como padrão:
  - antecedência mínima;
  - pedidos em aberto por membro;
  - prazo de cancelamento;
  - **máximo de atendimentos por dia**;
  - **intervalo entre atendimentos** (ex.: 15 min).

### 3.2 Quem pode pedir
Cada atendente escolhe o público que o vê em "Falar com a liderança":
- **Todos os membros**;
- **Só líderes** (líderes de célula, supervisores de rede e, quando existir, quem tiver função de liderança — ver a análise de Grupos, Cargos e Funções);
- **Só a minha célula ou rede**;
- **Só por convite**: não aparece no app; só o próprio atendente agenda.

Exemplo: o Pastor fica com "Só líderes". Os membros não o veem e são atendidos pelos líderes, mas ele continua podendo agendar qualquer pessoa.

### 3.3 Agendamento pelo atendente com aceite do membro
1. O atendente escolhe a pessoa, o tipo e um **horário livre da própria agenda**.
2. O atendimento nasce como **"Aguardando aceite"** e ocupa o horário.
3. O membro recebe **notificação no celular** e o aviso na caixa do app, com três botões: **Aceitar**, **Recusar** ou **Pedir outro horário** (com mensagem).
4. Ao aceitar, vira "Confirmado" e o atendente é avisado. Ao recusar, o horário é liberado.
5. Lembretes ao membro e ao atendente 24 h e 1 h antes.
6. Sem resposta até X horas antes (configurável), o horário é liberado e o atendente é avisado.
7. Quem não tem o app recebe o convite pelo atendente via WhatsApp, com o botão já pronto, e o atendente marca o aceite.

### 3.4 Relatório de atendimento
Depois do atendimento, ao marcar "Realizado", o atendente preenche o relatório (no app ou no painel):

| Campo | Observação |
|---|---|
| Resumo | Texto. |
| Assuntos | Vida espiritual, família, casamento, finanças, luto, saúde, trabalho, ministério, outro (vários). |
| Pedidos de oração | Opcional; pode ir para a intercessão só se o membro autorizar. |
| Encaminhamentos | Célula, curso/discipulado, outro atendente, ajuda profissional. |
| Próximo passo | Data de retorno; cria o próximo agendamento já com o convite. |
| Sigilo | **Equipe pastoral**, **Restrito** ou **Sigiloso** (ver 3.5). |

- O relatório fica numa tabela própria (separada do agendamento) e entra no **Histórico de atendimento** da ficha da pessoa, junto com os registros de acompanhamento.
- Pode ser editado por 7 dias. Depois disso fica travado e só aceita **complemento**, com data.
- **Toda leitura fica registrada** (quem leu e quando).
- O membro nunca vê o relatório: vê só que teve um atendimento, a data e o tipo.
- O relatório fica fora da exportação em Excel e de qualquer relatório geral.

### 3.5 Privacidade pela permissão de usuário
Nova permissão **Relatórios de atendimento** em Configurações › Usuários e permissões, com níveis e limitada por igreja e por grupo, como as demais:

| Nível | O que vê |
|---|---|
| Ver histórico | Data, tipo e atendente; sem conteúdo. |
| Ler relatórios | Conteúdo dos relatórios "Equipe pastoral". |
| Ler restritos | Também os "Restritos". |
| (ninguém) | "Sigiloso": só o autor. |

- O autor sempre lê os próprios relatórios.
- Pode ser limitada a uma rede ou célula: o supervisor da rede lê os relatórios das pessoas da rede dele, se tiver a permissão.
- A permissão atual "Notas pastorais" passa a usar essa regra. As anotações antigas viram relatórios "Restrito", para não abrir nada que hoje é fechado.

### 3.6 Acompanhamento (no lugar de "Novos convertidos")
Você está certo: ser visitante e ter fé são coisas diferentes.
- **Nome sugerido: "Acompanhamento"** (alternativas: "Integração" ou "Cuidado").
- **Novo campo no cadastro: "Decisão de fé"**:
  - Ainda não se decidiu;
  - Decidiu-se nesta igreja (data);
  - Reconciliação (data);
  - Já convertido(a), vem de outra igreja (qual);
  - Não informado.
- A **etapa** (Visitante, Em integração, Membro, Criança) continua separada.
- **Quem entra no acompanhamento**: qualquer pessoa que a secretaria ou o QR de visitantes marcar, convertida ou não. Filtros por decisão de fé permitem tratar cada caso: o evangélico de outra igreja vai para integração e célula; quem nunca se decidiu recebe o cuidado evangelístico.
- **Registrar contato**: tipo (ligação, mensagem, visita, encontro), resumo, próximo passo com data, e o mesmo sigilo do relatório. Entra no mesmo Histórico de atendimento.
- A situação continua (a contatar, contatado, em célula, integrado, encerrado).
- Indicadores:
  - decisões no mês;
  - visitantes já convertidos;
  - tempo até o primeiro contato;
  - pessoas sem contato há mais de 7 dias.
- O acompanhante é notificado no app quando é escolhido. Tem a área **Meus acompanhamentos** (a proposta da conversa anterior), dentro da agenda.

### 3.7 Calendário do atendente
Uma visão **Dia, Semana ou Mês**, no app e no painel, com cores:

| Cor | O quê |
|---|---|
| Verde | Atendimento confirmado |
| Dourado | Aguardando aceite ou pedido para decidir |
| Azul | Próximo contato de acompanhamento (visitante ou convertido) |
| Cinza | Bloqueios e horário fora da disponibilidade |
| Vermelho | Relatório pendente (realizado e sem relatório) |

- Cada usuário vê **só a própria agenda**.
- Quem tem a permissão de agenda vê os atendentes da igreja, com filtro, mas o conteúdo dos relatórios continua seguindo a seção 3.5.
- Tocar num horário livre agenda; tocar num atendimento abre o detalhe, aceite, "Realizado" e relatório.
- No topo: "Hoje: 3 atendimentos · 2 contatos · 1 relatório pendente".
- Assinatura opcional para Google/Apple Calendar (o sistema já gera calendário em ICS na Programação) **só com horário e "Atendimento"**, sem o nome da pessoa, por privacidade.

## 4. Impacto nos módulos e aplicativos

| Onde | O que muda | Risco |
|---|---|---|
| **Banco** | Conferência de horários no agendamento da equipe; choque pelos dois papéis; limites e público por atendente; situação "Aguardando aceite" e ações do membro (aceitar, recusar, outro horário); tabelas de relatório, de leituras e de contatos de acompanhamento; `people.faith_decision` e igreja anterior; novas permissões no catálogo. | Médio. A situação nova exige cuidado com os atendimentos já existentes (continuam válidos). |
| **Painel › Pessoas › Agenda pastoral** | Vira calendário; configuração de público e limites do atendente; relatório. | Médio |
| **Painel › Pessoas › Novos convertidos** | Renomeado para **Acompanhamento**; filtros por decisão de fé; registro de contato; indicadores. | Baixo |
| **Painel › Ficha e cadastro** | Campo "Decisão de fé"; seção **Histórico de atendimento** (respeita a permissão); a ficha mostra "relatório restrito" sem conteúdo para quem não pode ler. | Baixo |
| **Configurações › Usuários e permissões** | Nova permissão "Relatórios de atendimento" com níveis e limite por grupo; "Notas pastorais" migrada. | **Alto**: é privacidade. Testes de banco para cada nível e escopo. |
| **Relatórios** | Atendimentos por período, atendente, tipo e assunto, **só números**. | Baixo |
| **Células** | Encaminhamento para célula; "em célula" no acompanhamento confere a participação real; líder de célula com público "minha célula". | Baixo |
| **Comunicação / push** | Novos avisos: convite de atendimento, aceite, recusa, lembretes, acompanhamento atribuído, contato atrasado. Entram nas preferências de notificação do membro. | Baixo |
| **App da igreja — membro** | "Falar com a liderança" mostra só atendentes cujo público inclui a pessoa; convite com Aceitar, Recusar ou Outro horário; lembretes. | Médio (novo APK) |
| **App da igreja — atendente** | "Minha agenda de atendimento" vira calendário; relatório; agendar com aceite; Meus acompanhamentos. | Médio (novo APK) |
| **Vinha Equipe** | QR e cadastro rápido de visitante perguntam "Já é convertido? De qual igreja?" e se deseja ser acompanhado. | Baixo |
| **Grupos, Cargos e Funções** | O público "Só líderes" usa hoje líder de célula, supervisor de rede e pastor; quando as funções existirem, passa a usá-las. "Pastor" sai do sim/não e vira cargo. | Baixo (compatível) |
| **Kids, Financeiro, Escalas, Louvor** | Sem impacto. | — |
| **Portal da Vinha** | Texto de Pessoas (Agenda pastoral, Acompanhamento) atualizado; o **vídeo não é alterado agora**. | — |
| **LGPD** | Relatórios de atendimento são dado sensível (convicção religiosa, saúde, família). Acesso por necessidade, registro de leitura, fora de exportações e retenção definida. O termo de dados pessoais ganha um parágrafo sobre o atendimento pastoral. | Médio |

## 5. Fases sugeridas

1. **A — Regras da agenda**: horários respeitados em todo agendamento, choque pelos dois papéis, limites e público por atendente. *(pequeno, corrige o problema mais urgente)*
2. **B — Convite com aceite**: Aguardando aceite, Aceitar/Recusar/Outro horário no app, push e lembretes. *(médio, novo APK)*
3. **C — Relatório e privacidade**: tabela de relatórios, sigilo, permissão nova em Usuários, Histórico de atendimento na ficha, migração das anotações. *(médio, alto cuidado)*
4. **D — Acompanhamento**: renomear, decisão de fé, registro de contato, Meus acompanhamentos no app, notificação ao acompanhante. *(médio)*
5. **E — Calendário**: Dia/Semana/Mês no app e no painel, com atendimentos, acompanhamentos e pendências. *(médio)*
6. **F — Indicadores e Portal**: relatórios numéricos e atualização do texto do Portal (vídeo depois). *(pequeno)*

## 6. Decisões a tomar

1. Nome da área: **Acompanhamento**, Integração ou Cuidado?
2. Sem resposta do membro ao convite, o horário é liberado quanto tempo antes? *Sugestão: 12 h.*
3. O relatório "Sigiloso" deve existir (só o autor lê, nem o pastor titular)? *Sugestão: sim.*
4. Prazo para editar o relatório antes de travar: *sugestão 7 dias.*
5. O Pastor titular lê automaticamente os relatórios "Restritos" de toda a igreja, ou só com a permissão? *Sugestão: só com a permissão (fica explícito em Usuários).*

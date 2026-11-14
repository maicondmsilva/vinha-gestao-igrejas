# Agenda pastoral e de liderança: análise e proposta (14/11/2026)

## 1. O que a Vinha já tem e serve de base

| Peça | Onde está | Como ajuda |
|---|---|---|
| Pastor marcado no cadastro | `people.is_pastor` | Define quem aparece como "pastor" para o membro escolher |
| Responsável pelo acompanhamento | `people.followup_person`, `followup_status`, `followup_note` (Pessoas › Novos convertidos) | O atendimento pode nascer de um acompanhamento e voltar para ele |
| Líder de célula | `church_cells.leader_person_id` | O membro vê primeiro o líder da sua célula; o líder marca visitas aos participantes |
| Visitas de célula | `church_cell_visits` | Hoje só registra quem visitou a célula; não é agenda |
| Permissões por módulo e por igreja | `private.can_in(...)`, Usuários e permissões | Novo módulo "Agenda pastoral" com as mesmas regras |
| Caixa de notificações do app | `member_inbox` | Avisos de pedido recebido, confirmado e remarcado, mesmo sem push |
| Exportação de agenda (ICS) | `shared/ics.ts` | O pastor assina a própria agenda no Google Agenda ou no iPhone |
| Fuso de cada igreja | `shared/timezone.ts` | Horários sempre no fuso da igreja local |

**Não existe hoje:** horários de atendimento, pedido de horário, confirmação, remarcação, bloqueio de dias, registro do atendimento nem visita pastoral marcada.

## 2. Como vai funcionar

### Quem atende ("Quem atende" no painel)
- A igreja escolhe no painel quem recebe pedidos: pastores, líderes, secretaria (atendimento geral) ou ministérios (ex.: aconselhamento de casais).
- Para cada pessoa que atende:
  - **tipos de atendimento:** conversa pastoral, aconselhamento, oração, visita em casa, conversa com o líder e outros que a igreja criar, cada um com duração (30, 45 ou 60 min);
  - **modalidade:** presencial na igreja, visita em casa ou online (link enviado na confirmação);
  - **horários da semana:** ex.: terça 14h–18h e quinta 19h–21h, com intervalo entre atendimentos;
  - **bloqueios:** férias, viagens e dias de culto especial;
  - **antecedência mínima e prazo máximo:** ex.: no mínimo 24 h e até 30 dias à frente;
  - **confirmação:** automática ou manual. No modo manual, o pedido fica "aguardando confirmação".

### Membro pede um horário (app)
1. **"Falar com o pastor"** no Início e no Menu.
2. **Escolhe com quem.** O líder da sua célula e o pastor da sua igreja aparecem primeiro, com foto e função.
3. **Escolhe o motivo.** O tipo de atendimento e uma mensagem opcional, privada e curta.
4. **Escolhe o dia num calendário.** Os dias com horário livre ficam marcados; ao tocar no dia aparecem os horários.
5. **Confirma.** O pedido aparece em "Meus horários", com a situação: aguardando, confirmado, remarcado, realizado ou cancelado.
6. Pode **cancelar** até o prazo definido pela igreja; depois, só falando com a secretaria.

### Pastor, líder ou secretaria marcam com o membro (painel e app da equipe)
- **"Marcar visita"** ou **"Marcar atendimento":** escolhe o membro (busca em Pessoas), o tipo, o dia e o horário livre de quem vai atender. O endereço do cadastro vem preenchido para visitas.
- A **secretaria** pode marcar em nome do pastor, se tiver permissão.
- O membro recebe o aviso no app e pode **confirmar presença** ou pedir outro horário.
- **Agenda do dia e da semana** para quem atende: pedidos para confirmar, próximos atendimentos e botões "Realizado", "Não compareceu" e "Remarcar".
- **Registro do atendimento:** anotação **sigilosa**, vista só por quem atendeu e por quem tiver a permissão "anotações pastorais". O registro pode voltar para o acompanhamento da pessoa (Novos convertidos).

### Telas (identidade Vinha)
- **App do membro:** capa na cor da igreja ("Um tempo para conversar"), cartões de quem atende, calendário do mês com bolinhas nos dias livres, horários em pílulas e um cartão de confirmação com bloco de data.
- **Painel:** novo item **Pessoas › Agenda pastoral**, com:
  - quadro da semana, uma coluna por pessoa que atende;
  - lista "Aguardando confirmação";
  - "Quem atende", com horários e bloqueios;
  - "Tipos de atendimento".
- **App (líder ou pastor):** cartão "Minha agenda de atendimento" no Menu, como fizemos em "Minha célula".

## 3. Regras e cuidados

- **Sem horário duplicado:** o banco recusa dois atendimentos sobrepostos para a mesma pessoa (restrição de intervalo), mesmo com dois pedidos ao mesmo tempo.
- **Privacidade (LGPD):** motivo e anotações podem envolver dados sensíveis (fé, saúde, família).
  - Mensagem curta e opcional;
  - anotações visíveis só para quem atendeu e quem tem a permissão específica;
  - nada disso vai para relatórios gerais nem para o push (o push diz só "Seu horário foi confirmado");
  - registro de quem viu e alterou;
  - prazo de guarda definido pela igreja.
- **Visita em casa:** o endereço só aparece para quem vai visitar e só no dia agendado. O membro precisa aceitar a visita, quando ela foi marcada pela equipe.
- **Fuso e feriados:** horários no fuso da igreja; bloqueios cobrem feriados e eventos.
- **Limite de pedidos:** ex.: no máximo 2 pedidos em aberto por membro, para evitar excesso.
- **Lembretes:** primeiro pela caixa de notificações do app; quando o Firebase estiver ativo, push na véspera e 1 hora antes.

## 4. Permissões novas

| Chave | Quem recebe | Permite |
|---|---|---|
| `pastoral.agenda` (ver) | Secretaria, pastores | Ver a agenda de quem atende na igreja |
| `pastoral.agenda` (editar) | Secretaria | Marcar, remarcar e cancelar em nome de quem atende |
| `pastoral.settings` | Administração | Cadastrar quem atende, tipos, horários e bloqueios |
| `pastoral.notes` | Pastor titular | Ler anotações sigilosas de outros atendentes |

Quem atende sempre vê e organiza a **própria** agenda, sem precisar de outra permissão. O líder de célula só pode marcar visitas com participantes da sua célula.

## 5. Plano de desenvolvimento

| Fase | Entrega | Onde |
|---|---|---|
| P1 | Banco: quem atende, tipos, horários, bloqueios, atendimentos (sem sobreposição), permissões e testes | Supabase |
| P2 | Painel: Pessoas › Agenda pastoral (quadro da semana, confirmar, marcar com membro, configurar horários) | Web |
| P3 | App do membro: "Falar com o pastor", calendário de dias livres, meus horários, cancelar | App |
| P4 | App de quem atende: minha agenda, confirmar, marcar visita, realizado ou não compareceu, anotação sigilosa | App |
| P5 | Assinar a agenda (ICS) e lembretes (caixa do app; push quando o Firebase estiver ativo) | Web e app |

**Decisões que posso assumir se não houver objeção:**
- confirmação manual como padrão;
- antecedência mínima de 24 h;
- cancelamento pelo membro até 12 h antes;
- até 2 pedidos em aberto por membro;
- duração padrão de 45 min.

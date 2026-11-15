# Kids simplificado — desenho (aprovado em 16/11/2026)

## Por quê
O Kids ficou confuso: sessão avulsa, repetição e equipe ficam em lugares diferentes, e o painel tem 12 páginas.
O objetivo é que qualquer coordenador entenda em um minuto: **Sala, Turma e Sessão**.

## Objetivos
- **Sessão única:** nome, horário, *Repetir* (não repete, com a data, ou os dias da semana) e salas (sala + turma + responsáveis).
  Ao salvar, as próximas sessões nascem sozinhas, já com a equipe.
- **Painel Kids em 4 abas:** Hoje · Crianças · Configurar (Salas, Turmas, Sessões) · Relatórios.
  Telão, estações, materiais e ocorrências ficam dentro delas.
- **Vinha Equipe:** Recepção | Salas | Configurar, com o mesmo formulário de sessão.
- **App da igreja:** o cadastro da criança fica como está (aprovado).
  O responsável pode **adicionar outro responsável fixo** (sem validade, fica "a conferir" pela secretaria) ou temporário (1 a 30 dias).
- **Cadastro não conferido não bloqueia a entrada**; a recepção vê o selo "a conferir".
- **Holyrics:** sem mudança.

## Não objetivos
- Mudar regras de check-in e check-out, QR e comprovante.
- Mudar o telão.
- Mudar o cadastro da criança no app.

## Abordagem
Reaproveitar `kids_session_series` como a "Sessão":
- *não repete* = regra semanal com `valid_from = valid_until = data`;
- os responsáveis por sala ficam em `rooms[].staff` (ids de pessoa);
- `kids_series_run` cria as escalas (`kids_assignments`) a partir de `rooms[].staff`;
- a equipe fixa antiga (`auto_team`) continua funcionando nas repetições existentes, sem migração destrutiva.

Alternativas descartadas:
- tabela nova de sessão: duplicaria a lógica de geração;
- manter a sessão avulsa separada: é a confusão atual.

## Decisões minhas
- Sessão "não repete" sem data futura não é aceita.
- Responsável fixo adicionado pela família recebe a relação "Responsável (a conferir)" e entra na lista "Para conferir".

# Módulo Kids — análise completa

Data: 17/11/2026 · Escopo: painel (Área Kids), app da igreja (responsáveis), Vinha Equipe (recepção e salas), banco (Supabase) e integração com o telão (Holyrics). As medições foram feitas no código, no banco local com todas as migrações e em capturas de tela de todas as abas (computador e celular).

## 1. Retrato atual

| Item                                    | Quantidade                                                                                                                                          |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Migrações do Kids                       | 18                                                                                                                                                  |
| Funções públicas do banco (RPC) do Kids | 20 (todas exigem login)                                                                                                                             |
| Rotas de API do painel                  | 9 (`kids-operations`, `kids-foundation`, `kids-desk`, `kids-notes`, `kids-resources`, `kids-station`, `kids/setup`, `kids/projector`, `kids/photo`) |
| Componentes do painel                   | 13 arquivos, ~117 KB (o maior: `KidsOperations.tsx`, 32 KB)                                                                                         |
| Telas no Vinha Equipe                   | KidsHub, KidsReception, KidsPassFlow, KidsBoard, KidsSetupScreen, KidsSessionEditor                                                                 |
| Telas no app da igreja                  | KidsFamily, KidsGuardians, KidsCareFields, KidsCallAlert, KidsVolunteerScreen                                                                       |

**Menu do painel:** Hoje (Visão geral, Entrada e retirada, Ocorrências, Telão e estações) · Crianças · Configurar (Sessões, Salas e turmas, Equipe, Materiais) · Relatórios (Presenças, Histórico).

## 2. Onde está a configuração do Holyrics

Ela existe, mas está no lugar errado: **Área Kids › Hoje › Telão e estações**, no fim da página, e só aparece para quem pode configurar. Quem procura em **Configurar** não encontra.

**Proposta:** levar "Telão (Holyrics)" e "Estações de recepção" para **Configurar › Telão e estações**. Em **Hoje** fica só um aviso curto de situação ("Telão conectado · testado às 09:12" ou "Telão desligado"), com um link para a configuração.

## 3. Lentidão — causas encontradas

| #   | Causa                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Impacto                             | Correção                                                                                                                                                  |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1  | **Foto da criança: uma chamada por criança.** `KidsChildPhoto` chama `/api/kids/photo` para cada cartão e não guarda nada em cache (`no-store`). Cada chamada confere o login, consulta o banco e gera um link assinado no Storage. Com 60 crianças na sala, a tela faz **60 chamadas** a cada atualização.                                                                                                                                                                                                                | Alto (principal causa)              | Gerar os links das fotos **em lote**, na mesma resposta da lista (como já foi feito em Pessoas), com validade de alguns minutos e cache no navegador.     |
| L2  | **Todas as abas carregam juntas.** `KidsOperations.tsx` importa direto os 11 subcomponentes (recepção, leitor de comprovante, impressão, telão, configuração, família…) mesmo quando só a Visão geral é aberta.                                                                                                                                                                                                                                                                                                            | Médio                               | Carregar cada aba sob demanda (`lazy`), como em Pessoas.                                                                                                  |
| L3  | **Duas consultas em sequência na rota principal.** `/api/kids-operations` chama a página e, depois, `unit_timezone`.                                                                                                                                                                                                                                                                                                                                                                                                       | Baixo/médio                         | Devolver o fuso dentro da própria `kids_operations_page` (uma ida ao banco).                                                                              |
| L4  | **Índices faltando em chaves estrangeiras** usadas nos filtros e junções: `kids_guardians (person_id, organization_id, approved_by, created_by)`, `kids_profiles (organization_id, unit_id)` e `(organization_id, person_id)`, `kids_team (person_id, class_id, member_id, organization_id)`, `kids_guardian_calls (organization_id, unit_id)`, `kids_session_series (organization_id, unit_id)`, `kids_stations (unit_id)`, `kids_projectors (organization_id)`, `kids_history (actor_id)`, `kids_profiles (created_by)`. | Médio, cresce com o volume          | Uma migração só com os índices (sem mudar regra).                                                                                                         |
| L5  | **Atualização automática frequente.** O quadro das salas no Vinha Equipe consulta a cada 15 s e o aviso de chamado no app, a cada 20 s, mesmo com a tela em segundo plano.                                                                                                                                                                                                                                                                                                                                                 | Baixo hoje, alto com muitas igrejas | Pausar quando a tela não está visível e aumentar o intervalo fora do horário da sessão. Etapa futura: aviso em tempo real (Realtime) só para os chamados. |

## 4. Layout

| Onde                                 | Problema                                                                                                                                                                 | Ajuste                                                                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Telão e estações                     | Formulário do Holyrics desalinhado (caixa de seleção e chave lado a lado, token sozinho na linha de baixo, botões no meio). Rodapé com letras espaçadas, difícil de ler. | Formulário em uma coluna: ligar/desligar, chave, token, botões **Salvar** e **Testar telão** alinhados à direita; guia "Como configurar" abaixo.                  |
| Hoje › Telão e estações / Relatórios | O seletor de **Sessão** aparece em telas onde não muda nada (configuração do telão) ou repete o filtro de período (relatórios).                                          | Mostrar o seletor só em Visão geral, Entrada e retirada e Ocorrências.                                                                                            |
| Relatórios                           | Dois botões "Atualizar"; campo "De" largo e "Até" estreito; o texto técnico "Até (exclusivo)"; datas no formato do navegador.                                            | Um só "Atualizar"; período com dois campos iguais e atalhos (Hoje, 7 dias, 30 dias); trocar por "Até"; datas em dd/mm/aaaa.                                       |
| Visão geral                          | Barra de ocupação com verde fora da paleta e trilho cinza grosso; texto "Equipe disponível" grande demais numa sala e em faixa amarela na outra.                         | Barra fina na cor da igreja, amarela quando está perto da lotação e vermelha quando lota. Linha de equipe igual em todos os cartões, com selo quando falta gente. |
| Entrada e retirada                   | Cartões das crianças com alturas diferentes; títulos "Ocorrências" e "Orientações" em letra maior que o nome da criança; 4 botões quebrando em duas linhas.              | Grade com cartões da mesma altura; nome em destaque; ação principal (**Confirmar retirada**) visível e as demais no menu "Mais ações".                            |
| Configurar                           | Se a resposta do servidor vier num formato inesperado, a página inteira quebra (a tela não confere o formato, ao contrário de Hoje).                                     | Conferir o formato da resposta e mostrar um aviso com "Tentar novamente".                                                                                         |
| Celular                              | As abas principais quebram em 2×2 e as secundárias rolam de lado sem indicação.                                                                                          | Abas principais em uma linha rolável, com a ativa sempre visível.                                                                                                 |

## 5. Arquitetura e organização do código

- **Padrão correto:** tela → rota curta da API (confere sessão e formato) → função do banco `security definer` com `search_path` fixo. Regras de quem pode o quê ficam no banco (`kids_allowed`, `kids_op_allowed`) e valem igual para o painel, o app e o Vinha Equipe.
- **Contratos compartilhados** (`shared/contract/kids.ts`) validam comandos e respostas. Exceção: o painel de Configurar (`KidsSetupPanel`) e o Telão (`KidsProjector`) leem a resposta sem validar (ver item de layout).
- **Arquivo grande:** `KidsOperations.tsx` (32 KB, linhas longas) concentra as abas, o modal de entrada e as ações. _Sugestão:_ separar em `kids/Overview`, `kids/Attendance`, `kids/EntryDialog` ao fazer o carregamento sob demanda (L2), sem mudar regras.
- **Código sem uso:** nenhum encontrado. Os 13 componentes do painel, as 20 funções do banco e todas as tabelas do Kids estão em uso pelo painel, pelo app ou pelo Vinha Equipe. Antes de qualquer exclusão futura, conferir também `app/api/app/notifications` (usa chamados do Kids), `hierarchy` (contagens) e `consent/templates` (termo de imagem do Kids).

## 6. Integração painel ↔ app da igreja ↔ Vinha Equipe

| Fluxo                                         | Painel          | Vinha Equipe           | App da igreja                       | Situação                                |
| --------------------------------------------- | --------------- | ---------------------- | ----------------------------------- | --------------------------------------- |
| Cadastro da criança e responsáveis            | ✅ Crianças     | ✅ cadastro imediato   | ✅ família + responsável temporário | OK                                      |
| Reserva com QR                                | —               | ✅ lê o QR             | ✅ gera o QR                        | OK                                      |
| Entrada e retirada com comprovante            | ✅              | ✅ estação de recepção | ✅ comprovante                      | OK                                      |
| Chamar responsável                            | ✅              | ✅ quadro da sala      | ✅ alerta (consulta a cada 20 s)    | Funciona; ganharia com notificação push |
| Telão (Holyrics)                              | ✅ configuração | —                      | —                                   | Mover para Configurar                   |
| Aviso ao responsável na entrada e na retirada | ❌              | ❌                     | ❌                                  | **Falta**                               |
| Aniversariantes do Kids                       | ❌              | ❌                     | ❌                                  | **Falta**                               |
| Escala de voluntários do Kids                 | ✅ equipe fixa  | ✅                     | ✅ tela do voluntário               | OK                                      |

## 7. Segurança

| Verificação                                  | Resultado                                                                                                                                              |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Funções do Kids que abrem sem login (`anon`) | **0** ✅                                                                                                                                               |
| Foto da criança                              | Só para quem opera o Kids naquela igreja (`kids_op_allowed … 'read'`); o arquivo fica em bucket privado (`member-photos`) e sai por link temporário ✅ |
| Comprovante de retirada                      | O banco guarda só o hash; o contrato do painel recusa qualquer resposta que traga o segredo ou o hash ✅                                               |
| Estações (tablets)                           | Limite de 50 por igreja, desativação encerra o login do aparelho na hora, só coordenação ou supervisão ✅                                              |
| Telão                                        | Mostra só o número da etiqueta, nunca o nome da criança ✅                                                                                             |
| Chave e token do Holyrics                    | Guardados no cofre do banco (Vault), nunca devolvidos ao navegador; a tela só informa "já salva" ✅                                                    |

## 8. Análise de mercado

O que os sistemas de referência oferecem (sem copiar telas nem textos de nenhum deles):

| Recurso                                                  | Planning Center Check-Ins | KidCheck       | MyKids / ChurchSuite | Vinha hoje                                  |
| -------------------------------------------------------- | ------------------------- | -------------- | -------------------- | ------------------------------------------- |
| Totem de autoatendimento (pais fazem a entrada sozinhos) | ✅                        | ✅             | ✅                   | ❌                                          |
| Código de segurança que muda a cada entrada              | ✅                        | ✅             | ✅                   | ✅ (comprovante)                            |
| Aviso automático aos pais na entrada e na retirada       | parcial                   | ✅             | ✅                   | ❌                                          |
| Chamar os pais durante o culto                           | ✅ (texto)                | ✅ (pager/SMS) | ✅                   | ✅ (app + telão)                            |
| Foto do responsável autorizado na retirada               | ✅                        | ✅             | ✅                   | ✅                                          |
| Alerta de alergia na etiqueta e na tela                  | ✅                        | ✅             | ✅                   | ✅                                          |
| Pré-cadastro de visitante por link, sem app              | ✅                        | ✅             | ✅                   | parcial (QR de visitante geral)             |
| Aviso quando a criança deixa de vir há semanas           | ✅                        | —              | —                    | ❌                                          |
| Funciona sem internet por alguns minutos                 | ✅                        | ✅             | —                    | ❌ (por segurança, retirada exige internet) |

**Diferenciais da Vinha que devem ser mantidos:** telão com número da etiqueta, responsável temporário autorizado pelo próprio app, sessões recorrentes com equipe fixa e regras de acesso por turma.

**O que não vale trazer agora:** pager físico (custo de hardware) e modo totalmente offline (aumenta o risco na retirada).

## 9. Plano proposto

**Fase 1 — Desempenho (sem mudar regras)**

1. Fotos em lote na resposta da lista, com cache curto (fim do N+1).
2. Abas carregadas sob demanda e `KidsOperations.tsx` dividido por aba.
3. Fuso horário dentro de `kids_operations_page` (uma consulta só).
4. Migração de índices das chaves estrangeiras do Kids.
5. Atualização automática pausada com a tela em segundo plano (Vinha Equipe e app).

**Fase 2 — Layout e organização**

1. **Configurar › Telão e estações** (Holyrics + estações), com status resumido em Hoje.
2. Formulário do Holyrics em uma coluna e situação do telão (ligado, desligado ou sem configuração) na Visão geral.
3. Seletor de sessão só nas abas de operação; Relatórios com período e atalhos.
4. Cartões de sala e de criança padronizados (barra de ocupação, ações principais).
5. Validação das respostas em Configurar e Telão.

**Fase 3 — Novos recursos**

1. Aviso no app ao responsável quando a criança entra e quando sai (push), com o nome da sala.
2. Aniversariantes do Kids na Visão geral e lembrete à equipe da sala.
3. Aviso de "criança sem vir há 4 semanas" para a coordenação (acompanhamento).
4. Modo totem: a estação do Vinha Equipe aceita o QR da reserva sem operador; a retirada continua com conferência da equipe.

Cada fase segue o mesmo processo: testes de banco e de código, capturas antes e depois, banco de teste, produção e atualização do Portal da Vinha.

## 10. Entregue — 17/11/2026

**Fase 1 — Desempenho**

- Fotos em lote: `/api/kids/photo?profiles=` + `kids_child_photos` (uma consulta e uma assinatura por tela; cache de 9 min no painel e no Vinha Equipe). A rota antiga continua para os apps já instalados.
- Abas do painel carregadas sob demanda; fuso da igreja consultado em paralelo.
- 14 índices nas chaves estrangeiras do Kids (`20261117160000_kids_desempenho.sql`).
- Quadro das salas no Vinha Equipe pausa com o app em segundo plano (o app da igreja já pausava).

**Fase 2 — Layout**

- Telão e estações em Configurar; linha de situação do telão na Visão geral.
- Holyrics em uma coluna; seletor de sessão só nas abas de operação.
- Relatórios: atalhos (Hoje, 7, 30, 90 dias), “Até” inclusivo, um só Atualizar.
- Cartões de sala com barra de ocupação (amarela perto da lotação, vermelha lotada) e selo “falta equipe”; cartões de criança com “Confirmar retirada” e “Mais ações”.
- Configurar e Telão conferem a resposta do servidor; seções roláveis no celular.

**Fase 3 — Novos recursos** (`20261117170000_kids_avisos_familia.sql`)

- Aviso no app aos responsáveis permanentes na entrada e na saída (gatilho na presença: vale para painel, estação, QR e totem). Sem dados de saúde. Tocar abre a Área Kids. Não aparece na lista de campanhas.
- Aniversariantes da semana (Visão geral e selo no Vinha Equipe) e Relatórios › Ausências (`kids_insights`).
- Modo totem no Vinha Equipe: só entrada pelo QR da reserva; sair exige pressionar 2 s.

## 11. Complementos — 17/11/2026

- **Código:** `KidsOperations.tsx` dividido. As abas de operação (Visão geral, Entrada e retirada, Salas e turmas, Datas e escala, Equipe da data, Histórico) ficam em `app/kids/KidsTabs.tsx`; textos e utilitários em `app/kids/kids-ui.ts`. A tela principal guarda o estado, as consultas e o formulário (34 KB → 24 KB). Capturas antes e depois iguais.
- **Lembrete de aniversário à equipe** (`20261117190000_kids_aniversario_equipe.sql`): quando a criança aniversariante entra, a equipe escalada na sala e a coordenação da sessão recebem um aviso no app da igreja (“🎂 Aniversário na Sala Arca · Ana faz 5 anos hoje…”). A família não recebe esse lembrete. Os avisos usam uma função única (`private.kids_push`).

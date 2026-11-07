# Escalas S2 — planejamento e experiência visual

## Escopo implementado

Calendário mensal, semanal e lista, com período, equipe, situação, título e paginação. A igreja vem do seletor central e mantém os limites de acesso. Alternar a apresentação preserva os filtros de equipe, situação e busca; mensal/semanal ajustam o período correspondente. Preferência de apresentação preservada no navegador por igreja.

Cadastro com título, chegada, início, término, local, orientações, busca de evento existente e coordenador no cadastro de Pessoas. Nenhum vínculo cria evento ou amplia permissões. Equipes/funções geram a quantidade cadastrada de vagas; integrantes ativos podem ser atribuídos conforme permissão. Vagas também podem permanecer abertas.

Rascunhos, duplicação independente, repetição diária/semanal/mensal de até 120 ocorrências em dois anos. Prévia conferida no servidor antes de salvar ou cancelar. Recorrência mensal ancora o dia original e ajusta fevereiro sem deslocar março. Horários interpretados no fuso configurado da igreja. Edição atual, atual e próximas, ou série inteira. Todas as versões afetadas são conferidas na mesma transação; alterações concorrentes não são sobrescritas. Cancelamento conserva cadastro e histórico.

Detalhe com Resumo, Equipes, Respostas e Histórico. Respostas informa explicitamente que os convites ainda não foram enviados. Pendências/trocas e relatórios operacionais têm indicação honesta de disponibilidade na próxima etapa. Nenhuma tela antiga foi desbloqueada.

## Verificação

- 37 verificações SQL de planejamento: isolamento, autorização por equipe, revogação, papéis de atribuição, horários/fuso, vagas, repetição, idempotência, versões de todas as ocorrências, duplicação e cancelamento. Mais 45 verificações da base S1.
- 13 testes JavaScript da base/planejamento; quatro de contenção da liberação. Verificações de tipos, segredos e botões preservam a base existente.
- Homologação visual local: quatro ocorrências semanais criadas; série inteira editada; uma pessoa e uma vaga aberta por ocorrência; cópia independente criada e cancelada com histórico.
- Revisão a 390 × 844: formulário sem transbordamento horizontal. Corrigida a altura herdada do cabeçalho que sobrepunha o aviso no celular. Arquivo local de evidência: `output/escalas-s2-formulario-mobile.png`.

## Limite desta entrega

Publicação, convites, confirmações, conflitos, substituições e presença pertencem à S3. Nesta etapa as escalas são rascunhos ou canceladas; não existem confirmações simuladas nem sobrescrita de respostas publicadas. A S3 deverá acrescentar o fluxo de impacto sobre escalas publicadas, preservando o histórico e as respostas. Comunicação e relatórios operacionais completos seguem na S4.

## Liberação

Migração: `20261107063611_escalas_planejamento_series.sql`. Somente tabelas novas e funções com acesso autenticado, sem transformação de dados antigos. Reversão operacional: recolher a montagem do novo planejamento; conservar as tabelas e o histórico. Publicação será registrada após validação da integração contínua e da versão de produção.

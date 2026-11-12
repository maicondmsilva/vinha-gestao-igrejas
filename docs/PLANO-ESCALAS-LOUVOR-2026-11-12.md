# Plano · Escalas e Louvor · Vinha

Data: 12/11/2026.

## 1. Situação atual

### Escalas (funciona, com banco próprio)

| Parte | Onde | O que faz hoje |
|---|---|---|
| Equipes e funções | `ScalesFoundation.tsx`, `private.scale_foundation` | Equipes por igreja, funções com vagas, integrantes ligados ao cadastro de Pessoas, acessos por equipe. |
| Planejamento | `ScalesWorkspace.tsx`, `private.scale_planning` | Cultos e eventos com vagas por função, repetição (diária, semanal, mensal), duplicar, cancelar e pré-visualizar. |
| Operação | `ScalesOperations.tsx`, `private.scale_operations` | Preencher vagas, sugestões, conflitos, publicar, revisar, cancelar, fechar, respostas, substituições e presença. |
| Voluntário | `VolunteerScaleApp.tsx`, `MemberVolunteerScales.tsx`, `private.scale_volunteer` | Ver as escalas, aceitar ou recusar, informar indisponibilidade e pedir substituição. |
| Permissões | `scales.teams`, `scales.schedules` | Concluídas (P3/P4), com limite por equipe. |

O que falta em Escalas, pela análise:
1. **Visão de calendário**: hoje a navegação é por listas. Falta ver o mês e a semana com os cultos e as vagas abertas.
2. **Montagem rápida**: preencher vagas exige abrir cada culto. Falta um quadro "funções × cultos" para escalar várias datas de uma vez, com conflitos e indisponibilidades à vista.
3. **Saúde da escala**: vagas abertas, recusas e pessoas sobrecarregadas aparecem espalhadas. Falta um painel com esses alertas.
4. **Visual**: três folhas de estilo diferentes (`scales.css`, `scales-planning.css`, `scales-foundation.css`) e tamanhos de fonte inconsistentes. Precisa seguir o padrão novo (o mesmo de Usuários e Perfis pendentes).

### Louvor (ainda é demonstração)

`WorshipOperations.tsx` e `MusicCatalogSearch.tsx` usam **dados fixos na tela**: nada é gravado no banco, e a "busca de música" não consulta nenhum serviço. O módulo `worship` já existe no catálogo comercial, mas não tem tabelas, regras nem permissões.

## 2. Proposta

### Louvor: módulo real, ligado às Escalas

1. **Repertório** (`worship_songs`): título, artista, tom original, BPM, compasso, letra e cifra (texto com acordes), links (vídeo, áudio, cifra externa), etiquetas (adoração, celebração, ceia…) e situação (ativa, em ensaio, arquivada). Busca e filtros por tom, etiqueta e situação.
2. **Repertório do culto** (`worship_setlists` e itens): ligado ao **culto da Escala** (`scale_services`). Músicas em ordem (arrastar para reordenar), **tom do dia** com transposição automática da cifra, quem ministra cada música e observações (introdução, repetições). Os músicos vêm da equipe de Louvor já escalada no culto.
3. **Visão do músico**, no aplicativo do voluntário: repertório do próximo culto, cifra já transposta, modo palco (letra grande, rolagem) e confirmação de ensaio.
4. **Histórico**: quando cada música foi tocada, para evitar repetir demais e para relatórios.
5. **Permissões**: novas seções no catálogo, "Louvor › Repertório" (ver/criar/editar/excluir) e "Louvor › Repertório do culto" (ver/criar/editar), com limite por equipe de escala, seguindo a regra do plano de permissões.

### Escalas: visual moderno e montagem rápida

1. **Painel da semana**: próximos cultos com vagas preenchidas/abertas, recusas e pedidos de troca pendentes, num cartão por culto.
2. **Calendário** mensal/semanal com cores por equipe.
3. **Quadro de montagem**: linhas = funções, colunas = cultos do período. Ao clicar numa vaga, a pessoa é escolhida entre as sugestões, com conflitos e indisponibilidades marcados. Publicar em lote.
4. **Padronização visual**: uma folha de estilo única, tipografia e espaçamentos iguais aos das telas novas, e versão para celular.

## 3. Etapas

| Etapa | Entrega |
|---|---|
| L1 | Banco do Louvor: repertório, repertório do culto (ligado a `scale_services`), histórico, permissões e testes de banco. |
| L2 | Tela Louvor › Repertório (lista, busca, filtros, ficha da música com cifra e transposição). |
| L3 | Tela Louvor › Culto (montar repertório do culto, ordem, tom do dia, ministro) e visão do músico no aplicativo do voluntário. |
| E1 | Escalas: painel da semana e calendário. |
| E2 | Escalas: quadro de montagem com publicação em lote. |
| E3 | Escalas: padronização visual e celular. |

Cada etapa é aplicada primeiro no banco de teste, com testes de banco e de tela, e depois publicada.

## 4. Pessoas · análise (12/11/2026)

Feito nesta etapa:
- **Barra do topo sem repetição**: saiu a faixa que repetia o nome do módulo acima de todas as páginas (cada página já tem o próprio título). O ajuste de nomes do ministério continua no ícone de engrenagem do topo.
- **Lista de Pessoas modernizada**: tipografia e tamanhos iguais às telas novas; números úteis no topo (Todos, Membros, Em integração, Visitantes), que também funcionam como filtro; tabela com iniciais, número de cadastro, etapa em cor; no celular vira cartões.
- **Numeração de membros** saiu do topo de Pessoas e foi para Configurações › Identidade e cadastro (é uma escolha do ministério inteiro).
- Perfis pendentes e transferências aparecem em Pessoas só quando há pedido.

O que falta e proponho a seguir:
1. **Aniversariantes** do dia, da semana e do mês, com atalho para mensagem.
2. **Possíveis duplicados**: mesmo nome com data de nascimento ou telefone parecido, com tela para juntar cadastros.
3. **Filtros por célula, rede, gênero, faixa etária e batismo**, e **exportar para Excel** respeitando os filtros.
4. **Histórico do membro**: mudanças de etapa, transferências, células e escalas numa linha do tempo na ficha.
5. **Ações em lote**: mudar etapa, adicionar etiqueta e enviar comunicado para os selecionados.
6. **Novos convertidos e acompanhamento**: etapa e responsável pelo acompanhamento, com lembrete.

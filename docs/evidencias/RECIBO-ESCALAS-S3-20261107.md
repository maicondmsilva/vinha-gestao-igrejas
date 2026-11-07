# Escalas S3 — operação e área do voluntário

Entrega de 07/11/2026. A publicação de uma escala cria convites internos individuais; não representa entrega de e-mail ou push.

## Funcionalidades

- Publicar, preparar revisão, cancelar e encerrar, com prévia de ocorrências e confirmações afetadas. Revisões preservam respostas anteriores e a republicação pede nova confirmação.
- Área Minhas escalas na página do membro e no código do Android: convite próprio, confirmação/recusa, pedido de substituição e disponibilidade semanal ou por período, com edição, cancelamento e reativação.
- Igreja oficial e identidade do cadastro de Pessoas. A seleção de conteúdo de outra igreja não amplia acesso nem transfere as atribuições.
- Habilitações por função, coexistência explícita de funções e intervalo de deslocamento. Sobreposição usa chegada e término reais. Exceções de horário/disponibilidade exigem justificativa; habilitação e dupla vaga na mesma função não podem ser ignoradas.
- Sugestões com escolha humana por conflitos e carga dos últimos 30 dias. Substituição revalida os dados e cria um novo convite pendente. A pessoa substituída mantém seu histórico, sem acesso às orientações atuais.
- Confirmação e presença independentes. Registro pela liderança identifica autor, data e justificativa. Encerramento não transforma resposta pendente em ausência.
- Pendências e trocas com busca/paginação; habilitações e regras dentro de Equipes e funções. Formulários de operação em janela própria, cores Vinha e controles móveis alinhados.

## Verificação

- 72 verificações SQL S3, 37 regressões S2 e 45 S1: aprovadas no Docker local, transações revertidas.
- Teste concorrente real: resposta confirmada preservada, revisão com prévia antiga rejeitada; repetição de requisição não duplica histórico.
- 27 testes JavaScript de Escalas/Android, tipagem web e Android, controles interativos e varredura estática de segredos: aprovados.
- Homologação visual com a igreja e a conta fictícias locais: publicar → responder na área do membro → conferir confirmação no painel; disponibilidade, solicitação de troca e formulário móvel. Nenhuma escala real foi publicada por este teste.

## Limites

A etapa S4 continua responsável por comunicação externa homologada, integrações adicionais, exportações e relatórios avançados. O código Android foi atualizado e validado; não equivale a publicação na loja nem a instalação em aparelho. Endpoints legados permanecem contidos.

# Recuperação financeira e escopo — 18/10/2026

## Escopo realizado

Testes determinísticos locais, sem acesso ao banco de produção, sem envio de mensagens, sem cobranças e sem alteração de permissões. Nenhuma mudança funcional ou publicação foi feita neste bloco.

`scripts/ledger-recovery.test.mjs` executa o handler real de envio extraído do componente, com respostas de rede controladas. Confere:

- perda de resposta mantém o pedido pendente e libera o estado de processamento;
- reenvio utiliza exatamente o mesmo conteúdo e identificador;
- HTTP 503, resposta HTML de gateway e resposta sem confirmação não são tratados como sucesso;
- estorno incerto preserva o pedido original;
- recusa definitiva de acesso não anuncia gravação nem atualiza o histórico como se tivesse ocorrido sucesso.

`scripts/ledger-pilot.test.mjs` amplia a matriz de autorização da API:

- secretário, pastor, líder, membro e visualizador não consultam nem gravam no piloto financeiro;
- lançamento, criação de conta, fechamento e estorno em unidade não autorizada são recusados antes de chamar o banco;
- os testes anteriores continuam verificando ministério derivado da sessão, habilitação exclusiva de homologação e consultas fora do escopo.

## Resultado

`node --test scripts/*.test.mjs`: **112 testes aprovados, zero falhas**.

## Limites e próximos passos

São testes de handler e API com dependências controladas: não substituem uma sessão real com vários usuários/unidades ou falha de rede no navegador. A idempotência efetiva do banco foi testada em blocos anteriores; este bloco verifica a preservação do mesmo pedido na camada de interface.

Permanecem pendentes a homologação integrada no navegador dessas condições, a revisão/publicação dos PRs e as dependências externas de L3/L4. Não houve atualização do PR remoto ou nova execução de CI neste bloco. A evidência visual anterior permanece em `docs/HOMOLOGACAO-VISUAL-FINANCEIRO-2026-10-18.md`.

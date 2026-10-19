# Suspensão concorrente de operador na confirmação

## Correção candidata

A confirmação revalidava o gestor na entrada, mas podia aguardar o catálogo e retomar um resultado anterior sem nova consulta da permissão. Adicionada leitura bloqueante `FOR SHARE` da participação ativa owner/admin após obter o bloqueio de catálogo, antes do contrato e da leitura idempotente. Revalida também os requisitos existentes de MFA e e-mail confirmado.

A permissão é serializada: se a suspensão vence primeiro, a confirmação é recusada; se a confirmação já protegeu a participação, a suspensão aguarda seu término. Não promete interromper uma transação que já venceu essa ordem. O bloqueio conservador aumenta risco de contenção; outros caminhos que obtenham recursos em ordem inversa exigem revisão própria.

## Evidências locais

O executor de concorrência passou em oito cenários sobrepostos READ COMMITTED. Os dois novos cenários usam conta/operador fictícios e um segundo proprietário sintético, preservando a regra de último proprietário:

- Suspensão não confirmada inicialmente visível, com confirmação esperando catálogo: após commit da suspensão, retomada de pedido aceito é recusada com `42501`, sem novo ajuste.
- Confirmação vence primeiro: suspensão concorrente atinge `55P03` com espera curta; não altera acesso antes do commit. Nova suspensão após commit funciona.

Banco temporário removido automaticamente; dados locais existentes e produção preservados. A reexecução dos testes transacionais é separada da suíte concorrente.

## Limites

Cobertura específica de `platform_operators.active` e confirmação protegida. Não certifica suspensão concorrente do ministério, cancelamento de contrato, banimento em Auth, exclusão de sessão, todos os caminhos de faturamento ou todos os níveis de isolamento. Não habilita a confirmação na interface nem aplica candidatas ao banco persistente do navegador.

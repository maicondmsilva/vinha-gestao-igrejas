# Mudança imediata de plano — regra confirmada em 18/10/2026

O usuário confirmou: efeito imediato; upgrade cobra diferença proporcional; downgrade gera crédito na próxima fatura, sem estorno automático. Faturas anteriores e o pagador definido no contrato devem ser preservados.

## Cálculo implementado

`app/lib/plan-proration.ts` calcula uma cotação pura. Recebe preço líquido atual e novo em centavos e os instantes reais de início/fim/alteração do ciclo. A proporção usa o tempo restante do ciclo real, sem divisor fixo de 30 dias. A aplicação deve fornecer instantes com fuso resolvido; o cálculo não usa o relógio/fuso da máquina.

Diferença proporcional = (novo preço líquido − preço líquido atual) × tempo restante ÷ duração do ciclo. Arredondamento para centavo mais próximo, empate afastando de zero, simétrico para débito/crédito. Numerador e denominador exatos são preservados para auditoria. Cálculo interno inteiro evita ponto flutuante.

Exemplo: R$ 100 para R$ 160 na metade exata do ciclo gera R$ 30 de cobrança. R$ 160 para R$ 100 gera R$ 30 de crédito na próxima fatura, sem reembolso automático. No fim exclusivo do ciclo, ajuste do ciclo anterior é zero; o ciclo seguinte usa o novo preço.

## Integração ainda pendente

Esta função **não altera contrato, libera módulos, emite fatura ou cria crédito no banco**. A regra não está ativa em produção. Antes da ativação, implementar transação autenticada que bloqueie contrato/ciclo, derive preço líquido e pagador no servidor, grave snapshot imutável/UUID de alteração, registre ajuste/crédito uma única vez e efetive módulos atomicamente. Cotações do navegador não podem ser fonte de cobrança.

Múltiplas alterações no ciclo exigem considerar a versão e o último preço efetivo, preservar base exata e validar a política de arredondamento acumulado. O consumo do crédito na próxima fatura deve ser transacional e não pode descontar duas vezes em geração concorrente. Esses fluxos e a cobrança externa ainda não estão implementados por esta entrega. Não recalcular faturas antigas a partir do catálogo atual.

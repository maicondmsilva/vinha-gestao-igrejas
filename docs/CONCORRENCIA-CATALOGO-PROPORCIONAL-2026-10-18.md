# Confirmação e editor de catálogo concorrentes

## Execução local

`node scripts/local-proration-concurrency.mjs --local-synthetic`: seis cenários sobrepostos READ COMMITTED passaram. O executor criou e removeu exclusivamente seu banco temporário, copiando estrutura (sem linhas dos clientes) e usando fixtures sintéticas.

Os quatro cenários anteriores seguem cobrindo as três candidatas iniciais. Depois deles, o executor aplica a quarta candidata de confirmação ao banco temporário e testa:

1. Editor altera o preço primeiro e mantém a transação aberta. A confirmação sobreposta aguarda e recusa o snapshot antigo com `40001`, sem criar ajuste.
2. Confirmação inicia primeiro e mantém a transação aberta. O editor sobreposto encontra o bloqueio de catálogo e atinge o limite curto de espera (`55P03`). O preço permanece intacto, a confirmação é única, e uma nova edição funciona depois do commit.

O segundo cenário confirma bloqueio, não reenvio automático do editor. O editor é uma conexão de teste com papel postgres no banco temporário, para simular DML concorrente; não certifica todas as telas/RPCs administrativas nem seus próprios padrões de bloqueio. O teste usa confirmação sem mudança líquida de plano para não alterar a fatura já emitida pela fixture anterior.

## Limites

Não cobre revogação/suspensão concorrente, gerador mensal legado ou catálogo alterado por uma transação que também bloqueie contratos em ordem inversa. Não valida REPEATABLE READ/SERIALIZABLE nem desempenho em produção. SHARE sobre tabelas inteiras é conservador e exige revisão de contenção antes de escala.

As candidatas não foram aplicadas persistentemente ao banco do navegador. A confirmação da interface permanece bloqueada. Próxima validação: sessão real/MFA e caminho HTTP no ambiente local, sem remover a autenticação para facilitar o teste.

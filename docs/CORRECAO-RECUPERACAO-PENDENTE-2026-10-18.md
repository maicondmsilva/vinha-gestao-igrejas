# Recuperação após recarga — correção local em 18/10/2026

## Implementação

A API autenticada de bootstrap fornece o escopo conta:ministério derivado do acesso validado, não de campos enviados pelo cliente. O piloto restaura pedidos de sessionStorage somente depois desse bootstrap e valida a unidade contra as unidades autorizadas. A autorização de cada gravação continua no servidor/banco.

Pedidos de lançamento/estorno são validados e salvos antes do envio. Falha de armazenamento impede o envio. Campos extras como tokens não são persistidos. Dados corrompidos ou unidade sem autorização bloqueiam a retomada, sem apagar silenciosamente o pedido. Outro pedido não pode sobrescrever o pendente. Confirmação com identificador diferente não limpa o registro.

## Verificação

- 118 testes automatizados aprovados, incluindo isolamento de escopo, conteúdo inválido, armazenamento indisponível e identidade do reenvio.
- TypeScript do piloto aprovado.
- Navegador real em localhost: pedido `28da42f0-f0c5-442b-b434-f4ccf561b042`, R$ 1,23 fictícios, preparado com servidor local interrompido.
- Reinício do servidor e recarga automática preservaram exatamente esse identificador.
- Reenvio pela tela confirmado; nova recarga mostrou um único movimento e saldo de R$ 1,23 na conta sintética, sem pendência.
- Evidência: `outputs/ledger-recovery-fixed-20261018.png`.

## Limites

sessionStorage é armazenamento temporário da aba, não backup, criptografia ou fila offline durável. Fechar a aba, limpar dados do navegador ou usar outra aba pode perder a recuperação. Nenhuma senha/token é salvo, mas descrição e valores ficam no armazenamento da mesma origem; não se deve considerar isso isolamento contra outra pessoa com acesso ao navegador ou contra XSS. A retomada é separada por conta/ministério e exige autorização atual; não foi implementada limpeza global de pedidos no logout neste bloco.

O cenário testado interrompe o servidor antes da gravação. Perda da resposta depois de a transação ter sido confirmada continua coberta por testes controlados/idempotência anteriores, não por este cenário visual. Testes com abas concorrentes e recuperação após encerramento de aba permanecem pendentes. O piloto continua proibido em produção. Nenhuma migração, publicação ou atualização remota de PR foi realizada neste bloco.

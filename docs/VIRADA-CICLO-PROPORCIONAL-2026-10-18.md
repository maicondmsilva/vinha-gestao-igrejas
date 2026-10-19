# Virada do ciclo proporcional — homologação local, 18/10/2026

## Implementação

Migração aditiva `20261018161147_proration_cycle_rollover_pilot.sql` e POST `/api/platform/contracts/cycle-rollover`. A migração não foi aplicada persistentemente ao banco local principal nem à produção. O teste unitário aplica dentro de transação revertida; o ensaio concorrente aplica em banco temporário com estrutura copiada e dados exclusivamente fictícios.

A transação exige gestor da Central com MFA/e-mail confirmado, contrato ativo com versão atual, organização/unidade/assinatura disponíveis e fatura registrada pelo fluxo de emissão do mesmo contrato/pagador. O valor bruto validado da fatura deve corresponder ao preço líquido do contrato, sem confundir abatimento por crédito com preço contratado.

O novo período começa no limite anterior e só pode ser aberto depois desse instante, antes do próximo limite mensal. Não aceita datas ou preços do navegador; período futuro, lacuna de meses e versão antiga são recusados para revisão. O calendário usa America/Sao_Paulo e preserva o dia de referência: 31/janeiro → 29/fevereiro bissexto → 31/março, sem derivar silenciosamente todo mês do dia reduzido de fevereiro.

Atualiza versão do contrato, vínculo de fatura e período, acumuladores proporcionais, histórico e auditoria atomicamente. Reenvio do mesmo UUID/conteúdo retorna a mesma transição. A virada não altera faturas antigas, documentos de crédito ou consumos; reinicia somente os acumuladores do ciclo. O saldo remanescente é preservado para a próxima fatura elegível.

Histórico de viradas tem RLS, leitura restrita a gestores da Central e nenhum DML direto concedido a clientes/chave de serviço. A rota é opt-in, exige ambiente isolado e permanece recusada em produção. Não foi conectada a tela ou agendador neste bloco.

## Resultados observados

- **135 testes de aplicação** aprovados; TypeScript restrito e varredura estática de segredos aprovados.
- **59 verificações SQL** aprovadas: calendário bissexto/âncora, fatura incorreta, período futuro, versão antiga, replay, crédito remanescente e acesso negado.
- Falha forçada na auditoria da virada reverteu a transição e preservou o acumulador anterior.
- Massa histórica fictícia: crédito de 1.500 centavos preservado na virada; nova mensalidade de 1.000 ficou com valor zero e 500 centavos permaneceram disponíveis. A preparação direta dessa massa apenas simula um ciclo já encerrado; não é alteração de dados reais ou prova de toda a cadeia histórica de produção.
- **4 cenários concorrentes reais READ COMMITTED**, com duas sessões sobrepostas: mesmo pedido de mudança, mudança com versão antiga, reenvio de emissão e reenvio de virada. A virada produziu uma transição, sem consumir o crédito antes da emissão.
- Banco temporário removido ao final; estrutura/dados do banco local existente preservados. Cópia de estrutura não certifica restauração de backup/default privileges, conforme limites do runner anterior.

## Limites restantes

Ainda faltam concorrência com o gerador mensal antigo, outras combinações de UUIDs/isolamentos, revogação durante transação e alterações concorrentes no catálogo. Não há avanço automático de períodos atrasados, troca de pagador com transferência de crédito, cancelamento com reversão auditada ou interface operacional ligada a estas rotas.

Nenhuma implantação, atualização remota de PR, envio, nota ou cobrança real foi executada. Os testes não autorizam declarar a L4 concluída ou liberar os pilotos em produção.

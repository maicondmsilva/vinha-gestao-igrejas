# Recebimentos unificados e confirmação do pagamento

Pedidos de eventos e vendas ainda não pagos ficam na operação do evento/venda. A consulta financeira aceita somente provas de pagamentos confirmados de produção ou recebimentos anteriormente contabilizados. A filtragem ocorre antes do limite e do cursor da consulta. Não foi alterado o mecanismo que exige prova do provedor antes de contabilizar.

Lançamentos apresentam um recebimento por pagamento, incluindo principal, juros, multa, desconto, bruto, taxa, devolução e saldo. Descontos vêm do pedido; juros/multa ficam em zero porque o checkout atual não os cobra. Valores do provedor são somente leitura; descrição e observações mantêm edição auditada. Nenhum histórico foi apagado.

A unificação acontece antes da contagem e paginação no banco, inclusive quando somente uma devolução do pagamento antigo corresponde ao período ou filtro. Saldos e fluxo preservam os componentes e suas datas reais. Livro caixa/extrato e exportações reúnem os componentes selecionados, usando o líquido do período, não o líquido acumulado do recebimento. Classificações, partidas contábeis e conciliação mantêm os dados originais.

Exemplo: R$ 10,00 recebidos, R$ 10,00 devolvidos e R$ 0,30 de taxa não devolvida resultam em −R$ 0,30. Não é correto apagar essa taxa ou atribuí-la ao valor devolvido ao comprador.

Validação local: 169 testes JavaScript financeiros; 276 verificações SQL nas suítes F1/F2/F4/F5/F6 e operação. Incluem paginação, confirmação, devolução parcial/total, crédito de taxa, período posterior e proteção de acesso. Tipos e verificações de botões/segredos executados. Formulário revisado no navegador com dados fictícios em desktop e viewport de 390 px, sem transbordamento horizontal do documento. Nenhum pagamento ou reembolso real foi iniciado.

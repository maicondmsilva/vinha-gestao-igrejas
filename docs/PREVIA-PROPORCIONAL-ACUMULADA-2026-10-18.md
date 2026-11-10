# Prévia proporcional acumulada

Implementado `previewCumulativeProration`, cálculo puro que considera o numerador acumulado e o ajuste já arredondado do ciclo. Rejeita histórico inconsistente e mantém valores em centavos exatos. A prévia é estimativa, não autorização de cobrança nem substituto da transação no banco.

Validação: nove testes direcionados passaram, incluindo troca inversa sem geração de centavos e efeito de frações anteriores.

Ainda não conectado à tela ou a uma consulta autenticada de contexto do contrato. A confirmação deverá revalidar preço, permissão, versão e ciclo no banco. Não houve migração ou publicação de produção.

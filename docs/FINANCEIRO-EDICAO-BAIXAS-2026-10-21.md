# Correção de lançamentos manuais

- Botão Editar nas listas e na ficha, inclusive para realizados e liquidados.
- Edição de natureza, valor principal, descrição, conta/destino, categoria/subcategoria, centro, pessoa/fornecedor, datas, forma e observações.
- Pago/Recebido pode ser desmarcado. Transferência e saldo inicial são movimentos realizados por definição.
- Motivo e confirmação explícita obrigatórios. Identidade, código, autoria original e anexos não são trocados.
- Diários anteriores são estornados nas datas originais; nunca reescritos. Períodos fechados impedem toda a correção.
- Baixas ativas e suas taxas são revertidas juntas. Ao realizar novamente, os ajustes agregados de juros, multa, desconto e taxa são preservados. Baixas com taxas em categorias diferentes exigem primeiro estorno pelo acompanhamento, evitando classificação arbitrária.
- Uma ocorrência de série é editada individualmente; as demais não são alteradas.
- Recebimentos digitais confirmados e registros auxiliares de uma baixa não usam este editor. O status externo não pode ser fabricado por edição manual.
- Repetição idempotente, versão desatualizada e autorização por ministério/unidade verificadas no banco e na API. A API antiga permanece apenas para pedidos antigos de previsão.
- Códigos apresentados sem prefixo #.

## Validação

24 verificações SQL locais com dados fictícios e rollback: realização, edição de liquidado, reabertura, preservação de taxa/juros/multa/desconto, efeito no saldo, código estável, repetição, versão, classificação, unidade e período fechado.
Testes da API/parser e regressão das telas, tipos, build, segredos e controles interativos.
Este documento descreve a implementação; a confirmação de publicação deve ser registrada separadamente, sem confundir build local com produção.

# Confirmação protegida contra alteração de catálogo

Implementada migração candidata `20261018181106_proration_confirmation_catalog_guard.sql`.

- Nova operação exige snapshot completo de plano, módulos e vínculos.
- Autoriza gestor confirmado com MFA; mantém autorização do fluxo interno.
- Bloqueia tabelas do catálogo em SHARE antes de bloquear o contrato, mantendo a comparação e a gravação na mesma transação. É uma estratégia conservadora para o piloto; serializa alterações de catálogo e pode aumentar espera.
- Reenvio idêntico retorna o resultado original, sem duplicação, após revalidar o gestor.
- Retira a execução direta da operação anterior de contas autenticadas, evitando contornar a comparação.

## Evidência

Oito testes SQL passaram em transação desfeita no Docker local. Preço alterado foi recusado, prévia renovada aceita, reenvio único preservado e conta sem permissão recusada. Nenhum dado persistente ou de produção foi alterado.

## Não concluído

A migração não foi aplicada persistentemente. API/UI ainda não enviam o snapshot esperado e a API antiga ainda chama a operação anterior: **não aplicar esta candidata isoladamente com esse código**. É necessário atualizar o comando, compor a estimativa usando o mesmo snapshot e testar concorrência real com editor de catálogo. Os executores históricos anteriores continuam testando somente as três candidatas originais; não certificam a nova confirmação.

A autorização é reavaliada na entrada, mas suspensão/revogação concorrente continua exigindo teste e sincronização próprios. Não reclassificar como resolvida por este bloco. Gerador mensal, cancelamento, pagador e atrasos seguem pendentes.

## Continuação: integração da API

O código local foi atualizado após a rodada acima: `plan-change` agora valida o comando com `expectedCatalog` e chama `confirm_unit_contract_plan_pilot`; a prévia consulta `proration_catalog_preview_pilot` e calcula o valor exclusivamente a partir desse snapshot, não de três consultas independentes de catálogo. O snapshot é preservado, limitado em tamanho e conferido quanto a duplicidades, vínculos e preços exatos.

162 testes de aplicação e a verificação de tipos passaram. Os testes de rota usam cliente simulado. O botão continua bloqueado, e a migração candidata não foi aplicada persistentemente. Logo, o servidor local ligado a um banco sem a quarta candidata recusará a consulta: não é evidência de integração HTTP real concluída. A publicação exige o conjunto correspondente de código/migrações revisado, nunca somente um dos lados. Continuam pendentes concorrência real do catálogo e sessão autenticada/MFA.

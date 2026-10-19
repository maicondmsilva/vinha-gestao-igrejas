# Troca visual de unidades — 18/10/2026

Homologação realizada exclusivamente no Docker local, com conta e unidades fictícias preparadas por `scripts/local-browser-fixture.mjs --local-synthetic`.

## Cenário aprovado no navegador

1. Login real da conta sintética.
2. Abertura do piloto financeiro com ministério explícito na URL.
3. Seletor apresentou Sede visual de teste e Campus visual de teste.
4. Criada a conta Caixa exclusivo da sede na sede, com confirmação do banco e saldo zero.
5. Selecionado o campus: a conta da sede não apareceu no saldo nem nas opções de lançamento.
6. Criada a conta Caixa exclusivo do campus no campus, com confirmação e saldo zero.
7. Retorno à sede: reapareceu somente a conta da sede, sem a conta do campus.

Ministério sintético: `visual-local-356d6c4b-bc38-4ddc-9920-8b032ec24c62`.

Evidência local: `outputs/ledger-units-20261018.png`. A aba de teste foi fechada; isso não equivale a comprovar logout. Nenhuma credencial foi persistida na documentação ou no código. Os dados fictícios foram preservados no Docker.

## Limites

Não foram criados lançamentos monetários nesse cenário; a separação visual conferida foi das contas e opções de lançamento. O teste não prova recuperação offline no navegador, troca rápida sob respostas fora de ordem ou persistência de pedido pendente após recarga. Não houve publicação nem alteração de produção.

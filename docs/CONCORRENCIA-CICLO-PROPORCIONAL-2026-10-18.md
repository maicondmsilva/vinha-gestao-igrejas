# Concorrência e proteção do ciclo proporcional — 18/10/2026

Continuação: `VIRADA-CICLO-PROPORCIONAL-2026-10-18.md` registra a implementação posterior da virada, testes de crédito remanescente e o quarto cenário concorrente.

## Escopo

Somente Docker local `supabase_db_vinha`. O novo runner `scripts/local-proration-concurrency.mjs --local-synthetic` cria banco `proration_qa_20261018_<sufixo aleatório>`, copia apenas a estrutura, prepara contas e contratos fictícios e remove exclusivamente o banco que criou. Não copia linhas do banco original, não imprime esquema/credenciais e não chama provedores.

As extensões locais foram conferidas. A cópia portátil preserva permissões dos objetos existentes, mas omite padrões de privilégios futuros de papéis gerenciados que o usuário local não pode restaurar. Portanto o teste não certifica restauração integral de backup ou default privileges. Não houve alteração de papéis globais para contornar isso. As primeiras preparações falharam em esquema/extensões/default privileges; os bancos temporários foram removidos também nessas falhas.

## Cenários reais

Usadas duas conexões independentes com barreira após a primeira gravação e sobreposição comprovada. Isolamento: **READ COMMITTED**, não REPEATABLE READ/SERIALIZABLE.

1. Mesmo UUID de alteração simultâneo: ambas as tentativas retomam o resultado; há apenas um ajuste.
2. UUIDs diferentes com mesma versão de contrato: primeira alteração confirma; segunda recebe conflito de versão, sem novo ajuste.
3. Mesmo UUID de emissão simultâneo: uma fatura nova, um uso de crédito e valor líquido de 7.000 centavos para bruto 10.000/crédito 3.000.

## Proteção implementada após revisão do ciclo

Contrato com próxima fatura já emitida não pode alterar plano, decisões de módulos, pagador ou vencimento enquanto a fatura ainda é futura. Isso evita deixar preço/pagador congelados na fatura e contrato divergentes. A operação recebe conflito e deve passar por revisão; não cancela nem recalcula a fatura silenciosamente.

42 testes SQL transacionais incluem essa proteção e verificam que a recusa não deixa ajuste/documento parcial. 133 testes de aplicação e varredura estática de segredos aprovados.

## Ainda pendente

- Virada efetiva de ciclo: rotina explícita para vincular fatura validada ao novo período, preservar saldo de crédito e permitir mudanças seguintes. Não avançar datas manualmente.
- Concorrência com o gerador mensal antigo, diferentes UUIDs de emissão, alterações no catálogo e níveis de isolamento mais fortes.
- Crédito maior que a mensalidade em ciclos sucessivos, revisão legítima de fatura antecipada/cancelamento com reversão auditada, e interface de confirmação.

As migrações novas não foram aplicadas no banco local principal nem em produção. O runner utiliza banco temporário; o teste SQL unitário continua com rollback. Nenhum PR remoto ou implantação foi atualizado neste bloco.

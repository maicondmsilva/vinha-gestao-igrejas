# Integração proporcional — núcleo transacional de homologação

Continuação: `FATURA-PROPORCIONAL-CREDITO-2026-10-18.md` registra a implementação posterior de documentos internos e consumo de crédito, ainda em homologação e sem integração automática/provedor. Os limites abaixo descrevem a entrega original deste núcleo.

## Entrega

Migração aditiva `20261018151747_unit_contract_proration_pilot.sql`, função `change_unit_contract_plan_pilot` e rota POST `/api/platform/contracts/plan-change`.

O núcleo exige operador owner/admin da Central com MFA e e-mail confirmado. Bloqueia o contrato, revalida versão/estado e ministério, unidade e assinatura disponíveis. Preço vem do plano/módulos no banco, nunca do navegador; pagador permanece o do contrato. O ciclo deve ser informado explicitamente e estar em andamento. Primeira mudança exige fatura-base válida do mesmo contrato/pagador e valor compatível com a composição atual. Legado divergente é recusado para revisão, não reconstruído por inferência.

Atualiza plano, registra ajuste/ciclo, snapshot do novo preço e módulos e auditoria na mesma transação. Reenvio do mesmo UUID/conteúdo/operador devolve o snapshot original; conteúdo diferente é recusado. Versão de contrato antiga é recusada. O numerador proporcional acumulado no ciclo evita arredondar cada diferença isoladamente e produzir centavo extra em alterações inversas.

Tabelas novas têm RLS; clientes não têm permissão de inserir/alterar/apagar ajustes. Leitura apenas por gestores da Central com MFA. SECURITY DEFINER é limitado à transação privilegiada com essas validações explícitas; não usa metadados editáveis do usuário para autorização. Nenhuma chamada externa é feita com bloqueios de banco abertos.

## Estado financeiro honesto

`chargeCents` e `creditCents` são registros internos com `settlementStatus=pending_integration`. **Não são cobranças no provedor, reembolsos ou créditos já consumidos.** Fatura-base não é reescrita. O crédito aponta para `next_invoice`, mas o abatimento na próxima geração de fatura ainda não está implementado neste bloco.

Não se trata de snapshot completo do faturamento legado. O snapshot novo captura plano, preços de módulos, decisões e pagador na alteração; faturas anteriores continuam com suas limitações documentadas.

## Contenção e verificação

A rota fica desativada por padrão, exige `VINHA_PLAN_PRORATION_PILOT=true` e o mesmo gate de ambiente isolado do livro financeiro; produção é recusada. Não há botão conectado na tela atual; o PUT antigo não foi substituído. Migração não foi aplicada em produção nem registrada no banco local: foi executada dentro de transação revertida por `node scripts/local-proration-test.mjs --local-synthetic`, em container fixo `supabase_db_vinha`.

23 testes SQL exercitam atomicidade, MFA, histórico, reenvio, conflito, versão, preservação de fatura e crédito. 132 testes de aplicação e TypeScript restrito aprovados. A primeira execução encontrou um erro de nome SQL, corrigido antes do aceite. Um teste de revogação tentou alterar o próprio operador e foi corretamente recusado pela governança existente; foi substituído por verificação de outra conta sem acesso, sem enfraquecer a proteção.

## Próximos itens obrigatórios

1. Rever/aplicar migração no banco isolado e executar a suíte SQL completa, incluindo testes concorrentes reais de duas alterações no mesmo contrato e catálogo alterado durante a transação.
2. Conectar tela com prévia, fatura-base e ciclo explicitamente revisados, confirmação e UUID persistido; bloquear mudança direta antiga que contorne o novo fluxo quando houver piloto ativo. Não substituir essa tela antes dessa proteção e homologação.
3. Implementar geração da fatura adicional e consumo único/transacional de crédito na próxima fatura, com replay e concorrência; depois integração com provedor sandbox.
4. Tratar virada de ciclo: o protótipo aceita somente o ciclo já registrado para esse contrato; novo ciclo exige rotina própria, não atualização manual da tabela.
5. Não suporta troca simultânea do pagador, ciclo, descontos e módulos explícitos; a função somente troca o plano, preservando as decisões explícitas atuais. Contratos com desconto/preço divergente da fatura-base exigem revisão.
6. Revisão e CI remoto antes de qualquer publicação. Não foram realizadas migrações de produção, cobranças, emissões fiscais ou envios.

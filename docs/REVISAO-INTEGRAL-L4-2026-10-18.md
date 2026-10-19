# Revisão integral da L4 — 18/10/2026

## Decisão de liberação

**L4 não concluída e não liberada para clientes com dados reais.** Esta revisão implementa melhorias locais, não substitui as entregas faltantes do plano consolidado. Não reclassificar a fase como concluída apenas porque os testes existentes passaram. O piloto continua bloqueado em produção.

## Inventário e critérios de conclusão

| Bloco | Evidência atual | Pendência para conclusão | Dependência |
|---|---|---|---|
| L4.1 Livro persistente | Contas, partidas balanceadas, leitura por unidade e data, API/UI de homologação no Supabase | Centros de custo estruturados, anexos privados específicos do financeiro, saldo inicial com validação contábil e conciliação persistente | Desenvolvimento e aceite contábil |
| L4.2 Integridade e recuperação | Centavos exatos; transação/auditoria; UUID idempotente; estorno; fechamento; testes SQL; restauração do pedido na mesma aba | Recuperação durável entre abas/dispositivos, perda de resposta após commit no navegador, revogação concorrente de acesso durante gravação, limpeza no logout com preservação segura de pendências | Desenvolvimento/testes; não depende de gateway |
| L4.3 Provedores das igrejas | Livro segregado por organização/unidade; não usa recebedor SaaS para ofertas | Conexão e segredos por igreja, webhooks idempotentes, recebedor correto, conciliação de liquidação/taxas/estornos | Conta sandbox autorizada de cada recebedor e implementação |
| L4.4 Faturamento Vinha | Perfis/pagadores, contratos por unidade, geração e consolidação de faturas, testes transacionais existentes | Snapshot imutável de plano/módulos/preços/descontos/pagador e composição; matriz completa de mudança de plano, vigência, cancelamento e concorrência de checkout | Desenvolvimento e regra comercial explícita para alterações no meio do ciclo |
| L4.5 Cartão recorrente | Payload e adaptador sandbox com checkout hospedado; cartão não coletado pela Vinha | Homologar ciclo seguinte, cancelamento remoto, falhas, replay, cobrança dupla e reconciliação com a fatura interna | Conta sandbox autorizada; sem credenciais fornecidas |
| L4.6 Fiscal | Validação de CNPJ, código/tributos e revisão contábil; adaptador de homologação | Autorizar/rejeitar/cancelar/substituir nota; guardar PDF/XML privados; entrega comprovada ao responsável correto | Contador, município, enquadramento e credenciais; não inventar regras fiscais |
| L4.7 E-mail/WhatsApp | Regras de vencimento e assinatura de retornos, escape de HTML, configuração preparada | Domínio/remetente autorizado, templates Meta, consentimento/destinatários, entrega real, filas com reexecução/limites e alertas | Provedores de envio e homologação autorizada |
| L4.8 Relatórios | Saldo exato por conta/unidade/data; nova exportação CSV autenticada | Razão com partidas completas, filtros/centros de custo, exportação aceita pelo contador e fechamento conciliado | Desenvolvimento e aceite do contador |

## Achados e mudanças desta revisão

1. **Recusa temporária podia apagar recuperação.** A interface removia o pedido em todo erro 4xx. Agora 401, 403, 408 e 429 mantêm o identificador e o comando, sem presumir que uma tentativa anterior não foi gravada. Não há reenvio automático após recuperar acesso.
2. **Duplo envio antes do próximo render.** Adicionado bloqueio síncrono por referência ao redor do envio. Teste de duas chamadas simultâneas confirma somente uma chamada HTTP. Isso não coordena outras abas ou dispositivos.
3. **Fechamento da aba.** Adicionado aviso explícito e proteção `beforeunload` enquanto houver pedido pendente. O navegador pode ignorar o aviso; não é persistência durável nem backup.
4. **Relatório exportável ausente.** Implementado CSV de saldos da unidade/data com centavos e valores decimais exatos, UTF-8, escape e neutralização de fórmulas. Exige a mesma autenticação e escopo da consulta; resposta privada/no-store e nome de arquivo fixo. Limite de 500 contas recusa, não trunca silenciosamente. Não inclui o razão, não é obrigação fiscal nem conciliação.
5. **Cobertura no CI incompleta.** Incluídos testes de recuperação, armazenamento e CSV na definição do workflow. Os arquivos ainda precisam ser enviados/revisados no PR para que esse CI remoto os execute.
6. **Histórico de faturas.** `invoiceList` em `app/lib/supabase/central-billing.ts` obtém `plan_name` pelo contrato/assinatura e plano atuais. A exibição não comprova o plano histórico da fatura. A geração grava valor/pagador, mas isso não equivale a um snapshot completo da contratação. Não alterar faturas antigas por inferência: mapear dados disponíveis e produzir migração aditiva revisada.
7. **Dívida de controles legados.** Verificador encontrou 49 controles sob proteção global, dentro do limite atual de 50. Não equivale a homologação manual de todos esses controles nem foi resolvido nesta revisão.

## Verificações executadas

- 124 testes de aplicação: aprovados.
- TypeScript restrito ao piloto: aprovado.
- 1.047 testes SQL em 22 arquivos no Docker: aprovados, sem migração de produção.
- Smoke HTTP com sessão real, criação fictícia, lançamento, reenvio idempotente, estorno e saldo zero: aprovado.
- Isolamento entre ministérios/unidades e recusa de secretaria: aprovado no smoke HTTP.
- CSV autenticado de saldos e resposta privada: aprovado no smoke HTTP.
- Varredura estática de segredos: aprovada; não substitui varredura de histórico/rotação.
- Teste inicial do CSV esperava texto exato do cabeçalho; o servidor acrescenta `max-age=0`. Corrigida a asserção para exigir `private` e `no-store`, aceitando essa proteção adicional. A primeira tentativa interrompeu antes do logout; contas/sessões eram exclusivamente fictícias locais. A reexecução completa encerrou suas sessões.
- Build Vercel local aprovado. As duas tentativas restritas falharam com EPERM na criação de artefatos `.vercel`; a execução com permissão de escrita passou. Nenhum deploy foi executado.
- Prévia autenticada no navegador confirmou o link CSV com unidade/data/ministério corretos e saldos sintéticos. Evidência `outputs/l4-review-20261018.png`. Não se afirma abertura em Excel ou aceite contábil.

## Sequência de implementação restante

1. Recuperação durável: criar intenção persistente autorizada antes da gravação, estado/consulta por conta/ministério/unidade, reaproveitar UUID no banco e evitar alterações de conteúdo. Não usar somente localStorage como solução para múltiplas abas.
2. Faturamento: snapshot imutável para novas faturas, representação explícita de legado sem reconstrução falsa; testes de módulos, descontos, pagadores individual/centralizado e gerações concorrentes. Definir se mudança no meio do ciclo tem pró-rata, crédito ou vigência no próximo ciclo antes de implementá-la.
3. Livro: centros de custo com FKs compostas por organização/unidade; comprovantes em bucket privado, validação de conteúdo/tamanho, autorização para download e auditoria; não reutilizar permissões de arquivos de membros sem revisão.
4. Conciliação: extrato importado com hash/idempotência, prévia, vínculo com partidas, divergências/taxas, desfazer vínculo com histórico sem reescrever lançamento e bloquear declaração de conciliado sem evidência.
5. Relatórios: razão de partidas paginado/exportável, saldos inicial/final e demonstração revisada com contador. Validar arquivos no software de destino.
6. Homologações externas de L4.3/L4.5/L4.6/L4.7, com destinatários de teste e sem cobranças reais; guardar referência da evidência e resultado.
7. Aceite operacional L3 (restauração/monitoramento/rollback), revisão dos PRs e autorização de implantação correspondente. Somente então considerar piloto controlado com clientes.

## Limites de autoridade e publicação

Nenhum contrato de provedor foi criado, nenhum cartão foi cobrado, nenhuma nota emitida e nenhuma mensagem disparada. O usuário informou anteriormente não possuir sandbox de pagamentos nem contador responsável. A solicitação de concluir a fase não fornece essas credenciais nem define decisões comerciais/fiscais ausentes. Não publicar o módulo como pronto para clientes. As alterações desta revisão permanecem locais até envio/revisão e execução do CI remoto.

# Homologação financeira L4 — 18/10/2026

## Parecer

**Não aprovada para operação comercial. Homologação técnica local parcial aprovada; homologação visual completa e integrações externas pendentes.** Não foram realizados deploy, migração em produção, cobranças, emissão fiscal ou envio de mensagens.

## Execução desta rodada

- `npm run test:l4:local`: **13/13 suítes aprovadas**, saída 0, após conceder acesso ao Docker local. A tentativa inicial restrita obteve 3/13 porque não conseguia acessar a conexão do Docker; não foi uma evidência de regressão financeira.
- O conjunto executa 175 testes de aplicação, verificações SQL existentes e proporcionais, cancelamento/substituição, pagador/atrasos, concorrência, MFA real local, HTTP real local, tipos, segredos e build. Contagens detalhadas e limites em `EXECUCAO-CONSOLIDADA-L4-2026-10-18.md`.
- `npm run test:central`: **14/14 testes aprovados**, saída 0. São subconjunto da aplicação, não 14 casos adicionais independentes.
- Ampliado `scripts/local-platform-mfa-smoke.mjs`: consultas HTTP de operações financeiras e canais recusadas em aal1, aceitas em aal2 com resposta sem cache, recusadas após logout; rota legada de conciliação responde 503/FEATURE_NOT_RELEASED. Só leituras, sem chamar validação externa de canais ou envio.
- Contas fictícias MFA são encerradas e removidas pelo executor; servidor próprio encerrado; dados de clientes não são usados como fixtures.

## Matriz de evidências e impedimentos

| Área | Evidência disponível | O que impede aprovação completa |
|---|---|---|
| Contratos e proporcional | SQL de confirmação, catálogo, créditos, cancelamento, substituição, pagador e atrasos; concorrência | `PlanPreview.tsx` mantém confirmação desabilitada; faltam ações conectadas e execução autenticada pelo navegador |
| Créditos e documentos | Cálculos e leitura/validação de respostas testados | Sete candidatas não estão aplicadas persistentemente na instância usada pelo navegador; falta jornada visual completa |
| Livro | Testes de comandos, recuperação local, relatórios, regras SQL e seis cenários concorrentes | Não certifica recuperação durável entre dispositivos, centros de custo, anexos privados ou razão contábil completo |
| Conciliação | Contenção da rota antiga verificada por HTTP | `app/api/finance/reconciliation/route.ts` ainda contém implementação D1 legada, protegida por bloqueio. Não há fluxo operacional migrado e homologado de extrato/conciliação persistente |
| Pagamentos | Adaptador sandbox, payload recorrente, recusa de entrada inválida e falha HTTP | Nenhuma evidência nova de conta sandbox, checkout autorizado, primeira cobrança, renovação, recusa, cancelamento remoto e retorno real autenticado |
| Fiscal | Validações de dados e revisão contábil; vínculo com pagamento | Faltam configuração fiscal validada por contador e emissão/rejeição/cancelamento reais de homologação, PDF/XML e entrega ao responsável |
| E-mail | HTML seguro e validação de assinatura Resend testados | Remetente/domínio, destinatário autorizado e entrega/retorno reais ainda não comprovados |
| WhatsApp | Assinatura Meta testada | Conta/número, modelos aprovados, consentimento e entrega/retorno reais ainda não comprovados |

As abas encontradas no navegador estavam em erro de conexão com localhost. Isso não equivale a testar formulários autenticados. Esta rodada não declara botões, modais, responsividade ou acessibilidade visual homologados.

## Critérios de aceite restantes

1. Preparar instância local persistente isolada, com conjunto de candidatas compatível e dados exclusivamente fictícios. Preservar banco atual e as proteções de MFA; não apontar homologação para produção.
2. Conectar e testar na interface: prévia → confirmação → ajuste/crédito → fatura mensal → cancelamento → devolução → substituição; troca de pagador e retomada de atraso. Conferir valor exibido versus persistido, duplo clique, atualização, navegação, erro e resultado incerto.
3. Implementar conciliação migrada: importação de extrato, deduplicação, correspondência, divergência de taxa/valor/data, vínculo auditado ao livro e desfazimento sem apagar histórico. CSV de saldos e fechamento de período não substituem essa entrega.
4. Testar livro pela interface: contas, lançamento equilibrado, transferência, estorno, período fechado, paginação, exportação, isolamento entre unidades e retomada após interrupção.
5. Configurar provedores de teste e destinatários autorizados sem inserir segredos na conversa. Executar cenários reais em sandbox, incluindo retornos duplicados/fora de ordem e resultado incerto; guardar referências e estados sanitizados, nunca chaves.
6. Revisão contábil e operacional antes de liberar clientes. Nenhum resultado unitário ou simulado substitui aceite externo.

## Limite de escopo

Foram seguidas as orientações Supabase e Sites para isolamento local, validação e ausência de publicação. Não houve relaxamento de RLS, MFA, contenção de legado ou bloqueios de produção para fazer testes passarem.

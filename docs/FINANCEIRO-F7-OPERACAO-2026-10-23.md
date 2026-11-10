# F7 — segurança, homologação e operação financeira

## Situação e limite de liberação

A F7 acrescenta auditoria de preparação de exportações, identificação legível de igrejas no orçamento sem movimentos, saldos de caixa no CSV e testes concorrentes. A conclusão técnica interna não substitui homologação externa nem habilita automaticamente movimentação de dinheiro real. Mercado Pago, Asaas e Safe2Pay devem ser validados separadamente com credenciais e contas autorizadas. Nenhuma credencial ou transação real faz parte das fixtures.

## Guia da tesouraria

1. Selecione a igreja pelo nome e código. Consolidação inclui somente igrejas autorizadas; uma unidade recusada impede a consulta inteira, sem omissão silenciosa.
2. Em contas e saldos, confira conta bancária, saldo inicial e conta recebedora correspondente antes de lançar. Credenciais de cada igreja ficam no cofre do servidor; nunca colocar token em observações ou comprovantes.
3. No lançamento informe categoria e subcategoria separadas, conta, datas, pessoa cadastrada quando houver e comprovante. Nome livre não cria vínculo automático com membro.
4. Após salvar, confira o número e histórico. Em falha de rede, atualize e localize o registro antes de tentar novamente. Não criar outro lançamento para compensar uma resposta desconhecida.
5. Baixas, reabertura e edição de valores devem preservar o histórico e as reversões contábeis. Não apagar diretamente o livro nem alterar saldos no banco de dados.
6. Conciliação compara extrato e livro: bruto, taxas, líquido, estornos e divergências precisam ser explicados. Ausência de OFX não impede fechamento administrativo com ressalvas por proprietário/administrador, mas não transforma o mês em conciliado.
7. Relatórios usam o mesmo escopo de acesso do banco. Valores realizados não duplicam títulos em aberto; transferências e saldos iniciais não são receita operacional.
8. Em exportações confira período, igrejas, base de data e aviso do relatório. CSV traz todas as linhas autorizadas até o limite, não somente a página. Acima de 10.000 movimentos reduza o escopo. O identificador de preparação relaciona o arquivo à auditoria; não prova que o navegador concluiu o download ou que o arquivo foi entregue a terceiros.

## Guia do administrador do ministério

- Conceda somente as unidades necessárias ao responsável financeiro. Relatório e filtro de contribuição individual, assim como alteração de orçamento, são restritos a proprietário/administrador; papel financeiro comum não concede esses poderes.
- Orçamento é mensal por igreja, categoria e centro exatos. Uma edição concorrente obsoleta será recusada: atualizar e revisar antes de salvar. Mês parcial não é comparação mensal integral.
- Provedores usam data de caixa/liquidação ou data do evento ainda não liquidado. Não atribuir competência inexistente a comprovante externo. Divergências OFX não recebem filtros cadastrais ausentes do extrato.
- Antes de conectar token, confirme provedor, ambiente, titularidade e igreja. Conta configurada não equivale a pagamento homologado. Não habilitar produção com uma chave de teste.
- Encaminhe exportação contábil ao contador para mapear o plano de contas e validar a importação. O arquivo auxiliar não é escrituração fiscal certificada nem emissão de nota.

## Guia da Central e recuperação

- O servidor exige `FINANCE_RECEIVER_ENCRYPTION_KEY` e `SUPABASE_SECRET_KEY`. A interface revela apenas disponibilidade; não revela valores. A chave de criptografia deve ter cópia segura separada: trocá-la sem recriptografar os segredos existentes pode impedir sua leitura.
- Registros de exportação guardam autor, igrejas, período, relatório, base de data e contagem; não copiam linhas de contribuições ou tokens.
- Em incidente de acesso, revogue a participação/sessão correspondente e preserve auditoria. Não desative RLS, confirmação de e-mail ou verificações de unidade para contornar falhas.
- Em regressão de publicação, reverta o código compatível e corrija seletivamente a função afetada. Não apagar tabelas, histórico ou executar reset de produção. A migração F7 altera a função preservando contratos e dados existentes.
- Antes de restauração, obtenha backup íntegro e teste em banco isolado. Banco, arquivos de comprovantes/Storage e chave do cofre exigem recuperação conjunta e controles separados. Backups externos, retenção, destino, alertas e teste real de restauração continuam dependentes de contratação/configuração; não estão comprovados por testes unitários.
- Consulte falhas da aplicação/Vercel e tempos de resposta (`Server-Timing`). Compare o mesmo usuário, igreja, período e volume antes/depois. Nunca registrar tokens ou dados pessoais completos em logs de diagnóstico.

## Matriz de homologação

| Capacidade | Evidência interna | Validação externa necessária |
| --- | --- | --- |
| Isolamento, papéis e contribuições | SQL e API; escopos recusados e revogação concorrente | Revisão dos papéis reais do ministério |
| Livro, baixas, taxas, estornos e conciliação | Suítes F1–F6 com dados fictícios e concorrência | Conferência pelo responsável/contador |
| Exportação e orçamento | F7: auditoria, CSV, versão concorrente e suspensão durante espera | Aceitação do arquivo pelo contador |
| Mercado Pago | Conector e testes internos | Conta autorizada; checkout, webhook autenticado, taxa, liquidação, devolução e disputa reais de teste |
| Asaas | Conector e testes internos | Conta de teste; identidade, cobrança, liquidação, devolução e webhook |
| Safe2Pay | Conector e testes internos | Conta de teste; contrato/API, cobrança, liquidação, devolução e webhook |
| E-mail | Recuperação de acesso formatada já confirmada | Envio transacional financeiro com configuração própria e destinatário autorizado |
| WhatsApp | Fluxos preparados | Remetente, token seguro, modelo aprovado, consentimento e entrega real |
| Fiscal | Fluxos preparados | Provedor, contador, município e emissão/cancelamento de homologação |
| Recuperação e monitoramento | Procedimento documentado | Destino externo, alertas, retenção e restauração completa comprovada |

## Critério de aceite por provedor

Com usuários e meios de teste oficiais, validar pagamento aprovado, pendente, recusado, repetição da notificação, assinatura inválida, interrupção de rede, recebimento duplicado, taxa desconhecida/conhecida, liquidação, reembolso parcial/total e disputa. Cada evento deve manter referências, bruto/taxa/líquido e um único efeito no livro. Antes do uso comercial real, reconciliar o relatório do provedor com o livro e registrar a evidência sem segredos. Não usar cobrança real de cliente como teste.

## Testes reproduzíveis

- Aplicação: `node --experimental-strip-types --test scripts/finance-f6.test.mjs scripts/finance-f6-route.test.mjs scripts/finance-f7.test.mjs`.
- SQL isolado existente: `node scripts/local-finance-f7-test.mjs --local-synthetic` (transação com rollback).
- Concorrência isolada: `node scripts/finance-f7-concurrency.mjs --local-synthetic` (fixtures fictícias únicas, preservadas para diagnóstico).
- CI: banco novo com todas as migrações, testes de segurança, SQL e concorrência. Nunca substituir por reset de banco com clientes.

# L4 — desenvolvimento e validação consolidados

## Decisão de liberação

**L4 não encerrada nem liberada para clientes.** Esta rodada consolidou desenvolvimento do faturamento e testes locais; não equivale à conclusão de toda a matriz L4. Produção, repositório remoto e provedores externos não foram alterados.

## Desenvolvimento entregue nesta rodada

### Faturamento mensal

O gerador existente agora tem uma candidata que mantém o fluxo dos contratos não piloto e delega os contratos proporcionais elegíveis à emissão que consome créditos. Usa identificador repetível por contrato/competência, trava contratos em ordem e evita emitir pela tabela antiga contornando o novo cálculo. Não recria competências canceladas automaticamente. Trata-se da função acionada pela geração da Central, não da implantação de um novo serviço agendado.

### Cancelamento interno, devolução e substituição

Nova operação auditada e idempotente cancela somente fatura interna aberta, sem pagamento, provedor, link externo, consolidação ou uso como base de ciclo. Devolve exatamente o crédito utilizado mediante novo registro; o consumo original não é apagado. Falha de auditoria desfaz status, devolução e registro do cancelamento.

Uma substituição exige apontar explicitamente a fatura cancelada. Original e substituta ficam preservadas, e o índice permite somente uma fatura não cancelada por contrato/competência. A emissão pode reutilizar o crédito devolvido, sem duplicação. Cancelamento interno não faz reembolso nem cancelamento remoto.

### Pagador e atrasos

Nova operação exige gestor, versão atual, justificativa e pagador ativo do mesmo ministério, com contrato ativo. Preserva faturas e créditos do pagador anterior e registra a mudança. Não transfere créditos automaticamente; saldos do pagador antigo podem exigir resolução administrativa própria. Alterações com fatura futura já emitida continuam sujeitas à proteção existente.

A virada suporta atraso superior a um mês, mas avança somente uma competência verificada por chamada. A recuperação exige emitir/verificar e avançar cada mês, guarda histórico contínuo e informa se ainda existe atraso. Os testes recuperam três competências; não há job de recuperação automática ilimitada instalado.

### API e leitura

Novas rotas locais de cancelamento e pagador usam sessão real da Central, origem exata, tamanho limitado e lista permitida de campos. O navegador não determina valores de devolução ou transferência. A consulta de créditos desconta devoluções, aceita o vínculo REST um-para-um e recusa histórico possivelmente truncado.

## Testes executados

Resultado da execução consolidada final: **13/13 suítes aprovadas**, saída 0. Conferência posterior encontrou zero bancos temporários desses executores. Nenhuma publicação foi realizada.

| Suíte | Resultado verificado |
|---|---|
| Aplicação | 175 testes aprovados |
| SQL existente | 1.047 verificações TAP em 22 arquivos, com rollback |
| Proporcional | 59 verificações sobre as sete candidatas finais |
| Confirmação protegida | 8 verificações |
| Cancelamento/substituição | 64 verificações, incluindo recusa de fatura paga e acesso não autorizado |
| Pagador/atrasos | 16 verificações |
| Concorrência proporcional | 11 cenários sobrepostos READ COMMITTED; também regressão do contrato não piloto |
| Concorrência do livro | 6 cenários: fechamento e duplicação em READ COMMITTED, REPEATABLE READ e SERIALIZABLE |
| MFA real | Login local, recusa em aal1, desafio TOTP real e aceitação em aal2 |
| HTTP real da Central | Consulta de contratos recusada sem MFA, aceita com MFA e recusada após logout |
| Tipos, segredos e compilação | Aprovados no escopo configurado; varredura estática não substitui revisão de histórico ou rotação |

Os totais SQL compartilham fixtures e regressões; não somar como casos únicos independentes. Os testes HTTP reais cobrem autenticação/consulta de contratos, **não** confirmação financeira por HTTP ou navegador.

O primeiro preparo do banco temporário do livro falhou por ausência de plano ativo; adicionados plano e módulo inteiramente sintéticos, sem copiar linhas do banco existente. A reexecução passou. As cópias de estrutura omitem defaults de privilégios não portáveis e não certificam restauração de backup.

## Execução única

`npm run test:l4:local` executa treze suítes, continua coletando falhas, não aceita destino remoto e não publica. Exige Docker local ativo, dependências já instaladas e porta 4100 livre para o servidor HTTP de teste. Contas MFA são encerradas/removidas; bancos temporários e o servidor próprio são removidos/encerrados ao final. Não reutiliza nem encerra servidor preexistente.

As sete migrações candidatas permanecem sem aplicação persistente no banco do navegador. Foram aplicadas em transações desfeitas ou bancos temporários. As novas operações existem no código, mas não estão operacionalmente disponíveis nessa instância persistente sem preparar o conjunto correspondente. O botão de confirmação da interface continua bloqueado.

## Pendências internas reais

1. Preparar um destino local persistente das candidatas e homologar prévia, confirmação, cancelamento, substituição e pagador pelas rotas financeiras reais e pelo navegador com MFA. Conectar as novas ações às telas; validar reenvio/incerteza também na interface.
2. Completar o livro: recuperação durável entre abas/dispositivos, centros de custo, anexos financeiros privados, conciliação persistente e razão contábil completo. CSV de saldos não é razão nem conciliação.
3. Ampliar concorrência da sétima candidata, matrizes de pagador/contratos/estados, retomada de atrasos em limites de calendário e falhas de recuperação; avaliar contenção dos bloqueios amplos. Os testes acima não certificam todos os caminhos nem revogação de sessão/banimento Auth concorrentes.
4. Revisão de implantação, compatibilidade de versões e migrações/índices antes de produção. Não aplicar isoladamente candidata antiga com API nova ou vice-versa.

## Dependências externas ainda ausentes

Conta sandbox e recebedores dos pagamentos; provedor de envio/remetente e WhatsApp; contador, município/enquadramento e credenciais fiscais; evidências reais de entrega, recorrência, cancelamento remoto e emissão/rejeição/substituição fiscal. Também continuam os critérios operacionais L3 de backup externo, restauração, alertas e rollback.

Nenhuma cobrança real, nota fiscal, mensagem ou promessa de liberação comercial foi produzida para substituir essas evidências.

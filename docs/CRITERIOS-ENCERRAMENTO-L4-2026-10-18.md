# Critérios de encerramento da L4

> Atualização posterior desta mesma data: consultar `EXECUCAO-CONSOLIDADA-L4-2026-10-18.md`. Parte das pendências de backend abaixo foi implementada e testada como candidata local; a lista original foi preservada como histórico, não como inventário atualizado de código. A fase continua aberta.

## Estado confirmado

L4 aberta, somente desenvolvimento local. Nenhuma autorização anterior de produção substitui a instrução posterior de continuar localmente. Não habilitar confirmação, provedores ou publicação para simular conclusão.

Nesta rodada: proteção contra preço nulo e números JSON sem precisão; sete testes da rota de prévia com cliente simulado; 159 testes da aplicação aprovados; TypeScript do escopo e verificação estática de segredos aprovados. Os testes da rota não são uma sessão real nem validação das políticas no servidor remoto.

## Desenvolvimento que ainda impede encerrar o bloco proporcional

1. **Confirmação transacional:** comparar versão e composição do catálogo e revalidar autorização na mesma transação. Não basta a prévia feita por consultas separadas; considerar a passagem do tempo e impedir aceitar preço comercial diferente sem nova confirmação.
2. **Gerador mensal legado:** serializar com os novos fluxos e impedir que emissão direta ignore créditos. A proteção de API no salvamento não fecha acessos diretos/RPC nem elimina condições de corrida.
3. **Cancelamento:** operação auditada e idempotente que restitua exatamente os créditos usados, preserve o original e não confunda cancelamento interno com cancelamento de cobrança externa já liquidada.
4. **Pagador:** vigência explícita, autorização, preservação do responsável histórico e regra para saldo do pagador anterior, sem transferir crédito silenciosamente.
5. **Atrasos:** avançar períodos sequencialmente e emitir/reconciliar competências sem duplicação; a virada atual não permite pular meses.
6. **Concorrência adicional:** gerador antigo versus emissão nova, alteração de catálogo durante confirmação e suspensão/revogação durante operação. Os quatro cenários existentes não cobrem esses casos.
7. **Interface autenticada:** aplicar candidatas somente no destino local escolhido, criar operadores fictícios com MFA e executar seleção, prévia, confirmação, reenvio, crédito, cancelamento e acesso negado. Não remover MFA para obter evidência visual.

## Restante da fase L4 original

Recuperação durável de intenções; centros de custo e anexos financeiros privados; conciliação persistente; razão completo exportável e aceite contábil. Consultar a matriz integral em `REVISAO-INTEGRAL-L4-2026-10-18.md`.

## Dependências externas separadas

- Pagamentos: conta sandbox autorizada, recebedores separados, testes de recorrência, cancelamento e webhooks.
- Fiscal: contador, enquadramento/município e credenciais; autorização, rejeição, substituição, cancelamento e documentos privados.
- Mensagens: remetente/domínio e provedor, configuração WhatsApp/consentimento, destinatários de teste e evidência de entrega.
- Operação L3: backup externo, restauração banco/Storage, alertas, responsáveis e ensaio de rollback.

Esses itens continuam sem evidências suficientes. Não é possível classificar L4 como finalizada ou liberada para clientes apenas com testes locais. O próximo trabalho prioritário é a confirmação transacional e o fechamento dos caminhos legados, não a abertura de uma fase comercial.

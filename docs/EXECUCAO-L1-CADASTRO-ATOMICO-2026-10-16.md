# L1 — bloco 3: cadastro de membros em transação

Data: 16/10/2026. Base: 8786ccff327764b68f609d55ca1be34042b44e85.

## Entrega delimitada

POST/PATCH de pessoas usam uma única função transacional no Supabase principal Vinha Igrejas (aoxibaaydfgffrdqtkva). Nenhuma conexão FERTICALC foi usada. Migração aplicada: 20261016034427_member_atomic_write.

- Pessoa, endereço, contato de emergência, consentimentos, nota pastoral e auditoria são confirmados juntos. Falha em qualquer etapa reverte a operação.
- Função SECURITY INVOKER, search_path vazio, sem execução anônima. Mantém RLS, papel autorizado, módulo e escopo de unidade. Não usa chave administrativa.
- PATCH preserva campos omitidos e unidade não informada; campos opcionais explicitamente vazios podem ser limpos. Identidade, organização e acesso ao aplicativo não podem ser promovidos pelo formulário.
- Edição bloqueia a linha da pessoa durante a transação; registros inacessíveis não retornam sucesso.
- Consentimentos fornecidos explicitamente geram histórico apenas quando mudam. São registros administrativos, não aceite verificado do titular. Notas pastorais são acrescentadas para proprietário/pastor; editor vazio não apaga notas.
- O formulário usa unidades reais, preserva valores ao navegar entre etapas e recarrega o cadastro confirmado pelo servidor. Falha ao atualizar a lista depois de salvar não provoca repetição automática da criação.
- Opções fictícias de família, célula, envio de convite e foto foram retiradas ou sinalizadas como indisponíveis. Grupo/ministério permanece texto livre, não vínculo relacional.

## Verificação

- 46 testes da aplicação: 28 segurança/integridade, 4 contenção e 14 financeiro/integrações.
- 82 verificações pgTAP em sete arquivos SQL, com dados sintéticos e rollback no banco local isolado. Incluem falha deliberada na auditoria, rollback de endereço/consentimentos, bloqueio entre organizações, concessão somente leitura e recusa de nota pastoral por líder.
- Build de produção Vercel concluído localmente. CI deve repetir o build e todos os testes sobre instalação limpa.
- TypeScript global permanece com 313 diagnósticos; não é checagem aprovada.
- A migração foi gerada por comparação do banco local, revisada para manter SECURITY INVOKER explícito, checagem do corpo habilitada e privilégios mínimos. Não houve teste de escrita em dados reais.
- Publicação da aplicação deve ser comprovada pelo PR/deploy correspondente; aplicar a função isoladamente não publica a interface.

## Limites e próxima etapa

Não libera piloto comercial. Falta validação visual autenticada com os papéis reais e unidades autorizadas; ainda não foi executada neste bloco.

Não há chave de idempotência: perda de conexão pode impedir confirmar se uma operação inteira foi concluída. A mensagem orienta atualizar a lista antes de repetir. Concorrência entre sessões, formulários desatualizados e mudanças de concessão durante a operação precisam de testes adicionais.

O formulário edita o contato de emergência mais antigo e preserva contatos adicionais. Histórico de consentimentos/notas é preservado por esta função, mas isso não transforma todas as outras permissões de acesso direto em um histórico imutável. Revisar essas permissões no próximo bloco.

A checagem do módulo segue o contrato/contexto existente; revisão integral dos contratos por unidade ainda é necessária. Continuam pendentes auditoria das funções privilegiadas, endpoints públicos, proteção contra abuso, validação de e-mail real, redução dos erros TypeScript e demais critérios do plano de lançamento. Não houve envio de mensagens, cobrança ou emissão fiscal real.

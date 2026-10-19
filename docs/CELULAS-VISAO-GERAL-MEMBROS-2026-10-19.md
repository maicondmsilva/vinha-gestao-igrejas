# Células: panorama e identidade dos membros

## Disponível nesta entrega

- Visão geral própria da Vinha: cartões, gráfico diário de encontros, comparação com o mês completo anterior, grupos da unidade e aviso de encontros passados ainda agendados.
- Contagens do banco, não somas limitadas à primeira página. Participantes contam pessoas distintas com vínculo ativo; grupos e vínculos representam a situação atual. Presença usa as chamadas congeladas dos encontros realizados no mês. Sem chamada, a taxa aparece como traço, não zero fictício.
- Diretório limitado a 100 grupos nesta visão; todos continuam acessíveis pela paginação do Cadastro. Atalho do grupo abre Encontros com o grupo selecionado. Relatório conserva o mês escolhido.
- Menu móvel recolhível, fechamento por Escape, foco contido e devolvido ao botão. Cartões adaptados à tela estreita, com identidade visual da Vinha, sem reaproveitar código ou ativos de concorrentes.
- Responsável/líder de Células: busca por nome no cadastro de membros da unidade, escolha explícita e chave `leader_person_id`. O banco valida a identidade e usa o nome cadastrado. Não concede papel, conta ou acesso.
- Nome manual continua aceito e identificado como sem vínculo. Alterar o texto limpa a seleção anterior. Não cria membro nem conta. Não associa cadastros antigos automaticamente por semelhança de nome.
- Consulta reutilizável `/api/member-choices`: somente identificador/nome, no máximo 30 resultados, mínimo de duas letras, sem contatos ou documentos. Respeita RLS, unidade, papel e módulo Pessoas.

## Compatibilidade e segurança

A nova listagem é `cell_directory_list_v2`; a listagem anterior permanece com o mesmo formato durante a troca de código. Escrita antiga sem identificador preserva vínculo existente apenas quando não altera o nome. O vínculo de membro é opcional, com chave estrangeira do mesmo ministério e índice. A gravação valida também a unidade real e a situação ativa do membro. Nomes históricos continuam sendo um retrato do nome na gravação; não são sincronizados silenciosamente por correspondência textual.

Sem leitura anônima, escrita direta, chave de serviço no navegador ou mudança de contrato. A visão geral e busca são funções invoker; a gravação atômica existente conserva validações, bloqueios, versão e auditoria. Novos campos não suspendem contas nem alteram planos. Não apagar tabelas ou históricos para reverter a interface.

Migração aplicada ao Supabase Vinha Igrejas com recibo `20261019205442`. Conferidas as três novas consultas invoker sem EXECUTE anônimo. Advisors mantiveram as mesmas categorias de avisos de segurança anteriores; o índice novo ainda sem uso é esperado antes do tráfego. Os avisos antigos não foram desativados ou contornados. Referências: https://supabase.com/docs/guides/database/database-linter e https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

## Homologação

233 testes de aplicação, tipagem, verificação estática de segredos e controle de botões. Suítes do banco: 29 cenários novos, além dos 29 do diretório e 43 de operação. Concorrência: três cenários do diretório e nove de operação nos níveis de isolamento já usados pelo projeto. Build Vercel/Nitro local aprovado; o artefato utiliza configuração Docker e não deve ser enviado como produção.

Interface homologada exclusivamente com ministério e conta fictícios no Docker: busca por digitação, escolha por setas/Enter, salvar e reabrir vínculo, alteração para nome manual, panorama com dois participantes/um encontro/100% de presença, navegação específica de grupo, relatório do mês anterior e menu em 390 × 844. Nenhum teste cadastral será criado no principal.

## Padrão para os demais módulos — ainda não concluído

O componente compartilhado já existe; somente o campo de líder de Células foi integrado ao armazenamento nesta entrega. Uma sugestão que copia texto não basta: cada formulário precisa de chave referencial, validação de unidade/ministério e teste de gravação. A incorporação nos demais módulos deve seguir sua migração, sem reativar rotas antigas.

1. Pessoas: contato de emergência com referência opcional a outro membro, mantendo telefone e indicação manual quando necessário.
2. Igrejas/unidades: responsável/pastor com referência opcional e regra explícita sobre vínculo entre unidades autorizadas.
3. Eventos: organizadores e convidados; pessoa vinculada ou convidado externo manual, sem criar conta.
4. Escalas/Louvor: participantes cadastrados para convites/confirmações; nomes externos informativos não recebem poderes ou notificações de usuário.
5. Famílias/Kids: responsáveis precisam de vínculo autorizado para ações de segurança. Nome livre nunca substitui autorização de retirada, consentimento ou identidade.
6. Financeiro: associação opcional de pessoa em lançamentos; pagador contratual continua separado e validado.

## Evolução de Células — fora desta entrega

Visitantes, indicações, redes, supervisão/hierarquia, múltiplos líderes, transferências com aceite, materiais e solicitações de relatórios por agenda habitual ainda precisam de fluxos próprios. O aviso de pendência atual se refere apenas a encontros já agendados e não atualizados, não à geração automática de relatórios faltantes. Não há métricas fictícias nem botões de ações indisponíveis.

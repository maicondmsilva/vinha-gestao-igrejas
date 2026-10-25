# Igreja acompanhada e vínculo oficial

A preferência de conteúdo é separada do cadastro de membro. O usuário autenticado e com e-mail confirmado escolhe qualquer igreja ativa do mesmo ministério e recebe somente publicações explicitamente públicas daquela igreja. A escolha persiste por conta/ministério; nunca é consultada pelas regras de autorização. Não copia grupos, escalas, permissões ou conteúdo privado. Sem publicação real, o aplicativo informa ausência de conteúdo, sem dados simulados.

Transferência exige ação explícita, tem uma solicitação pendente por conta/ministério e pode ser cancelada pelo próprio solicitante. A administração consulta e decide em Configurações → Usuários e permissões, com identidade confirmada e acesso de gestão nas duas igrejas. Não pode aprovar a própria solicitação. Aprovação valida novamente conta, vínculo de origem, destino ativo, suspensão e pendências cadastrais; aplica a mesma pessoa ao destino, atualiza a unidade padrão e registra auditoria. Recusa/cancelamento preservam o vínculo. Conteúdo acompanhado é independente da decisão.

Papéis não são promovidos; concessões explícitas não são copiadas nem alteradas. Usuários com cargo diferente de membro ou acesso de gestão específico exigem revisão separada antes da aprovação. O histórico de atividades permanece nas unidades originais; não há migração automática de grupos, funções, finanças ou responsabilidades Kids. As proteções de operações Kids existentes continuam valendo.

Publicações públicas são criadas e retiradas no mesmo espaço de configurações, por igreja, com aviso expresso de audiência pública. Tipos: aviso, agenda, vídeo e culto, com texto e link HTTPS opcional. Não se trata de sincronização automática dos módulos operacionais ainda não homologados.

Verificação local: 42 testes PostgreSQL/pgTAP, seis testes de rota/segurança, testes anteriores de cadastro/Android, tipagem web/Android e compilação web. Verificador de funções PostgreSQL sem erros nos esquemas private/member_app_api. Nenhuma alteração em membros reais durante os testes.

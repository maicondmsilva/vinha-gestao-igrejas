# Desenvolvimento dos módulos incompletos

Primeira entrega: relatórios cadastrais por unidade e situação. Apenas contagens, em uma consulta SQL consistente, sem dados pessoais, sem bypass de RLS e com validação dos módulos reports e people na unidade real. Acesso inicial para os papéis com leitura cadastral já autorizada; sem concessão para financeiro ou visitante.

Não inclui relatórios contábeis, exportações nominais, filtros históricos ou consolidação de filiais. O antigo AccountingCenter não é montado nesta entrega. Botão de atualização, carregamento, erro e descarte de respostas após troca de unidade implementados.

Validações: teste PostgreSQL transacional com dados fictícios e rollback, verificando outro ministério/unidade, ausência de unidade, ministério suspenso, contagem isolada e ausência de nomes. Testes da API para acesso negado, seleção inválida, erros genéricos e resposta privada. Sem alteração de dados existentes.

Sequência proposta após esta primeira entrega:

1. Células: cadastro, líderes e membros, encontros e presença; exclusão lógica e auditoria.
2. Escalas: equipes, disponibilidade, conflitos e confirmação; comunicação externa separada.
3. Eventos: programação, inscrição gratuita, capacidade e check-in; ingressos pagos somente após homologação do provedor.
4. Famílias e Kids: vínculos autorizados, consentimentos versionados, responsáveis, check-in/retirada segura e impressão.
5. Financeiro: concluir piloto, conciliação persistente, anexos privados e relatórios; validar integração de cobrança separadamente.
6. Comunicação, Louvor e Transmissões: permissões e migração de dados; integrações externas/licenciamento próprios.
7. Aplicativo: identidade visual, conciliação cadastral e aprovação, conteúdo segregado por unidade e publicação nas lojas.

Cada liberação limita-se ao escopo comprovado. Não liberar telas legadas ou prometer um módulo completo pela entrega parcial.

Estado: candidata local. A tentativa de instalar a função read-only em produção foi recusada pela revisão automática por falta de autorização específica para este relatório. A função não foi criada no principal; não promover o catálogo/tela antes da aplicação autorizada e verificação da função. A migração não altera registros de pessoas, mas cria uma RPC autenticada de agregação com RLS e controles de módulo/unidade. A validação visual autenticada permanece pendente.

Atualização após autorização específica: função instalada no projeto Vinha Igrejas, versão efetiva `20261019092730`. Verificado acesso anônimo negado, execução autenticada concedida e `security invoker` (sem bypass de RLS). O registro anterior descreve o bloqueio inicial, agora resolvido. A publicação da interface será registrada no PR 35 após implantação.

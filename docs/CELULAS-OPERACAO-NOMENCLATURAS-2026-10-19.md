# Células: operação e nomes do ministério

## Entrega

Complementa a primeira entrega de cadastro, sem reativar o legado. Submenu com Cadastro, Encontros, Participantes, Relatórios e Categorias. O botão genérico “Criar novo” saiu do cabeçalho; ações de cadastro permanecem nas páginas correspondentes.

Participantes são vinculados a Pessoas da mesma unidade. Inativação preserva o histórico. Encontros possuem data, horário, assunto, situação e chamada: o conjunto de participantes é congelado na criação; edições posteriores alteram somente as presenças desse conjunto. Encontros cancelados não compõem os indicadores. Relatórios consideram até 366 dias e mostram totais da página, não de todo o ministério. Categorias podem ser arquivadas sem apagar classificações anteriores.

## Personalização

A engrenagem dos títulos permite a proprietários e administradores alterar os nomes exibidos dos módulos. Em Células também permite singular, plural, páginas e termos de responsável/local. As alterações são do ministério inteiro, compartilhadas entre suas unidades e usuários. Outras sessões atualizam ao recuperar o foco ou em até aproximadamente 15 segundos quando visíveis.

Não altera endereços, identificadores, papéis, módulos contratados ou preços. Restaurar padrões afeta apenas o módulo aberto. Alterações simultâneas usam versão e recusam sobreposição.

## Segurança e limites

- Organização vem da sessão verificada; unidade explícita inválida nunca é substituída pela sede.
- As operações respeitam o contrato e a unidade real. Participantes, encontros e relatórios exigem também Pessoas disponível. Categorias exigem Células.
- Proprietário, administrador e pastor gerenciam; líder precisa de gestão na unidade. Secretaria autorizada consulta. O banco revalida acesso em cada gravação.
- Tabelas têm RLS e clientes não gravam diretamente. Funções de gravação fazem validação explícita, bloqueios, controle de versão e auditoria atômica. Nenhuma função de escrita é concedida a visitantes.
- Busca de pessoas retorna somente identificador e nome. Respostas privadas não usam cache compartilhado.
- Não há exclusão física pelo cliente, envio de mensagens ou alteração comercial automática.

## Verificação

225 testes de aplicação aprovados; 43 verificações pgTAP aprovadas com rollback; nove cenários concorrentes aprovados nos três níveis de isolamento. Tipagem, busca estática de segredos, controle de botões e build Vercel/Nitro aprovados localmente.

Homologação visual com cadastros fictícios exclusivamente no Docker: categorias, classificação, vínculo de duas pessoas, encontro, edição da chamada, relatório 50% e depois 100%, nomes compartilhados, navegação entre páginas preservando a unidade e isolamento de campus. Nenhum cadastro fictício foi criado no banco principal.

## Publicação e recuperação

Aplicar a migração aditiva antes do código, conferir permissões e aguardar CI e Vercel. Não publicar o artefato local construído com configuração de Docker. Preview em nuvem não deve usar o banco principal para contornar a falta de homologação isolada.

Em regressão, reverter seletivamente a interface/código, preservando tabelas, registros e auditoria. Não remover dados para desfazer a publicação. Contratos existentes não serão ampliados automaticamente.

Supervisão, multiplicação e vínculo do responsável como líder formal continuam fora desta entrega.

Conferência de desempenho complementou os índices das cinco relações compostas novas (recibo `20261019180429`), validados no Docker antes da aplicação. Índices novos ainda sem uso não devem ser removidos apenas por falta de tráfego.

Estrutura aplicada ao Supabase Vinha Igrejas, recibo `20261019180052`. Conferidos RLS nas seis tabelas, ausência de leitura anônima e ausência de escrita direta autenticada. Os dois novos avisos de função privilegiada autenticada são esperados para as gravações validadas; nenhum EXECUTE anônimo foi concedido. Alertas anteriores sobre senhas comprometidas e funções antigas permanecem fora desta entrega. Referência: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

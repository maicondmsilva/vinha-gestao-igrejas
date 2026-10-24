# Kids K1 — cadastro integrado e fundação web

Data de referência: 23/10/2026, America/Sao_Paulo.

## Entrega

O painel `pagina=kids` passa a montar `KidsFoundation`, sem executar KidsArea/KidsTools legados. O aplicativo nativo foi explicitamente adiado. As interfaces de backend poderão ser aproveitadas no futuro, mas não foi criado projeto Android/iOS.

- Perfil complementar vinculado obrigatoriamente a Pessoas. Nome e nascimento não são duplicados; a numeração principal de membros permanece válida.
- Busca mínima de pessoas da unidade, incluindo pendentes. Cadastro rápido com nascimento obrigatório cria visitante pendente, sem criar usuário, associar conta ou promover à jornada Membro.
- Homônimos exigem conferência em Pessoas, nunca fusão automática. Nome exatamente igual no cadastro rápido é recusado para evitar duplicação inadvertida.
- Fila paginada de pessoas pendentes, aprovação administrativa e revisão Kids separadas.
- Responsáveis vinculados a Pessoas: parentesco informado separado de permissão de retirada, atualização cadastral e contato de emergência. Nenhum desses campos concede automaticamente acesso digital ou comprova guarda legal.
- Autorizações pendentes/aprovadas/revogadas, validade e origem da conferência. Aprovação exige adulto com nascimento informado e pessoa ativa. Expiração, revogação, inativação ou transferência deixam de contar como autorização vigente.
- Arquivamento/reativação do perfil sem excluir vínculos/histórico.
- Cuidados restritos com origem da informação. Conteúdo sensível não é copiado para o histórico geral.
- Histórico com ator, data, ação e campos tratados. Os campos registrados são os enviados à operação, não uma reconstrução de valores anteriores/posteriores.
- Paginação, busca literal, controle de versão, reenvios idempotentes, mensagens sem SQL e formulários responsivos acessíveis.

## Permissões iniciais

Todos os acessos exigem conta atual confirmada, participação ativa, ministério/unidade ativos, escopo autorizado e módulos Kids/Pessoas habilitados pela regra contratual existente. Não foi alterada a compatibilidade já estabelecida para contrato ausente/rascunho.

| Papel | Consulta | Cadastro/vínculo | Aprovação | Cuidados |
| --- | --- | --- | --- | --- |
| Proprietário, administrador, pastor | Conforme escopo | Conforme escopo | Sim | Sim |
| Secretaria com gestão da unidade | Sim | Sim, sem autoaprovar | Não; pode revogar | Não |
| Secretaria somente leitura | Sim | Não | Não | Não |
| Financeiro, líder, membro, visualizador | Não | Não | Não | Não |

Recepção/professor/supervisor terão permissões específicas junto das salas/equipe; este K1 não lhes concede acesso geral à saúde. Ser pai/mãe, pessoa cadastrada ou portar um identificador não concede acesso à API.

## Arquitetura

Migração `20261024024447_kids_identity_foundation.sql`: identificador UTC realmente registrado na aplicação pelo Supabase; entrega em 23/10 no horário local. O arquivo inicialmente preparado pela CLI (`20261024020252`) foi renomeado para corresponder ao registro aplicado, sem modificar o histórico do banco ou reaplicar a estrutura.

Tabelas privadas com RLS e sem privilégios diretos de visitantes/autenticados/serviço: `kids_profiles`, `kids_guardians`, `kids_care`, `kids_history`, `kids_requests`. Implementação privilegiada fica no esquema privado com autenticação/autorização explícitas. Interfaces públicas são invocadoras; a API deriva o ministério da sessão, não do navegador.

Gravações bloqueiam as linhas de identidade, participação, unidade e contrato antes de revalidar acesso. Edições exigem versão esperada; reenvios usam chave da operação e impressão digital do conteúdo. Não há user_metadata como permissão, chave de serviço no navegador ou exclusão física pelo Kids.

Retenção, base legal e atendimento a direitos precisam seguir a política aplicável à igreja. A entrega não é certificação jurídica. Não há biometria, reconhecimento facial ou compartilhamento entre ministérios.

## Inventário e eventual migração

Consulta somente de estrutura na conexão Vinha Igrejas, projeto `aoxibaaydfgffrdqtkva`: a pesquisa de tabelas públicas/privadas por kids/child/guardian ou people/person_consents retornou apenas `public.people` e `public.person_consents`, ambas com RLS. Isso não demonstra inexistência de dados infantis em outras estruturas ou no antigo D1.

Rotas antigas de children/kids, etiquetas e verificação continuam contidas. Nenhum registro legado foi apagado ou associado automaticamente.

Mapa de eventual carga: criança antiga → Pessoa conferida por unidade/nome/nascimento; responsável → adulto conferido; autorização antiga → pendente, não aprovada por importação; saúde → revisão de finalidade/origem e armazenamento restrito; conflitos → relatório restrito de pendências. Extração e conferência da fonte antiga ainda são necessárias se houver dados reais a importar; não foi criado importador que associe pessoas às cegas.

## Verificações

- TypeScript do núcleo e 96 testes JS selecionados (incluem 8 Kids).
- 59 verificações SQL Kids com pessoas fictícias e rollback: isolamento, papéis, revisões, cuidados, revogação, validade, transferência, contrato e suspensão.
- 5 cenários concorrentes: edição nos três níveis de isolamento; reenvio sem duplicação; suspensão durante gravação.
- Diagnóstico de segurança local do Supabase: sem alertas na execução.
- Build Vercel completo aprovado com acesso aos arquivos locais de dependências. A primeira tentativa restrita encontrou EPERM do Windows no empacotamento; não foi reduzida nenhuma proteção da aplicação.
- Interface homologada com organização/pessoas fictícias: responsáveis, aprovação, cuidados e cadastro rápido. Foi corrigida uma data incompleta observada no teste, com validação obrigatória também no domínio e banco.

Testes: `node scripts/local-kids-k1-test.mjs --local-synthetic`, `node scripts/kids-foundation-concurrency.mjs --local-synthetic`, `node --experimental-strip-types --test scripts/kids-foundation.test.mjs`. Scripts de banco fixados ao Docker local, sem argumento de URL/credencial externa.

## Fora do K1

Entrada/entrega física, turmas/salas/capacidade, equipe operacional, QR, etiquetas/impressoras, materiais, notificações, relatórios operacionais e contingência presencial. As operações antigas não foram reativadas. Aplicativos nativos ficam para outro momento.

Homologação local não comprova publicação: implantação e conferência do banco principal devem constar no recibo da entrega.

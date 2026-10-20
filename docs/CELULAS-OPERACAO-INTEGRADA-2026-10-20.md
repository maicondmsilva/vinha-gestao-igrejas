# Células — operação interna integrada

## Liberação e limites

Esta entrega conclui o escopo **interno por unidade** descrito abaixo, sujeito à aprovação dos testes e publicação. Não declara toda a Vinha concluída. Outros módulos e as proteções de funções antigas permanecem como estavam.

As cinco novas páginas ficam no submenu de Células e seus nomes são personalizáveis na engrenagem para todo o ministério. O cadastro de pessoas é reutilizado: escrever um nome manual não cria membro, usuário ou acesso.

| Página | Uso |
| --- | --- |
| Indicações | Indicar pessoa a um grupo, conciliar com membro existente e aceitar ou recusar |
| Materiais e estudos | Escrever estudos, adicionar links HTTPS e controlar rascunho/publicação/arquivamento |
| Indicadores por rede | Consolidar grupos de uma rede e seus descendentes, com período e exportação CSV da página |
| Pendências e avisos | Consultar agendamentos vencidos sem relatório, notificar internamente e acompanhar leitura |
| Supervisão e acesso | Conceder/revogar capacidades por rede e consultar/preencher chamadas autorizadas |

Fora desta liberação: e-mail/WhatsApp/push externos, arquivos hospedados ou upload de PDF, compartilhamento entre unidades, organograma de contas, histórico da posição antiga de um grupo na rede e exigência de relatório para datas sem encontro agendado. Um link externo pode apontar para um arquivo, mas o arquivo não é copiado nem hospedado pela Vinha.

## 1. Indicações

Gestores da unidade podem indicar uma pessoa por busca no cadastro ou por nome manual. A escolha de um membro armazena a identidade e o nome canônico. Para aceitar uma indicação manual, primeiro “Vincular ou corrigir pessoa” e selecionar um cadastro ativo da mesma unidade. O aceite cria ou reativa a participação naquele grupo, sem duplicar a pessoa. Recusa encerra a indicação sem criar vínculo.

Identidade do grupo e decisões encerradas não são reescritas. A versão protege alterações concorrentes e o banco impede duas indicações pendentes do mesmo membro no mesmo grupo. Repetir uma decisão com versão antiga é recusado; atualizar a tela antes de repetir. A participação não implica exclusividade: uma pessoa pode participar de outros grupos conforme as regras anteriores.

## 2. Estudos

Gestores cadastram título, texto de até 16 mil caracteres e link HTTPS opcional, para toda a unidade ou uma rede. Rascunhos e arquivados ficam somente para gestores. Supervisores consultam os publicados dentro de sua autorização; materiais gerais da unidade ficam disponíveis aos supervisores ativos daquela unidade. O filtro de materiais usa a rede exata e os materiais gerais, não uma reprodução histórica da árvore.

Textos são exibidos como texto, não HTML executável. Links abrem em outra aba com isolamento; a aplicação não busca nem executa conteúdo do endereço. Não guardar senhas ou dados sensíveis no estudo ou URL.

## 3. Indicadores

Selecionar uma rede considera os grupos atualmente associados a ela e aos descendentes (até 32 níveis). Sem seleção, considera todo o escopo atualmente autorizado. Os totais não são limitados à página exibida. “Participantes distintos” conta identidades com vínculo ativo agora, evitando somar a mesma pessoa duas vezes em grupos diferentes. Encontros realizados e presenças usam as chamadas registradas no período. Transferências posteriores não mudam essas chamadas. Grupos arquivados continuam no histórico consultável pelos gestores.

O período admite até 366 dias. CSV exporta **a página atual**, com neutralização de fórmulas em nomes; navegar para obter outras páginas. A coluna da rede reflete a associação atual, não uma atribuição histórica no dia do encontro. Opções e escopo de uma consulta são limitados a dois mil grupos/redes; exceder esse limite retorna falha explícita, não totais parciais.

## 4. Pendências e notificações internas

Pendente é um encontro de grupo ativo, agendado para uma data passada em São Paulo e ainda não realizado/cancelado. Não são gerados agendamentos ou faltas imaginárias a partir do dia habitual. A página atualiza a cada 30 segundos enquanto visível, sem interromper edições/decisões.

“Notificar responsáveis na Vinha” cria avisos internos para contas ativas vinculadas ao responsável do grupo ou à supervisão aplicável. A conta precisa continuar autorizada à unidade e ao grupo. Não usa e-mail/telefone escrito manualmente. Uma notificação por encontro/destinatário evita duplicatas. O destinatário pode marcar somente a própria leitura. Ao realizar ou cancelar o encontro, ele deixa as pendências atuais; o histórico de avisos permanece.

Sem destinatário válido, a resposta informa zero novas notificações; não afirma envio. Não há e-mail, WhatsApp ou push nesta operação. SMTP de autenticação do Supabase não é um serviço transacional automaticamente disponível ao módulo.

A rotina diária existente `/api/platform/lifecycle/run` foi estendida para chamar `cell_report_reminder_batch` antes dos processos existentes, sem modificar sua autenticação por `CRON_SECRET`. O cron existente está em `0 11 * * *` (08h de São Paulo). O cliente nunca pode executar a varredura global: só o serviço pode. Lotes de cem, até dez por execução, usam checkpoint persistido para continuar o ciclo no próximo agendamento, sem ficar preso aos primeiros mil encontros. O cursor zera ao terminar o ciclo. Repetir o lote não duplica avisos. Uma rotina sem execução/configuração de cron não deve ser descrita como entrega automática homologada em produção.

## 5. Supervisão

Proprietário, administrador ou pastor com gestão da unidade podem conceder a um membro **já vinculado a uma conta ativa e autorizada à unidade** uma capacidade para uma rede e seus descendentes ativos:

- Consulta: indicadores, indicações, estudos publicados e chamadas daquele escopo.
- Acompanhamento: consulta e notificação de pendências internas.
- Registro de relatórios: acompanhamento e preenchimento/correção de presença na chamada já existente.

Não cria conta, não concede acesso inicial à unidade e não altera o papel geral. Permissões gerais anteriores continuam válidas — uma concessão restrita não reduz os direitos de quem já gerenciava toda a unidade. Supervisores não publicam estudos, aceitam indicações, alteram concessões, cadastram membros, criam encontros, mudam datas, cancelam agendamentos ou obtêm dados financeiros por esta permissão.

Concessões têm destinatário/rede imutáveis. Para trocar a pessoa, revogar a antiga e criar outra. Apenas indicar o responsável informativo da rede não concede direitos. Revogação, suspensão de conta, troca de vínculo de grupo, movimentação da árvore, arquivamento e perda do vínculo ativo de pessoa/conta são revalidados. A concessão não abre os diretórios gerais antigos para membros/viewers.

## Segurança e validação

Migração `20261020091234_cell_integrated_operations.sql`: tabelas internas no esquema privado com RLS de negação e sem acesso direto de clientes; interfaces públicas invoker; execução privilegiada no privado, com validação explícita de unidade, identidade, papel, capacidade, módulo e estado. A rotina de serviço tem execução negada a clientes e anônimos. Não há novas concessões, indicações ou mensagens para clientes reais na migração.

Comandos usam versões e travas de estado e da hierarquia. O registro delegado trava o vínculo de rede do grupo, além do grupo e encontro, para detectar troca concorrente inclusive em snapshots antigos. Audita IDs, transições e contagens, sem copiar texto de estudos, nomes, contatos ou credenciais para a auditoria. APIs usam organização validada da sessão, formato estrito, corpo limitado e `no-store`.

Evidências da entrega: testes de aplicação, SQL transacional de integração, concorrência em read committed/repeatable read/serializable, regressão dos módulos anteriores, build e homologação visual local. A homologação visual usa gestor fictício; as diferenças entre papéis e revogações são verificadas no banco com contas fictícias e nas rotas. Produção deve ser conferida somente por leitura e abertura/cancelamento de formulários, sem cadastro de teste nem envio externo.

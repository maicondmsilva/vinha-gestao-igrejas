# Células — registro de visitas

## Entrega

Submenu Visitantes com nome personalizável para todo o ministério. Consulta por unidade, grupo e período (até 366 dias), com paginação por chave de cem registros. Uma linha é uma visita, não um visitante único. O resumo mensal de Células não foi alterado e não inclui este novo indicador nesta entrega.

Para registrar, selecionar um grupo ativo; informar a data e procurar um membro pelo nome ou manter um nome manual, sem vínculo. A seleção explícita guarda `person_id`; o banco valida o membro ativo na mesma unidade e usa seu nome cadastrado. Alterar o texto limpa o vínculo. Não há conciliação textual automática, cadastro de membro, conta, concessão de acesso, contato ou envio de mensagens. Não são coletados telefone, documento ou observações sensíveis.

Editar permite corrigir nome/data e cancelar ou reativar uma visita, sem exclusão física. A versão evita sobrescrever alterações simultâneas; as gravações têm auditoria atômica sem copiar nomes. Repetição idêntica da gravação usa o mesmo identificador. Um membro vinculado não pode ter duas visitas registradas no mesmo grupo e dia. Nomes manuais não permitem deduplicação segura. Não há alteração de chamada ou participação por registrar uma visita. Grupos arquivados são somente consulta; membros inativos não podem ser selecionados em gravações.

## Acesso

Somente os papéis já autorizados a ler Células/Pessoas podem consultar, na unidade autorizada e com os dois módulos habilitados. Gravação exige papel de proprietário, administrador, pastor ou líder, com gestão da unidade, conta confirmada e ministério/unidade ativos. A função auditada trava estados de acesso, contrato, grupo e pessoa durante a operação. Não altera planos ou poderes existentes. Nenhuma escrita direta ou execução anônima é concedida. Consultas públicas invoker com RLS; escrita pública invoker delega à implementação definer no esquema privado não exposto pela API, com autorização explícita, `search_path` vazio e privilégios restritos.

Migração: `20261019212302_cell_visits.sql`. Índices cobrem paginação, chaves estrangeiras e duplicidade de membro por dia/grupo. API usa ministério da sessão, JSON limitado a 8 KiB, validação estrita de campos e resposta, sem cache compartilhado ou mensagens SQL ao usuário.

## Validações

- 240 testes de aplicação aprovados, incluindo sete novos de contratos/rotas de visitas; tipagem, verificação de segredos e botões aprovadas.
- 31 testes pgTAP novos aprovados no Docker: acesso, isolamento, nome canônico/manual, datas, deduplicação, versões, cancelamento, auditoria, paginação e bloqueio dos módulos.
- Nove cenários concorrentes aprovados: edição simultânea, duplicidade e suspensão versus gravação em read committed, repeatable read e serializable. Fixtures exclusivamente no container `supabase_db_vinha`.
- Compilação Vercel/Nitro aprovada com configuração local; esse artefato não deve ser publicado. Produção deve compilar o código pelo GitHub/Vercel.
- Interface com conta fictícia local: seleção por teclado, gravação, reabertura do vínculo, alteração para nome manual e cancelamento. Formulário conferido em 390 × 844, sem gravações de teste no principal.
- A suíte geral no Docker atual apontou duas estruturas antigas ausentes (`people_summary_report` e `saas_plan_adjustments`); as suítes de Células passaram. Conferir todas as migrações no banco limpo do CI antes de promover, sem resetar o Docker que contém as fixtures locais do usuário.

## Ainda fora desta entrega

Indicações, integração de visitantes na chamada de encontros, conversão acompanhada para membro, métricas de visitantes únicos, redes, supervisão/hierarquia, múltiplos líderes, transferências com aceite, materiais e cobranças de relatórios. A busca referencial nos demais módulos também continua pendente.

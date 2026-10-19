# Células — primeira entrega

## Escopo

Diretório por unidade no Supabase principal: criar, listar, editar, arquivar e reativar. Não é a conclusão de todo o módulo. Encontros, participantes, presença, multiplicação, supervisão e vínculo do líder com Pessoas ainda não fazem parte desta entrega. O responsável informado é somente texto cadastral e não cria uma conta nem concede permissões.

O legado `/api/cells` continua bloqueado. A nova interface usa `/api/cell-directory`, sem dependência do banco antigo e sem reativar operações antigas.

## Uso

1. No painel da igreja, selecionar a unidade e abrir Células.
2. Usar Nova célula; informar nome, responsável opcional, dia, horário, formato e local/orientação opcional.
3. Salvar. Para alterar dados ou situação, usar Editar célula e situação.
4. Arquivar preserva o registro; reativar reutiliza o mesmo identificador. Não há exclusão física pelo cliente.
5. A lista usa páginas de até 100 registros; Próxima página e Voltar ao início navegam sem carregar toda a organização.

## Acesso e proteção

- Exige conta autenticada, participação ativa, unidade real ativa e ministério ativo/em demonstração.
- Respeita o módulo `cells` no contrato da unidade alvo. Nenhum plano, preço ou contrato de cliente é alterado nesta entrega. A compatibilidade existente para contrato ausente/rascunho permanece.
- Proprietário, administrador e pastor podem gerenciar; líder depende de concessão de gestão/administração na unidade. Secretaria tem consulta com concessão de leitura. Outros papéis são recusados.
- Todas as gravações revalidam o e-mail confirmado e o acesso no banco. Bloqueios transacionais protegem a checagem de estado/participação/contrato; edição usa versão para recusar sobreposição de alterações.
- A tabela tem RLS e clientes possuem somente SELECT. Gravação ocorre exclusivamente pela função validada e auditada; a função privilegiada tem caminho de busca vazio e não aceita identidade, organização ou unidade dentro dos campos livres.
- Repetir a criação com o mesmo identificador, autor e conteúdo normalizado não duplica o registro nem a auditoria. Repetir uma edição já aplicada retorna conflito; atualizar a lista antes de tentar novamente.
- Auditoria atômica registra ação, unidade, identificador, versão e situação, sem copiar nomes ou endereço para os metadados.
- Dados e respostas privados não podem ser armazenados em cache compartilhado. A troca de unidade cancela consultas pendentes e fecha o formulário.

## Homologação e publicação

- 213 testes de aplicação, tipagem, verificação estática de segredos, controles de botões e build Vercel passaram localmente.
- Testes pgTAP em Docker isolado verificam permissões, separação por unidade/ministério, repetição, versão, arquivamento/reativação, contrato e auditoria.
- 29 asserções pgTAP passaram. Edições simultâneas passaram em READ COMMITTED, REPEATABLE READ e SERIALIZABLE, sem sobrescrever a versão aceita nem auditar a rejeitada.
- Interface homologada com usuário e ministério fictícios locais: criar, editar, arquivar, reativar e trocar a unidade. Nenhum cadastro fictício foi criado em produção.
- Publicação solicitada expressamente pelo usuário. Banco deve ser aplicado antes do código; aguardar CI e implantação de produção confirmados. Prévia em nuvem permanece isolada: não apontar Preview para o banco de produção.
- Estrutura aplicada ao projeto Vinha Igrejas com recibo 20261019094950. Conferidos RLS ativo, acesso anônimo negado e ausência de gravação/exclusão direta por clientes. Nenhum registro fictício no principal. Contratos ativos existentes não incluem Células; liberação comercial pela Central continua necessária e não foi feita automaticamente.
- Reversão de interface: retirar apenas `celulas` do piloto ou retornar ao código anterior. Preservar a tabela e auditoria; não remover dados para reverter esta entrega.

## Próximas entregas do módulo

Vínculo do líder e participantes com Pessoas, encontros e presenças com isolamento e auditoria; depois supervisão, multiplicação, indicadores e acompanhamento pastoral com minimização de dados pessoais.

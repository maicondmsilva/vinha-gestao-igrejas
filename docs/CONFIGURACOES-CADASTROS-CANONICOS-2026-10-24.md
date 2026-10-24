# Configurações e cadastros independentes

Implementação local em 24/10/2026. Não constitui publicação, homologação do aplicativo nativo ou conclusão integral do plano.

## Regra cadastral

O ministério contratado possui identidade institucional em `organizations`. Cada igreja ou unidade possui seu próprio registro em `organization_units`, incluindo nome, código, razão social, CNPJ, responsável, e-mail, telefone e endereço completo. Não há cópia automática desses campos entre igrejas. A edição de uma unidade não modifica sua hierarquia, autonomia, contrato ou permissões.

Logotipos são armazenados em `private.church_branding`, associados ao ministério ou à igreja específica. Não são aceitos URLs remotos ou SVG. O painel e as exportações financeiras consultam a fonte canônica: igreja selecionada, depois ministério, depois identidade Vinha. Consolidações usam a marca institucional do ministério. A identificação Vinha permanece no rodapé dos relatórios. Os dados cadastrais continuam nas mesmas tabelas consultadas pela Central; não existe sincronização por cópias ou rotinas paralelas. Não foi acrescentada uma tela de prévia da logo na Central.

## Fluxos reais implementados

- Configurações reúne Identidade e cadastro, Igrejas e unidades, Usuários e permissões e Serviços e segurança. URLs antigas de usuários e igrejas continuam abrindo as seções correspondentes.
- Formulários institucionais salvam no banco, com controle de versão por data de atualização. Conflitos exigem recarregar; erros de conexão não são apresentados como sucesso.
- Igrejas existentes permitem editar seus dados próprios e o endereço completo. A criação reutiliza o fluxo existente; o endereço detalhado e a logo podem ser completados após criar.
- A logo pode ser informada na configuração inicial ou posteriormente. O cadastro inicial e a logo são gravados na mesma transação.
- Nome, cores e identidade do cabeçalho são atualizados após salvar. Usuários e permissões reutilizam a governança existente, sem conceder privilégios novos.
- PDFs e planilhas financeiras usam a marca persistida em vez de uma seleção temporária por sessão.

## Segurança

Gravação restrita a proprietário, administrador e pastor geral, com conta confirmada, vínculo ativo e organização ativa/em teste. A camada pública é invocadora; a implementação privada verifica a autorização no banco, bloqueia os registros durante a gravação e registra auditoria na mesma transação. Não permite alterar código, assinatura, status, hierarquia ou campos desconhecidos. Imagens não são copiadas para a auditoria. O armazenamento privado não possui acesso direto por clientes.

## Verificação realizada

- 36 verificações SQL específicas, incluindo independência de igrejas do mesmo ministério, isolamento de outro ministério, suspensão, leitor sem escrita, conta não confirmada, conflito, logo inválida e auditoria.
- Regressão geral local inicial: 45 arquivos e 2.130 testes aprovados, antes dos oito testes adicionais de independência cadastral. Os 36 testes específicos foram reexecutados com sucesso após a inclusão.
- 34 testes de rota, exportação e interface aprovados. Outros 76 testes de segurança e quatro de contenção aprovados.
- Verificações de tipos do núcleo, segredos, controles interativos e compilação Vercel aprovadas durante a implementação.
- Navegador local: cadastro institucional salvo, cadastro de igreja salvo, endereço persistido após recarregar, seções dentro de Configurações e formulário a 390 × 844 sem transbordamento horizontal.
- Apenas dados fictícios foram alterados no ambiente local. Nenhum cadastro de cliente foi alterado para testes.

Evidência visual: `evidencias/configuracoes-cadastros-independentes-local-20261024.png`.

## Situação do restante do plano

A unificação completa do autoatendimento do membro, revisão de alterações por campo, reconciliação segura de pessoas/contas e integrações do aplicativo ainda precisa de implementação e homologação próprias. Google/Apple, notificações e publicação nas lojas dependem de configuração externa. O projeto nativo não está presente neste repositório. A operação Kids K2 anterior foi preservada em arquivos locais, mas não é montada pelo painel nem declarada publicada nesta entrega. Não foram ativados endpoints legados contidos.

Antes da publicação destas mudanças: conferir o conjunto de arquivos sem incluir K2 pendente, executar CI sobre esse conjunto exato, revisar a migração e aplicar pelo fluxo de migrações autorizado. Não reescrever o histórico do banco nem publicar todo o diretório de trabalho indiscriminadamente.

# Execução do plano de lançamento — L0, bloco 1

Data: 15/10/2026. Base: 2c0dafe55c2221bbcc88b2d7c9633dd5fbc53a7f.

## Resultado e limites

Implementado o primeiro bloco de contenção. **Não é autorização para lançamento comercial nem conclusão de todo o plano.**

O núcleo cadastral continua em validação. Nenhuma funcionalidade passou a ser considerada pronta por estar visível, contratada ou habilitada no banco. Esta alteração não migra tabelas nem modifica registros de clientes.

## Entregas

1. Catálogo versionado em app/lib/release-availability.ts: visão geral, pessoas, unidades e configurações limitadas são classificados como núcleo em validação; os demais módulos permanecem em desenvolvimento.
2. Contenção no servidor em 50 rotas exclusivamente legadas, abrangendo 91 métodos HTTP. Resposta 503, código FEATURE_NOT_RELEASED, Cache-Control no-store. O código antigo é preservado, mas não é executado pelos métodos exportados.
3. Não há variável de ambiente, ajuste no navegador ou alteração de plano para contornar a contenção. Cada reabertura exige migração e revisão de código.
4. Painel: módulos não liberados não montam suas interfaces antigas. Exibem explicação em vez de permitir gravações demonstrativas em memória.
5. Doze grupos de páginas diretas receberam contenção: chat de membros, notificações, voluntários, escalas, eventos, convites locais antigos, vínculos, testes de termos, importação, notificações/configuração de equipe e suporte legado. O atendimento Supabase pelo widget é preservado; o portal de chamados antigo é substituído por orientação para esse chat.
6. Configurações: retiradas da navegação as telas com confirmação de salvamento somente visual e indicadores fictícios. Disponíveis os links para contratos/solicitações, segurança da própria conta e atendimento, além do catálogo operacional.
7. Apresentação pública: identifica pré-lançamento, núcleo em validação, aplicativo futuro e ilustração com dados fictícios. Não promete plataforma completa, publicação nas lojas ou validação de backups já concluída.
8. Quatro testes de contenção adicionados à automação do GitHub.

## Preservado

- Rotas Supabase da Central, ativação comercial em /ativar, cadastro e autenticação.
- API de onboarding, contratos da unidade, atendimento por setor e segurança da própria conta.
- Adaptadores Supabase existentes de pessoas e unidades. Seu caminho legado residual ainda exige remoção na L2.
- Bloqueios de operações financeiras reais: nenhuma cobrança, nota, mensagem ou pagamento foi criado como teste.
- Dados existentes, políticas de banco e arquivos de clientes, sem exclusão.

Convites locais antigos em /convite são diferentes da ativação comercial em /ativar e do convite de operador em /central-vinha/convite. Os dois últimos não foram bloqueados.

## Validações

- 14 testes existentes de faturamento/integrações: aprovados.
- 4 testes novos: catálogo desconhecido bloqueado; código legado nunca executado; cobertura AST dos 50 arquivos/91 métodos e resolução de imports; páginas diretas/painel protegidos.
- Verificador de botões: 49 controles legados, sem aumento. Isso **não** significa que todos os botões funcionam.
- Verificação TypeScript: 318 diagnósticos, mesma contagem da auditoria inicial. Não é um check aprovado.
- Build Vercel: aprovado após repetir fora da restrição local de arquivos do Windows. A tentativa restrita falhou com EPERM na montagem de dependências, não na compilação das alterações.
- HTTP local: GET /api/events retorna 503 FEATURE_NOT_RELEASED com no-store.
- Navegador local: apresentação de pré-lançamento renderizada; /eventos/exemplo mostra a contenção em vez da página antiga.
- Não foi validada nesta etapa uma sessão autenticada de cliente. Não foram realizados testes de isolamento no banco ao vivo, restauração, SMTP ou entrega real de mensagens.

O estado de publicação deve ser confirmado pelo commit, revisão e deploy vinculados à entrega. Build local não equivale a deploy.

## Próximo bloco — L1, segurança do núcleo

1. Triar os avisos de dependências conforme o uso real com Vinext/Vercel; atualizar com testes, sem correção forçada indiscriminada.
2. Remover fallback de identidade/banco antigo do núcleo e revisar autorização por organização, função e unidade.
3. Testar isolamento com pelo menos duas organizações e usuários com acessos diferentes, em ambiente de teste.
4. Revisar cache privado, proteção de escritas, cabeçalhos e mensagens de erro.
5. Reduzir os erros de tipos e tornar as verificações relevantes obrigatórias antes de publicação.
6. Configurar SMTP de domínio próprio quando o responsável fornecer o serviço; validar confirmação/retorno com conta de teste autorizada.

Depois: L2 migração do núcleo, L3 recuperação/monitoramento e aprovação do piloto. Financeiro de igreja, Kids, integrações e apps seguem suas fases próprias.

## Critérios para retirar uma contenção

- Dados persistidos no Supabase; nenhuma dependência operacional de D1.
- Autenticação e autorização de todas as leituras/escritas/arquivos, inclusive por unidade.
- Testes negativos entre organizações e unidades.
- Jornada completa aprovada, sem sucesso fictício, com tratamento de erro e repetição segura.
- Disponibilidade consistente entre catálogo, painel, API e oferta comercial.
- Integrações externas homologadas e contratos/licenças atendidos quando necessários.

## Recuperação e operação

Este bloco não exige migração ou reversão de dados. Em regressão, corrigir ou reverter de forma seletiva a interface afetada, preservando os bloqueios de segurança. Não reabrir endpoints antigos por ajuste de plano ou retorno indiscriminado à versão anterior. Webhooks antigos de pagamentos retornam 503, não confirmação falsa de processamento; qualquer integração legada contratada deve ser revisada antes de reativação.

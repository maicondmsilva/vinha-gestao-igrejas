# L1 — bloco 1: acessos, navegação e proteções de resposta

Data: 15/10/2026. Base de implementação: f59685ce91cf4d1ac708761e65b86e1e21dd4a03.

## Escopo e decisão de lançamento

Primeiro bloco da L1, não conclusão da fase de segurança. A Vinha permanece em pré-lançamento. Não libera o piloto, financeiro real, módulos contidos na L0 ou aplicativos nas lojas.

Não houve alteração de esquema, políticas RLS, registros, credenciais ou fatores de autenticação. Não foram enviados e-mails/WhatsApp, cobranças ou documentos fiscais como teste.

## Alterações

### Identidade do servidor

- sessionFrom e platformSessionFrom não aceitam mais identificação por cabeçalhos oai-authenticated-user-* nem consultam a identidade antiga quando Supabase não está configurado.
- Removida a criação automática do primeiro operador proprietário na autenticação antiga.
- Na falta da configuração, a autenticação nega acesso; não tenta recuperar privilégios por outro banco.
- A validação da Central exige getUser sem erro, contexto único de operador obtido do banco, papel conhecido e AAL2 confirmado sem erro.
- Proprietário e administrador continuam autorizados às escritas genéricas. Suporte e somente leitura não ganham novas permissões. APIs especializadas do chat mantêm seus controles próprios.
- Os nomes em user_metadata continuam apenas como apresentação, não como fonte de papel/permissão.

### Seleção de organização

- Sessão de igreja e autorização do núcleo passam a usar a mesma política de seleção.
- Vínculo suspenso/inativo não é selecionável.
- Um identificador explícito não autorizado não recai na primeira igreja.
- Preferência inválida não seleciona silenciosamente outra igreja.
- Havendo mais de uma organização e nenhuma seleção válida, o acesso é negado até selecionar o ambiente em /acesso.

Isso é uma proteção da seleção do contexto, **não prova de isolamento por unidade ou de todas as políticas do banco**.

### Origem das escritas com sessão

Os autenticadores compartilhados e authorizeSupabaseChurch exigem origem exatamente igual à da requisição em operações de escrita. Origem ausente, diferente ou Sec-Fetch-Site cross-site são recusados. Cabeçalhos de host encaminhado não concedem confiança. Leituras continuam exigindo autenticação/autorização nos respectivos endpoints.

Não é uma alegação de cobertura CSRF universal: endpoints públicos, integrações, webhooks e controles especializados precisam de sua revisão própria. Webhooks financeiros assinados e o agendador não receberam uma exigência genérica de Origin que quebraria suas integrações.

### Navegação

53 ocorrências de Link, em 26 arquivos, foram substituídas por links HTML nativos. O inventário prévio confirmou apenas href, className e style nessas ocorrências. URLs e aparência foram preservadas, sem interceptação/prefetch do Link do Vinext que havia falhado no teste de produção.

A navegação usa carregamento completo; não altera regras de acesso nem libera módulos. Isso não equivale a validar todos os botões, formulários ou jornadas autenticadas.

Três atalhos de suporte deixaram de apontar para uma caixa de e-mail não configurada no domínio vinha.app e passam ao atendimento da própria Vinha.

### Recuperação de senha

A tela não depende mais de /api/access/recovery, contida na L0. Usa resetPasswordForEmail, trata erros e sempre libera o botão ao terminar. Não cria protocolo fictício nem afirma que a mensagem foi entregue. Alteração de e-mail, conta bloqueada e perda de MFA exigem atendimento, sem remover proteções.

O retorno usa /conta/nova-senha no mesmo domínio. Configuração de URLs permitidas, SMTP, entrega com conta real, PKCE/expiração/uso único do link e alteração efetiva da senha ainda precisam de homologação ponta a ponta. Nenhum envio real foi realizado nesta entrega.

### Respostas e cabeçalhos

Configuração Vercel adicionada:

- Cache privado/no-store e desativação explícita de cache CDN nas APIs e grupos de páginas de conta/painel/Central.
- X-Content-Type-Options nosniff e Referrer-Policy same-origin.
- Proteção contra enquadramento: X-Frame-Options DENY e frame-ancestors none.
- CSP também restringe base-uri e object-src; **não é CSP completa de scripts**. Uma política mais restritiva depende de inventário e testes das integrações.

Os valores precisam ser reconfirmados nos domínios após a publicação. Não basta estarem no arquivo.

## Validação automatizada

- Nove testes novos de política, falhas de dependências, MFA, papéis, seleção de organização, origem, ausência de autenticação antiga, navegação, recuperação e configuração de resposta.
- Quatro testes da contenção L0 preservados.
- Quatorze testes de integrações/faturamento preservados.
- 27 testes aprovados localmente. Não substituem testes reais de isolamento no banco.
- Verificador de botões continua com 49 controles legados, sem aumento; não é aprovação funcional desses controles.
- TypeScript: 316 diagnósticos contra 318 da base, sem diagnóstico nos novos controles de acesso nem na recuperação reescrita. Não se considera a checagem aprovada enquanto houver erros.
- HTTP local sem sessão: sessão/pessoas/unidades retornaram 401, sessão de operador 403, eventos contidos 503. Cabeçalhos sintéticos de identidade sem sessão continuaram com 401.
- POST local com origem externa foi recusado com 403 pelo próprio servidor de desenvolvimento antes da aplicação; a política específica da aplicação foi validada nos testes unitários, não por esse POST.
- Navegação local: login → recuperação → atendimento abriu os destinos esperados, sem enviar formulários.
- A prévia de desenvolvimento continuou registrando erro interno de RSC do Vinext. A troca de links elimina a dependência de prefetch do Link, mas não é correção completa do ambiente de desenvolvimento/framework. A produção precisa de conferência própria após deploy.

## Próximo bloco obrigatório

1. Validar banco/RLS com duas organizações e papéis distintos, incluindo unidades restritas, vínculos de hierarquia e dados sensíveis.
2. Revisar access_context e escopo por unidade: a migração existente monta unidades ativas da organização, o que não comprova filtro granular de unidade para cada usuário.
3. Revisar leituras/escritas de pessoas, campos sensíveis e notas pastorais; remover os caminhos D1 residuais de pessoas/unidades.
4. Tratar os alertas de dependências com análise de aplicabilidade ao Vinext/Vercel e atualização testada.
5. Revisar sessões, renovação de cookies/PKCE, expiração, desativação de usuários e MFA das APIs especializadas.
6. Completar revisão CSRF/rate limits/erros em todos os endpoints públicos e de escrita.
7. Homologar recuperação e confirmação de e-mail com remetente e conta real autorizada.
8. Reduzir os erros TypeScript e ampliar jornadas automatizadas autenticadas.

Sem esses critérios, restauração testada e acompanhamento operacional, não abrir contratação como plataforma completa.

## Referências consultadas

- Changelog Supabase: https://supabase.com/changelog.md — consultado antes da implementação; mudança próxima de cifras TLS em 10/11/2026, sem alteração necessária nestas funções.
- Identidade e cache SSR: https://supabase.com/docs/guides/auth/server-side/creating-a-client
- Recuperação: https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail

Consultas locais HTTP e navegação sem sessão não provam os controles do banco em produção. Os bloqueios técnicos da L0 continuam obrigatórios.

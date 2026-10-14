# Auditoria da Central Vinha e ativação dos ministérios

Data: 14/10/2026. Escopo: versão publicada e código local da Central, do cadastro ao primeiro acesso da igreja.

## Resultado

O fluxo está parcialmente funcional. Cadastro pela Central, funções de convite e vínculo do proprietário usam Supabase. A configuração inicial após o aceite e o painel completo ainda dependem de autenticação e banco do OpenAI Sites. Na Vercel, esse banco é substituído por um objeto que lança erro ao ser utilizado. Portanto, a existência das páginas e uma resposta HTTP 200 não demonstram que as operações estejam funcionando.

O estado consultado no Supabase confirma uma organização em avaliação, sede criada, assinatura vinculada e proprietário ativo com e-mail confirmado. Há dois convites aceitos e um revogado; a configuração inicial permanece em `in_progress`, etapa `identity`.

## Método e limites

- Inventário de 15 páginas da Central e 69 declarações de botões. Botões repetidos em listas não representam 69 controles visuais fixos.
- Conferência dos destinos literais internos: todos possuem página correspondente no código.
- Rastreamento dos botões até a API, função do banco, autenticação e destino após sucesso.
- Consultas de leitura no Supabase para estado de convites, vínculos e políticas.
- Nenhuma alteração de dados, aceite, envio de convite ou cobrança foi executada nesta auditoria.
- Não havia janela de navegador com sessão autenticada disponível ao controle de interface. Cliques, modais e aparência dentro da sessão não foram certificados por teste visual. As conclusões funcionais abaixo se apoiam no código e no estado remoto do banco.

## Situação por etapa

| Etapa | Situação | Evidência e consequência |
| --- | --- | --- |
| Cadastro de cliente na Central | Integrado ao Supabase | API chama `create_platform_organization`, que cria organização, sede, assinatura, módulos, convite e registros operacionais em uma transação. |
| Gerar novo convite | Integrado, com risco de UX | Revoga convites pendentes e cria novo token. A interface não garante recuperação se a cópia para a área de transferência falhar. |
| Abrir convite | Função disponível | A correção anterior restaura a leitura; a tela trata incompletamente os estados aceito e revogado. |
| Login/cadastro a partir do convite | Parcial | O retorno `next` é mantido no login comum, mas o fluxo específico de convite não apresenta cadastro claramente separado de criar novo ministério. |
| Aceitar convite | Vínculo confirmado no banco | Há proprietário ativo com convite aceito. A função valida identidade, e-mail, prazo e estado do token. |
| Abrir configuração após aceite | Bloqueador crítico | A API de ativação envia para `/onboarding`, cuja API usa `sessionFrom` baseada em cabeçalhos do Sites e tabelas D1. |
| Salvar configuração inicial | Bloqueador crítico | `/api/onboarding` não utiliza a sessão Supabase; a tabela de progresso Supabase permite apenas operadores da plataforma, não o proprietário da igreja. |
| Entrar no painel completo | Bloqueador crítico | `/painel` usa `AccessGate`, que consulta `/api/session`; esta API usa a autenticação antiga. |
| Entrar por `/acesso` | Parcial | Supabase identifica o vínculo, mas redireciona para `/inicio`, uma tela de migração que oferece o painel antigo. |
| Criar ministério por autoatendimento | Incompleto comercialmente | `bootstrap_organization` cria organização, sede e vínculo, mas não assinatura, módulos contratados nem progresso operacional, ao contrário do cadastro pela Central. |

## Menus e operações da Central

| Área | Destino | Integração das operações |
| --- | --- | --- |
| Organizações | `/admin-vinha` | Supabase; requer melhorias no tratamento de falhas e atualização da ficha. |
| Planos e preços | `/admin-vinha/planos` | Supabase; gravação do plano e dos módulos ocorre em requisições separadas, com possibilidade de gravação parcial. |
| Operadores | `/admin-vinha/operadores` | Supabase; validação visual pendente. |
| Assinaturas/cobranças | `/admin-vinha/faturamento` | Banco legado indisponível na Vercel. |
| Provedores | `/admin-vinha/faturamento/configuracoes` | Banco legado indisponível na Vercel. |
| Consolidadas | `/admin-vinha/faturamento/consolidadas` | Banco legado indisponível na Vercel. |
| Dados financeiros | `/admin-vinha/faturamento/clientes` | Lista vem do Supabase; abertura/salvamento do cadastro financeiro usa API legada. |
| Hierarquia | `/admin-vinha/hierarquia` | Banco legado indisponível na Vercel. |
| Solicitações de vínculo | `/admin-vinha/hierarquia/solicitacoes` | Banco legado indisponível na Vercel. |
| Suporte | `/admin-vinha/suporte` | Banco legado indisponível na Vercel. |
| Qualidade e conhecimento | `/admin-vinha/suporte/conhecimento` | Banco legado indisponível na Vercel. |
| Automações | `/admin-vinha/automacoes` | Banco legado indisponível na Vercel. |
| Alertas | `/admin-vinha/automacoes/notificacoes` | Banco legado indisponível na Vercel. |
| Execuções | `/admin-vinha/automacoes/execucoes` | Banco legado indisponível na Vercel. |

Onze APIs sob `/api/platform` ainda acessam `env.DB`: billing, consolidated, profiles, providers, hierarchy, hierarchy/requests, lifecycle, lifecycle/notifications, lifecycle/run, support e support/knowledge. Na Vercel, `app/lib/cloudflare-env-stub.ts` lança explicitamente erro nesse acesso.

## Defeitos adicionais confirmados no código

1. **Convite aceito impede retomar o acesso:** a tela desabilita o botão quando `status === 'accepted'`, embora a função de aceite já ofereça retorno idempotente para a mesma conta. Deve permitir entrar no ambiente existente sem exigir convite novo.
2. **Convite revogado parece acionável:** `unavailable` considera apenas aceito e expirado; revogado mantém botão de ativação, que falhará no servidor.
3. **Cadastro duplicado por perda do contexto:** um usuário sem vínculo enviado a `/acesso` cai automaticamente em `/onboarding/novo`. Para quem recebeu convite, o produto deve priorizar ativação do ambiente criado pela Central.
4. **Erros deixam controles ocupados:** funções `create`, `update` e `newInvite` na Central não possuem recuperação completa com `try/catch/finally`. Falhas de rede, JSON ou clipboard podem impedir a mensagem de conclusão e a liberação do botão.
5. **Ficha com valores antigos após salvar:** o retorno local mescla nomes camelCase do formulário com dados snake_case da organização. Alguns valores apresentados ficam desatualizados até reabrir a ficha.
6. **Painel da igreja não equivale a acesso do operador:** o link abre `/painel` sem seleção de cliente. Um operador interno não recebe automaticamente vínculo de igreja; o produto precisa de seleção autorizada ou explicação de acesso, sem conceder permissões implicitamente.
7. **Navegação parcialmente alterada:** a página principal e os atalhos usam âncoras nativas, mas páginas secundárias ainda usam `next/link`. Não é possível concluir que todos os cliques foram corrigidos sem teste autenticado.
8. **Estado financeiro fixo:** a função de visão geral retorna `billing_profile_complete = false` para todas as organizações. Isso não comprova a situação real do cadastro.
9. **Configuração concluída sem validar etapas:** o endpoint legado permite enviar `completed` sem verificar que identidade e sede estejam completas. Deve existir validação no servidor na implementação Supabase.
10. **Representante escolhido implicitamente:** o cadastro da Central usa o responsável pela conta como pastor titular quando este não é informado. Esses papéis podem pertencer a pessoas diferentes e devem ser campos distintos.

## Ordem recomendada de correção

1. Migrar autenticação e configuração inicial para Supabase, incluindo políticas de progresso restritas ao proprietário/administrador da organização.
2. Fazer o aceite levar à configuração Supabase ou ao painel, conforme progresso; permitir retomar convites aceitos e apresentar corretamente revogados/expirados.
3. Unificar o resultado do cadastro pela Central e do autoatendimento, evitando duplicação e definindo assinatura, avaliação e módulos.
4. Corrigir mensagens, recuperação de erros, clipboard e atualização da ficha; testar navegação em sessão autenticada.
5. Migrar as operações restantes da Central por área: dados financeiros/cobranças, hierarquia, suporte e automações.
6. Validar ponta a ponta em homologação: novo cliente → convite → cadastro/login → aceite → identidade → sede → conclusão → entrada e retorno ao painel; cobrir também token revogado, expirado, já aceito e e-mail diferente.

## Arquivos centrais da evidência

- `app/api/platform/organizations/route.ts`
- `app/api/platform/activate/route.ts`
- `app/ativar/[token]/page.tsx`
- `app/SupabaseLogin.tsx`
- `app/api/onboarding/route.ts`
- `app/api/_auth.ts`
- `app/AccessGate.tsx`
- `app/api/session/route.ts`
- `app/acesso/page.tsx`
- `app/inicio/page.tsx`
- `app/lib/cloudflare-env-stub.ts`
- `supabase/migrations/20261013113000_platform_organization_operations.sql`
- `supabase/migrations/20261013120000_organization_invite_activation.sql`

Conclusão: o ministério existente não precisa ser recriado. O vínculo do proprietário está ativo; a prioridade é conectar as telas posteriores ao aceite à mesma sessão e ao mesmo banco.

# L1 — bloco 2: proteção de membros e unidades (entrega parcial)

Registro histórico da primeira entrega. A continuação e o estado mais recente constam em EXECUCAO-L1-ISOLAMENTO-2026-10-16.md.

Data: 15/10/2026. Base: 398f15838570cbffccdcc794707194569c1e5b0f.

## Situação

Correções locais e testes concluídos no escopo abaixo. Não publicado nesta entrega.
O bloco de isolamento não está concluído e a Vinha permanece em pré-lançamento.
Não houve alteração de políticas/esquema/contas do Supabase de produção nem envios, cobranças ou notas fiscais reais.

## Implementação

- Pessoas e unidades deixam de importar Cloudflare/D1 e de retornar ao banco antigo na ausência de Supabase. A autorização existente responde 503 sem configuração.
- Seleção explícita de unidade só aceita identificador existente ou nome exato e único entre unidades ativas retornadas pelo banco da organização. Sem busca por padrões; unidade inválida não é substituída pela padrão. A seleção é validação de integridade, não concessão de permissão: RLS continua obrigatória.
- Edição de pessoa verifica primeiro o registro acessível na organização. A omissão de campus preserva a unidade existente.
- Pessoas e unidades verificam o registro retornado pelo UPDATE. Zero linhas retorna 404, sem auditoria de sucesso e, para pessoas, sem gravação posterior de endereço.
- Endereços, contatos e notas recebem filtro explícito de organização. Notas só são consultadas por proprietário/pastor; erros de dados complementares retornam indisponibilidade em vez de cadastro aparentemente completo.
- Limpeza compensatória de criação de membro também filtra organização. Essa sequência ainda NÃO é transação atômica; precisa ser substituída por operação transacional antes do piloto.
- Unidade responsável precisa estar ativa e acessível na mesma organização. Edição preserva o pai omitido e rejeita autoparentesco, descendentes, ancestrais ausentes e ciclos existentes na cadeia visível.
- A validação de ciclo é de aplicação: NÃO protege acesso direto à API do banco nem alterações concorrentes. A restrição no banco ainda precisa ser implementada e testada.

## Banco de testes isolado

Docker disponível, servidor 29.8.2. Criado projeto local independente vinha-rls-b348af76, porta de banco 56322, sem copiar credenciais/vínculo remoto ou sementes de clientes. As 27 migrações versionadas foram aplicadas com sucesso. Nenhum reset do banco local preexistente.

Suíte supabase/tests/members_rls.sql ampliada de 6 para 15 cenários pgTAP, com dados sintéticos e rollback:

- leitura limitada à organização;
- inserção e auditoria entre organizações bloqueadas;
- líder vê apenas unidade concedida;
- concessão somente de leitura não permite inserir/editar;
- notas pastorais não aparecem para líder;
- endereço respeita acesso à pessoa;
- atualização e exclusão de membro de outra organização não afetam linhas;
- chave composta impede membro vinculado a unidade de outra organização;
- suspensão da participação remove acesso do líder;
- membro lê seu próprio cadastro sem ganhar edição administrativa.

Resultado: 15/15 aprovados no banco LOCAL. Isso não comprova o estado do banco remoto.
Verificador local de segurança: nenhum alerta warn/error encontrado. Não equivale a auditoria completa das regras de negócio.

A execução da pasta inteira falhou: quatro arquivos de testes transacionais exigem contas preexistentes e não produzem plano TAP. Não foram considerados aprovados. Próximo trabalho: criar fixtures independentes e adaptar a execução apropriada para esses quatro arquivos.

## Validação da aplicação

- Testes unitários executam as rotas reais com cliente substituto para validar registro inacessível, zero linhas, falha de leitura, preservação da unidade e bloqueio de ciclo. Não simulam aprovação de RLS.
- Build Vercel concluído.
- TypeScript continua com 316 diagnósticos preexistentes; nenhum em people/units ou unit-integrity. Checagem global NÃO aprovada.
- Testes de contenção L0 e faturamento preservados.
- Jornadas autenticadas no navegador e publicação não realizadas neste bloco.

## Pendências para fechar L1 bloco 2

1. Conector Supabase continua recusando até consulta de metadados com “You do not have permission to perform this action”, apesar da permissão do plugin ter sido alterada anteriormente. Resolver a autorização efetiva da conexão sem desativar RLS nem expor chaves privilegiadas.
2. Conferir histórico de migrações, políticas, privilégios e advisors no banco principal; não presumir que é idêntico à cópia local.
3. Restringir access_context, leitura de unidades e pessoas conforme concessões por unidade. Hoje o contexto lista todas as unidades ativas da organização e o papel secretary tem acesso organizacional nas políticas existentes. Definir e testar a semântica sem ampliar privilégios.
4. Integridade de membership_unit_access: validar que participação e unidade pertencem à mesma organização; testar reatribuição, concessões revogadas, manage/admin, include_children e vínculos cruzados.
5. Impedir ciclos e corridas de reparentamento no banco; tornar recursão de escopo resistente a dados cíclicos.
6. Tornar criação/edição de membro e dependências transacional, validar campos parciais e impedir apagamento involuntário de campos omitidos.
7. Converter os quatro testes dependentes de contas existentes em testes isolados e reproduzíveis.
8. Só depois: homologação autenticada, revisão da entrega e publicação controlada. Não liberar clientes reais com base apenas nesta suíte parcial.

# Hierarquia em vários níveis e transferências

## Onde usar

Células → Redes e supervisão → bloco **Hierarquia e transferências**. Os nomes do módulo e da página continuam usando a personalização do ministério. A unidade selecionada determina o escopo de todas as consultas e decisões.

### Hierarquia

Cadastrar redes no diretório existente e, em “Hierarquia das redes”, escolher a rede superior de cada rede. “Nível principal” remove o vínculo superior sem apagar o histórico. O caminho completo exibe os níveis, inclusive quando os ancestrais estão em outra página. As opções correspondem à página atual; navegar para escolher outras redes. É possível ter várias raízes e até 32 níveis contando a raiz. Movimentar um ramo considera também a profundidade de seus descendentes. Ciclos diretos/indiretos são recusados no banco, inclusive em alterações simultâneas.

Arquivar preserva as relações existentes. Uma rede arquivada não pode receber novas relações superiores nem ser escolhida como novo superior. As relações dos grupos com as redes continuam usando a página existente. Não há mudança automática de supervisor, papel, permissão ou contrato.

### Transferência de participante

Em “Transferências de participantes”, escolher “Solicitar transferência”, os grupos de origem/destino e um participante ativo da origem. Os nomes são obtidos do cadastro de membros; não existe criação automática ou transferência por nome manual. A busca filtra os participantes carregados, com botão para carregar outras páginas.

A solicitação não altera vínculos. Outro comando explícito permite aceitar ou recusar; o solicitante também pode cancelar. A decisão exige gestão atual da unidade. O próprio solicitante pode aceitar se continuar autorizado — não é uma regra de dupla aprovação por pessoas diferentes. Os usuários com leitura podem consultar o histórico, mas não decidir.

Aceitar faz, na mesma transação: revalidar emissor, decisor, acesso, módulo, contrato, unidade, pessoa, grupos e versão da origem; inativar o vínculo da origem; criar ou reativar o vínculo de destino; encerrar a solicitação e auditar. Uma origem só pode ter uma solicitação pendente. Destino já ativo ou origem alterada exigem revisar a pendência; não há aceite silencioso. Recusa/cancelamento não movem o participante e não reescrevem decisões encerradas. Solicitações obsoletas podem ser recusadas por gestor autorizado mesmo se o emissor perder acesso.

Os vínculos antigos não são movidos nem apagados: chamadas já criadas continuam apontando para o vínculo original. Isso preserva os relatórios históricos. O cadastro de membro e sua unidade não são modificados. O sistema continua permitindo participação em outros grupos conforme as regras anteriores; a transferência não estabelece exclusividade global.

## Segurança e compatibilidade

Migração `20261020012039_cell_hierarchy_transfers.sql`. Duas tabelas públicas com RLS e sem gravação direta de clientes, chaves compostas de escopo, funções públicas invoker e comandos privilegiados no esquema privado. A hierarquia tem uma linha privada de serialização por unidade; sua atualização também detecta snapshots antigos em repeatable read/serializable. A consulta materializa os registros autorizados da unidade para não repetir a autorização em cada passo recursivo.

Transferências travam os grupos em ordem estável, compartilhando a serialização usada pelos encontros e participantes. Decisões e cadastros têm versões; retries idênticos não duplicam os efeitos/auditoria. Erros de corrida não são reportados como sucesso. APIs usam a organização da sessão validada, limites de corpo, respostas estritas e `no-store`. Não há acesso anônimo nem concessão automática por hierarquia.

APIs antigas de redes/participantes mantêm seus contratos. Nenhum dado existente é reclassificado, excluído ou transferido pela migração. Não há migração de ministérios, filiais ou cobrança neste bloco.

## Evidências de validação

- 254 testes de aplicação aprovados, incluindo sete novos de validação/rotas e autorização.
- 50 testes SQL transacionais: ciclos, 32 níveis, descendentes, versões, escopo, papéis, estados, histórico, idempotência, retorno, RLS e paginação.
- 18 cenários concorrentes nos três níveis de isolamento: ciclo oposto, decisão simultânea, alteração da origem, ativação do destino, suspensão do emissor e fotografia da chamada versus aceite.
- Compilação local Vercel/Nitro e verificações de tipos, segredos e botões. O artefato local não deve ser publicado; produção compila pelo GitHub.
- Interface local com conta fictícia: três níveis, ciclo recusado, solicitação/aceite/recusa/cancelamento e formulário em 390 × 844. Sem dados fictícios em produção.
- A suíte completa em banco limpo deve passar no CI antes da aplicação no principal. O Docker de desenvolvimento não é resetado para corrigir estruturas antigas ausentes.

## Fora desta entrega

Transferências entre unidades/ministérios, concessão de acesso por rede, organograma de contas, múltiplos supervisores, notificações automáticas, métricas consolidadas por ramo, indicações e materiais continuam separados. O módulo mantém a classificação de piloto; não há declaração de conclusão de toda a plataforma.

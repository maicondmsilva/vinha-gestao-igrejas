# Redes e supervisão — primeira entrega

## Uso

Em Células → Redes e supervisão, cadastrar uma rede da unidade selecionada. O responsável pode ser um membro ativo escolhido pela busca ou um nome manual. O banco guarda a referência e o nome canônico quando há seleção. Digitar outro nome limpa a referência. Não cria cadastro, conta, convite, mensagem ou papel de acesso.

No bloco Vínculos dos grupos, escolher uma rede ativa e salvar. Cada grupo tem no máximo uma rede da mesma unidade. “Sem rede” remove o vínculo atual, mantendo sua linha versionada e o evento de auditoria com identificadores da rede anterior/nova. Arquivar rede preserva vínculos existentes e impede novas associações até reativá-la. Grupo arquivado fica somente consulta. “Ver grupos da rede” filtra a relação.

Redes e grupos têm paginação independente por chave, até cem registros. As opções de associação correspondem à página de redes visível; a rede atual fora da página continua identificada. Não há contagens ou métricas artificiais baseadas na página. Os termos da página e do responsável são personalizáveis para todo o ministério pela engrenagem.

## Limites explícitos

Supervisão nesta entrega significa indicar o responsável pela rede, não conceder poderes. A rede é plana e limitada à unidade; não há níveis pai/filho, acesso herdado, supervisão por usuário/conta, múltiplos supervisores, consolidação entre unidades, transferência de participantes ou alteração de chamada. Indicadores e relatórios existentes não foram reclassificados por rede. Esses fluxos continuam pendentes, assim como indicações, materiais e referências de membros nos outros módulos.

## Segurança e consistência

Migração `20261019234621_cell_networks.sql`: duas tabelas com RLS, sem gravação direta do cliente ou execução anônima. Chaves compostas impedem referências fora de ministério/unidade. Consultas e API pública são invoker; implementação de escrita auditada fica no esquema privado não exposto. Leitura exige os módulos Células e Pessoas e acesso à unidade; escrita exige proprietário/administrador/pastor/líder com gestão da unidade, e-mail confirmado e estados operacionais válidos.

Gravação trava os estados de organização, unidade, participação, concessão e contrato, além do grupo/rede/pessoa relevantes. Versões recusam concorrência; retry idêntico é idempotente. A associação segue a mesma ordem de locks do diretório para não inverter advisory/row lock. Auditoria usa identificadores/versão/situação, sem copiar nomes. Nenhum plano, acesso ou cadastro existente é reclassificado automaticamente.

## Validações

- 247 testes de aplicação aprovados, sete novos de redes/rotas; tipagem, segredos e botões aprovados.
- 38 novos testes SQL: identidade, nomes canônicos/manuais, arquivamento, vínculo, auditoria, paginação, escopo, contratos, papéis e suspensão.
- Quinze cenários concorrentes: edição de rede, troca de vínculo, arquivamento de rede e de grupo versus associação, suspensão versus associação, nos três níveis de isolamento. Exclusivamente fixtures no Docker local.
- Compilação Vercel/Nitro com configuração local; esse artefato não é publicado. O deploy de produção deve compilar o código do GitHub.
- Interface local com conta fictícia: seleção por teclado, salvar/reabrir responsável vinculado, associação, arquivamento preservando vínculo, nome manual, desvincular e filtro. Formulário conferido em 390 × 844. Nenhum teste cadastral no principal.
- A suíte completa deve passar no banco limpo do CI antes da promoção. O Docker de desenvolvimento preserva fixtures do usuário e não é resetado para corrigir ausências de estruturas antigas.

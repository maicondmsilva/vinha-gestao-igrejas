# F6 — relatórios e prestação de contas

Área Financeiro → Relatórios e prestação de contas, por igreja ou consolidado das igrejas autorizadas.

## Consultas

Livro caixa, extrato por conta, fluxo previsto versus realizado, receitas/despesas por categoria e subcategoria, centros de custo, resultado por igreja, títulos por vencimento, contribuições por membro, campanhas/eventos, provas dos provedores, orçamento mensal, divergências, prestação de contas e exportação auxiliar contábil.

As entradas realizadas vêm do livro imutável, com sinais e datas originais de estorno. O principal ainda aberto vem dos títulos e não é somado novamente quando há baixas parciais. Transferências aparecem nas contas mas não integram resultado, assim como os saldos iniciais. Bruto/taxas/líquido dos provedores vêm de cada prova uma única vez; taxa desconhecida permanece desconhecida. Sandbox não compõe esse relatório.

Partidas contábeis são exportadas por lote completo, inclusive a contrapartida, sem simular um plano de contas do contador. Os dados precisam ser mapeados e validados antes de importar em outro sistema.

## Filtros e limites

Período de até 366 dias, base de data (caixa, competência ou vencimento), igrejas, conta, categoria, subcategoria, centro, pessoa/fornecedor cadastrado, finalidade, referência de campanha/evento/pedido, origem, situação, provedor, método, valor e responsável. Não se cria vínculo por semelhança de nome. Contribuições individuais e filtro de pessoa são exclusivos de proprietário/administrador.

As mesmas regras do banco e da API são aplicadas à consulta e ao CSV. Todas as igrejas selecionadas devem estar autorizadas; não há consolidação parcial silenciosa. A consulta recusa mais de 10.000 movimentos, exigindo redução do escopo, e não exporta somente a página visível. A tela pagina a cada 50 linhas; impressão e CSV usam a seleção completa. O CSV é UTF-8 com BOM, separador ponto e vírgula e neutralização de fórmulas.

Saldos de conta seguem data de caixa e são identificados como independentes dos filtros de classificação. Orçamento aceita somente dimensões de categoria/subcategoria/centro e mês; filtros incompatíveis são recusados. Orçamento usa a categoria exata e o centro escolhido, sem inventar rateio entre centros. Comparações mensais devem usar meses completos.

Pendências OFX não possuem categoria, pessoa ou provedor. O relatório de divergências aceita igreja, conta e data de caixa, recusando filtros inexistentes no extrato. Movimentos antigos cujo vínculo cadastral foi substituído continuam no livro de caixa; metadados históricos indisponíveis não são atribuídos ao cadastro atual.

## Orçamento

Proprietário/administrador define ou revisa valor por igreja, mês, categoria e centro. Edição usa versão e registra autor, valor anterior e justificativa. Em resultado incerto, atualizar a consulta antes de repetir; uma versão obsoleta não sobrescreve alterações. Para zerar uma previsão, editar o valor para zero, sem apagar o histórico.

## Ajustes operacionais de 23/10

- Categorias: filtros de recebimento/pagamento/todos e ativo/inativo/todos, sem excluir cadastros.
- Fechamento: a conciliação não é obrigatória para o fechamento administrativo. A opção existente de fechar com ressalvas foi explicada na tela e no formulário. Apenas proprietário/administrador pode assumir pendências com justificativa; o mês não fica falsamente conciliado.
- Carregamento: verificações de unidades feitas em lotes de no máximo quatro, preservando recusas; reaproveitamento da consulta ao navegar entre páginas que usam o mesmo escopo e filtros. Cabeçalho Server-Timing da API financeira permite distinguir tempo de servidor de espera de rede. Não representa certificação de desempenho global.
- Tokens: exigem FINANCE_RECEIVER_ENCRYPTION_KEY válida e credencial privada SUPABASE_SECRET_KEY (ou a compatibilidade SERVICE_ROLE) somente no servidor. Nunca em NEXT_PUBLIC_. Alterar a chave do cofre sem migração torna credenciais antigas ilegíveis. Salvamento protegido não equivale a homologar pagamentos externos.

## Segurança

Orçamentos e fontes de relatório privados, sem acesso direto de clientes. Função pública invoker e rotina interna com conta confirmada, ministério, papel, contrato e unidade revalidados. Relatórios sincronizam a leitura com as gravações financeiras; escopo não é aceito de uma organização enviada pelo navegador.

Relatórios gerenciais, recibos e exportações não substituem nota fiscal ou demonstração contábil validada pelo contador. Configuração e homologação real de cada provedor seguem pendentes de suas credenciais e validações externas.

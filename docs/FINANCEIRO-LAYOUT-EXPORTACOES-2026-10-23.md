# Financeiro: layout e exportações

## Entrega

- Estilo compartilhado nas 13 páginas do financeiro: formulários, cabeçalhos, cartões, navegação, tabelas com rolagem interna e modais.
- Ação Gerar relatório abre a consulta correspondente ao contexto, mantendo igrejas e período. Contas a pagar/receber abrem Contas por vencimento, que contempla ambos; não implica filtro exclusivo pela natureza.
- Filtros avançados recolhíveis. Removidos slogan repetido e aviso desatualizado sobre disponibilidade futura dos provedores.
- Os 14 relatórios existentes agora oferecem PDF, Excel XLSX e CSV. A consulta é refeita no servidor, sob a mesma autorização e regras de privacidade, com preparação auditada. Não se exporta somente a página visível.

## Identidade dos documentos

- PDF A4 paisagem, nome do ministério, igrejas, período, base de data, filtros, horário de Brasília e identificador de preparação.
- Logo PNG da igreja selecionada em Relatórios > Logo da igreja no PDF. Essa seleção é temporária, por sessão/seleção de igrejas; não altera a identidade compartilhada do ministério. Em consolidações, usar logo do ministério.
- Na ausência da logo, cabeçalho com a identidade Vinha. Rodapé fixo Vinha - Gestão que frutifica e paginação em todas as páginas.
- Livros com muitas colunas são divididos em painéis que repetem número e igreja. Cabeçalhos de tabela se repetem nas quebras. Não há corte silencioso de registros.
- Caracteres fora do alfabeto suportado pelo PDF padrão geram orientação para usar Excel; não são substituídos silenciosamente.
- Excel: cabeçalhos verdes, linhas alternadas, filtro e congelamento de cabeçalhos, datas e valores numéricos, identificadores textuais e saldos em aba própria quando aplicável. Valores acima da precisão do Excel permanecem texto exato.

## Proteções preservadas

- Nenhuma migração, alteração de contrato, mudança de permissões ou cobrança real.
- Organização e nomes das igrejas vêm da sessão, não do navegador.
- Logo enviada como PNG limitado a 250 KB, 2 milhões de pixels e 2.000 pixels por lado; sem URL externa, SVG ou busca remota. Não utiliza chave de serviço para ampliar acesso aos relatórios.
- Identificadores verdadeiros não viram números e textos semelhantes a fórmulas permanecem células textuais no XLSX. CSV conserva proteção existente.
- Downloads privados e sem cache; contribuições individuais continuam restritas. Identificador de preparação não é prova de download ou assinatura digital.
- Limites anteriores de período e 10 mil movimentos permanecem. PDF com mais de 2 mil páginas é recusado, orientando reduzir período ou usar Excel.

## Verificação

Testes de autorização GET/POST, formato, identidade confiável, payload, PNG, centavos, identificadores, texto semelhante a fórmula, estrutura XLSX, paginação e todos os 14 relatórios. Downloads exercitados na interface com dados fictícios locais. PDF de duas páginas renderizado e inspecionado. Telas de 390 e 320 pixels revisadas, com correção do estouro nos filtros.

ExcelJS e pdf-lib são dependências de execução do aplicativo, não ferramentas de criação de planilha avulsa. Correções transitivas para brace-expansion e uuid fixadas no lockfile. A auditoria também apontou avisos preexistentes de Next.js 16.3.8; a atualização do framework não faz parte desta alteração de layout e não foi declarada como resolvida. O servidor usa Vinext; esta observação não substitui avaliação de exposição das rotas afetadas.

Mercado Pago permanece conectado conforme configuração anterior. Não se realizou pagamento nem se declarou homologação externa completa de recebimento, webhook ou liquidação.

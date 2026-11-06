# Operação financeira — 6 de novembro de 2026

Entrega: lançamentos, recebimentos digitais, cadastros, relatórios e conciliação OFX.

- Recebimentos, taxas e devoluções identificam o nome e o ID numérico do evento/venda, inclusive nos registros anteriores. A evidência original do provedor não é reescrita.
- Clicar no lançamento abre diretamente o formulário de edição. Lançamentos manuais usam o mecanismo de revisão com histórico e reversões. Registros vinculados ao provedor admitem descrição e observações em uma camada auditada; valores e classificação permanecem coerentes com a transação.
- A data de pagamento/recebimento só aparece quando a situação é realizada. Séries continuam criando previsões.
- Paginação de categorias, fornecedores, centros de custo e contas; relatórios e lançamentos oferecem 15, 30, 50, 100 e 150 registros por página. Exportações mantêm a consulta completa.
- OFX: seleção explícita de movimentos na importação, comparação paginada, fornecedor no livro, criação de um lançamento revisável a partir de um movimento, prevenção de duplicidade e retirada/restauração sem apagar a evidência original. A conciliação permanece uma ação explícita apenas para a seleção de totais correspondentes.
- Cabeçalho simplificado, com a personalização de nomes no topo e sem repetir o nome do módulo no Financeiro.

## Validação

- Compilação e verificação TypeScript aprovadas.
- 165 testes financeiros de aplicação aprovados, incluindo autorização, importação seletiva e limites da paginação.
- Regressão SQL local F1, F2, F4, F5, F6 e 27 verificações da nova operação aprovadas com rollback das fixtures.
- Interface local: previsão sem data realizada; edição e recebimento; fornecedor em conciliação; importação de um dos dois movimentos; criação pelo OFX; exclusão e restauração; fornecedores em duas páginas; 390px sem transbordamento.
- Revisão de botões e segredos aprovada. Nenhuma cobrança, devolução ou conciliação de produção foi executada nos testes.

As imagens anexas contêm somente dados fictícios no banco local.

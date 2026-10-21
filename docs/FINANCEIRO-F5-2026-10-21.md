# F5 — Conciliação e fechamento

## Entrega

Submenus Conciliação e Fechamento mensal integrados ao painel financeiro e à identidade visual da Vinha. Operações por uma igreja e conta de cada vez, respeitando papel, módulo, contrato e concessão da unidade.

### Extratos

OFX bancário SGML/XML simples, BRL, uma conta, até 1 MB e 1.000 movimentos. Datas e centavos são validados sem ponto flutuante. Leitura UTF-8 com alternativa Windows-1252. Entidades externas, correções OFX, múltiplas contas, moedas diferentes, datas inválidas e FITIDs ausentes/repetidos são recusados explicitamente.

O servidor interpreta novamente o arquivo. Não é armazenado o arquivo bruto nem o número completo da conta: apenas movimentos normalizados, saldos, final da conta e identificadores resumidos criptograficamente. O responsável confirma que a conta financeira corresponde à conta bancária. OFX é evidência informada pelo usuário; não é uma consulta autenticada ao banco.

Arquivo repetido não importa de novo. FITIDs são únicos por conta; arquivos sobrepostos reutilizam movimentos existentes. Um FITID com dados divergentes recusa a operação integralmente. Coincidência de valor/data/descrição com FITIDs diferentes aparece como possível duplicidade, sem exclusão automática.

### Correspondências

Sugestões por valor, proximidade de até três dias e referência, sempre sujeitas à confirmação humana. Bruto e taxa de uma prova do provedor podem formar uma sugestão de líquido. Seleção de vários itens de cada lado permite recebimentos agrupados. Os totais assinados devem ser exatamente iguais. Nenhum movimento pode estar em duas conciliações ativas.

A importação e a conciliação não criam receitas ou despesas. Transferências continuam fora dessas receitas/despesas; cada conta é conferida separadamente. Saldos iniciais são conferidos no saldo, não forçados contra um movimento OFX fictício. Pares de estorno contábil compensados internamente não criam falsas pendências bancárias.

Recebimentos digitais exibem a conciliação derivada dos vínculos, sem alterar a prova ou o estado de pagamento do provedor. Disponível no provedor não significa conciliado com extrato. A homologação externa e as credenciais de cada provedor continuam sendo requisitos próprios: a F5 não ativa contas, não executa repasses e não simula respostas externas.

### Correções e fechamento

Desfazer exige justificativa e mantém o vínculo anterior no histórico. Uma contabilização conciliada não pode ser estornada nem editada por APIs antigas antes de desfazer o vínculo. Períodos fechados exigem reabertura administrativa.

Checklist mostra movimentos pendentes de ambos os lados, revisões dos provedores, itens desconsiderados, ausência de evidência de saldo na data final e diferenças de saldo. Fechamento normal exige checklist regular. Proprietário/administrador pode assumir ressalvas explícitas; o registro fica marcado como não totalmente conciliado. Essa distinção não pode ser alterada pelo cliente.

O fechamento usa o último dia de mês já encerrado. Reabertura exige proprietário/administrador, data esperada do fechamento e justificativa; retém a história anterior. A rotina legada de fechamento também exige checklist, sem contornar a F5.

## Segurança e validação

Tabelas privadas com RLS restritiva e sem leitura/gravação direta para clientes. Funções públicas invoker e rotinas privilegiadas internas com validação da conta autenticada e escopo financeiro. Nenhuma chave secreta no navegador.

Identificadores de pedido e impressão do conteúdo tornam os comandos idempotentes. Há revalidação após bloqueios, proteção por versão/estado, índices únicos para vínculos ativos e ordem de bloqueio compatível com recebimentos.

Testes: parser OFX, API e permissões, importações sobrepostas, conflito de dados, correspondência bruto/taxa, saldo, fechamento/reabertura, ressalvas, isolamento de unidade, suspensão e concorrência real. Dados de homologação são fictícios e locais; testes SQL usam rollback.

Referência do formato: [OFX Banking Specification 2.3 — Financial Data Exchange](https://financialdataexchange.org/common/Uploaded%20files/OFX%20files/OFX%20Banking%20Specification%20v2.3.pdf).

Relatórios gerenciais amplos e exportação contábil continuam no escopo F6. Recursos de conciliação entregues aqui não substituem a validação do contador.

# Identificação e cadastro de cobrança

- Ministérios recebem `registration_code` automaticamente no banco, em sequência global iniciada em 1000. UUIDs continuam sendo as chaves internas e os números não concedem acesso.
- A sede representa o próprio ministério e exibe seu mesmo código. Congregações, campus, regionais e filiais recebem códigos próprios da mesma sequência. Uma igreja com contratação independente mantém seu código quando é vinculada a uma sede.
- Cadastros anteriores receberam códigos por ordem de criação. O primeiro ministério existente recebeu 1000.
- Números não podem ser alterados por edição e não são reutilizados. Como em sequências PostgreSQL, exclusões, falhas ou testes revertidos podem deixar intervalos; não é uma numeração fiscal.
- A Central exibe e permite pesquisar o código na carteira de organizações e no cadastro de cobrança; o painel exibe o código nas unidades.
- A lista de cadastros financeiros passa a consultar `/api/platform/billing/profiles` sem `id`, independente de planos ou faturas. Inclui organizações em avaliação e sem perfil financeiro, com indicação de cadastro pendente.
- Falhas de carregamento são exibidas com opção de tentar novamente; lista vazia não é usada para esconder erros.
- Faturas continuam separadas dos cadastros. A geração automática respeita os contratos em avaliação e não cria cobranças reais só para fazer os ministérios aparecerem.

Validação: compilação Vercel, verificação dos arquivos principais e teste transacional de ativação com rollback. O teste confirma geração de códigos, código da sede, código próprio de congregação, bloqueio de edição, aceite e hierarquia. A RLS não foi desativada. Não houve teste visual autenticado nesta execução.

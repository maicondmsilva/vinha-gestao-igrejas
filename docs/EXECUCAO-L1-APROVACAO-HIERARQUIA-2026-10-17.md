# L1 — bloco 13: estado atual na aprovação de hierarquia

Base publicada: 1fff477e93c161f7f0fecea2e2721484427d6e18. Desenvolvimento em revisão, não aplicado em produção. Somente conexão Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva. Não encerra L1 nem libera piloto.

## Achado confirmado e correção delimitada

A inspeção de leitura do corpo remoto de approve_organization_hierarchy confirmou que o fluxo privilegiado não confere os estados dos dois ministérios antes de registrar aceite, rejeição ou vínculo/pagador. Também usa NOT IN sem rejeitar NULL explicitamente; em PL/pgSQL uma condição NULL não aciona o IF e uma decisão ausente pode seguir o ramo de aceite.

A revisão exige decisão explícita approve/reject e identificadores presentes; em solicitações pendentes, trava as duas organizações em ordem de ID e exige ambas active/trial. Depois trava e revalida a participação atual de quem responde. Preserva a matriz existente owner/admin/pastor, as respostas, a serialização de hierarquia, a aprovação pelos dois lados, a idempotência de estados terminais e os bloqueios anteriores de ciclos/filha já vinculada. Pagamento individual ou centralizado mantém o comportamento anterior, somente após o aceite duplo.

Nenhum backfill, exclusão ou alteração automática de solicitação, vínculo ou cobrança existente. Rejeitar uma solicitação pendente com uma das organizações suspensa/cancelada também será recusado até revisão administrativa ou regularização. Não muda o preço, plano ou contrato e não executa pagamento externo.

## Testes e limites

Preparados testes SQL com contas sintéticas, rollback e casos de autorização, NULL, decisão inválida, suspensão de sede/cancelamento da filha, efeitos parciais, idempotência, ciclos, papéis e pagador. Aguardar suíte completa em banco efêmero antes de pedir aplicação. Docker local inacessível por permissão do canal, não interpretado como prova de engine desligado.

Escopo limitado ao RPC de resposta. A criação/edição direta das solicitações pela Central, retenção/consulta, identidade de autores de aceites antigos e revalidação desses autores no segundo aceite ainda exigem revisão própria. O modelo atual guarda horários, não os dois autores: esta revisão não afirma resolver revogação do primeiro aprovador entre os aceites. Não houve teste específico de concorrência de hierarquia nem nova validação visual autenticada. Testes anteriores de governança não provam todos os interleavings desse fluxo. Não afirmar segurança integral ou conclusão da migração de toda a plataforma.

As orientações de Supabase levaram a manter a autorização explícita no RPC privilegiado existente, search_path vazio e grants restritos, sem conceder acesso geral às tabelas nem usar metadados editáveis do usuário. A consulta ao changelog markdown não foi suportada pelo navegador; usado o índice HTML oficial e a documentação atual de RLS. Referências: [changelog](https://supabase.com/changelog), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [privilégios](https://supabase.com/blog/postgres-roles-and-privileges).

## Aplicação e recuperação

Após CI e autorização específica, aplicar a migração apenas no banco principal Vinha Igrejas; verificar definição/grants sem criar solicitações reais. Conciliar o arquivo com a versão registrada e publicar a revisão. Se houver regressão, reproduzir em ambiente isolado e corrigir seletivamente; não restaurar decisão implícita nem contornar a verificação de estado. E-mail real, backup/restauração, sessões e os demais itens do plano continuam pendentes.

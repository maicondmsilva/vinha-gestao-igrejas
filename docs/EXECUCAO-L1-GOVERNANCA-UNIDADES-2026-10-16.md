# L1 — bloco 12: governança das unidades

Base publicada: eb90f5769ddc0e8b6f0fe5c25ae142397b1b6934. Proposta em revisão, sem aplicação em produção. Exige CI aprovado e autorização específica antes da implantação. Não encerra L1 nem libera o piloto.

## Evidência

A inspeção somente de leitura confirmou políticas INSERT/UPDATE/DELETE de unidades por papel de gestor sem conferir o estado do ministério na escrita. O gatilho anterior já impedia transferir organization_id e formar ciclos, e o código de identificação já era protegido, mas não havia proteção equivalente para id, slug, created_at ou classificação da sede. O tipo headquarters influencia consultas de contrato e provisionamento: não deve ser trocado como simples rótulo de cadastro.

A contagem agregada principal não encontrou ministérios com mais de uma sede nem sedes com unidade superior no momento da inspeção. Isso não prova ausência de outros problemas e não substitui os testes. Nenhum cadastro real foi alterado.

## Mudanças delimitadas

- Revoga DELETE de organization_units para PUBLIC, anon e authenticated. Fluxos internos de serviço permanecem separados; não é criada API de purga.
- Gatilho invoker mantém a RLS, exige ministério ativo/em demonstração e bloqueia sua linha durante a decisão. Impede trocar identidade, ministério, slug, data original e código por escrita comum, mantendo a mensagem anterior para transferência entre ministérios. Novas colunas são negadas por padrão até revisão.
- Impede converter unidade em sede ou sede em outro tipo, subordinar sede e criar segunda sede por escrita de cliente. A primeira sede do cadastro legítimo continua permitida.
- Preserva nome, dados legais, responsável, contato, endereço, autonomias operacionais, tipos não sede, hierarquia autorizada e estado operacional da unidade. Reativar uma unidade não reativa o contrato, cujas regras anteriores continuam independentes.
- Horário de atualização é atribuído pelo banco; INSERT de cliente não fabrica data antiga.
- A API traduz somente recusas conhecidas em mensagens compreensíveis e não registra sucesso/auditoria positiva quando o banco recusa a gravação.

Sem exclusão, migração ou reclassificação de registros existentes. A troca legítima de sede exigirá procedimento administrativo auditado separado, não atualização direta do tipo. Não foi implementada nova tela de arquivamento/restauração: o estado operacional existente é preservado, mas DELETE deixa de ser uma opção de cliente.

## Validação e limites

77 testes de aplicação aprovados localmente: 59 de segurança, 14 da Central e 4 de preparação de publicação. SQL novo preparado para identidade, campos permitidos, sede, datas, papéis, outro ministério, suspensão e bootstrap; aguardando CI em banco efêmero. O Docker local continua inacessível por permissão do canal. Migração criada com a ferramenta oficial, não por diff local; o prefixo UTC do arquivo foi gerado pela ferramenta, enquanto a data deste relatório segue America/Sao_Paulo.

Os testes concorrentes anteriores de governança não provam todos os interleavings de hierarquia/classificação/contrato. O lock da organização não é apresentado como solução integral de concorrência, sucessão ou governança de credenciais de serviço. Não houve nova validação visual de telas autenticadas nem aprovação global de TypeScript. E-mail real, sessões, importação, armazenamento e os demais itens do plano continuam abertos.

As orientações de Supabase levaram a preservar RLS, usar gatilho invoker e retirar o privilégio de exclusão física, sem elevar o acesso de cliente. Referências: [changelog](https://supabase.com/changelog), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) e [privilégios](https://supabase.com/blog/postgres-roles-and-privileges).

## Aplicação e recuperação

Após testes e autorização específica: aplicar somente no projeto aoxibaaydfgffrdqtkva pela conexão Vinha Igrejas; conferir função/gatilho, privilégio DELETE e RLS sem escrever em cadastros reais. Conciliar o nome do arquivo com a versão registrada e publicar a revisão aprovada. Em regressão, reproduzir isoladamente e corrigir seletivamente sem restaurar exclusão física irrestrita ou mudança de sede por cliente.

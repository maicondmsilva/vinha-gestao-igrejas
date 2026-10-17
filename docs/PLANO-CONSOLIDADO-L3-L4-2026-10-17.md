# Consolidação L3 + L4 — operação e financeiro

Referência: 17/10/2026. Dependência: revisão L1/L2 da PR 32, SHA 54e76c1f115683f3daa31cedf5b0f1c5cb2e1973, ainda não aplicada em produção. O pedido de consolidar as fases não equivale ao aceite comercial ou a contratar provedores. Não declarar L3/L4 concluídas.

## Inventário de todos os blocos

| Bloco do plano original | Implementação nesta revisão / estado | Falta para aceite |
|---|---|---|
| L3.1 Homologação isolada | Gate no build recusa Preview sem ambiente test e projeto diferente, com hostname exato; recusa provedores em modo production | Projeto Supabase de teste ou Docker disponível; configurar variáveis Preview, validar domínio e credenciais dos provedores separados. O novo gate pode bloquear prévias antigas mal configuradas intencionalmente |
| L3.2 Backup e restauração | Primitiva AES-256-GCM com nonce aleatório, autenticação e digest; testes com dados exclusivamente sintéticos | Não é exportador nem rotina agendada. Implementar exportação completa, objetos Storage separados, cofre/chave independente, destino externo, retenção e ensaio real |
| L3.3 Monitoramento | Esquema de métricas por lista permitida, sem identidades/corpos/URLs; testes | Conectar a coletor, alertas, cron/filas e plantonista; medir falha, atraso, percentis e indisponibilidade. Função pura não significa monitoramento instalado |
| L3.4 Implantação/rollback | Runbook abaixo; mudanças novas aditivas, financeiro continua não liberado | Ensaiar versões N/N-1, autorização de migração e preservação de gravações posteriores; nenhuma reversão destrutiva automática |
| L3.5 Guia/suporte/incidentes | Procedimentos e checklist abaixo | Responsáveis, canais e prazos acordados; treinamento |
| L3.6 Piloto | Avaliador de sete evidências, exige referência, aprovação, validade de 30 dias e unicidade | Contas/igrejas autorizadas, sessões reais e aceite explícito; não há aprovação automática pelo número de testes |
| L4.1 Livro persistente | Contas de ativo/receita/despesa personalizáveis; diários e partidas por unidade em tabelas Supabase novas; banco protege leitura/escrita por papel/unidade/contrato | Tela e API operacional, centros de custo estruturados, anexos privados financeiros e fluxo de conciliação; núcleo não é ERP concluído |
| L4.2 Integridade financeira | Centavos inteiros, soma zero, gravação/auditoria atômica, repetição por identificador/conteúdo, estorno único sem editar original, fechamento progressivo e bloqueio retroativo | Concorrência específica de fechamento/revogação, homologação contábil de saldo inicial e conciliação real. Fechar livro não comprova conciliar extrato |
| L4.3 Provedores das igrejas | Separação por organização/unidade no livro; nenhuma chamada a gateway neste núcleo | Conta de cada igreja, credenciais segregadas, webhooks e conciliação. Não usar recebedor SaaS para ofertas |
| L4.4 Faturamento Vinha | Preservados contratos/faturas e regras existentes; nenhum preço/fatura alterado nesta entrega | Revisar snapshots históricos, combinações pagador/unidade/desconto/pacote, concorrência e mudança de plano. Não afirmar finalizado por já existir tela |
| L4.5 Recorrência | Adaptador de sandbox existente preservado | Conta sandbox autorizada, ciclo seguinte, cancelamento remoto, falha e reconciliação, prevenção de cobrança dupla; nenhuma cobrança real |
| L4.6 Fiscal | Validações/adaptador de homologação existentes preservados | Contador, município/código/tributos, credenciais, autorização/rejeição/cancelamento/substituição e entrega do documento. Não há nota emitida nesta entrega |
| L4.7 E-mail/WhatsApp | Regras/assinaturas existentes preservadas; Preview só sandbox | SMTP/remetente, domínio, templates Meta, destinatários autorizados, retorno/reexecução e observabilidade. Sem disparos |
| L4.8 Relatórios contábeis | Partidas persistentes permitem apuração posterior por conta/unidade/data | Relatórios/totais e exportação validados no software do contador; sem promessa de obrigação fiscal entregue |

## Isolamento e implantação

Preview Vercel exige `NEXT_PUBLIC_VINHA_ENV=test`, `NEXT_PUBLIC_VINHA_TEST_PROJECT_REF` de um projeto separado e URL `https://<ref>.supabase.co`. Não usar domínio customizado, proxy ou a referência principal aoxibaaydfgffrdqtkva. `VINHA_PROVIDER_MODE`, quando definido em Preview, deve ser sandbox. Isso bloqueia o build mal configurado; não reconfigura automaticamente ambientes existentes nem identifica a natureza de uma credencial secreta. Não copiar segredos de produção para Preview.

O gate não transforma um banco sem clientes em homologação; conferir a referência, aplicar migrações somente no destino autorizado e usar dados sintéticos. Mantido catálogo financeiro em desenvolvimento. As funções novas são APIs de banco experimentais; não disponibilizar a migração no banco principal antes da revisão de segurança.

Implantar: registrar SHA e migrações, validar CI completo, testar N e N-1, confirmar backup recuperável, aplicar alterações compatíveis aprovadas, publicar código correspondente, fazer smoke test e acompanhar erros. Rollback de código não restaura dados. Se houver regressão, suspender a escrita do fluxo afetado, preservar novos dados e produzir correção seletiva; não executar DROP/reset/restauração do banco principal como resposta automática.

## Recuperação — alvos propostos, ainda não medidos

RPO piloto proposto: 24 horas. RTO proposto: 4 horas. São metas, não SLA/resultado medido. Retenção proposta: 7 diários e 4 semanais, sem purga automática nesta revisão. Confirmar capacidade e custo do destino antes de habilitar.

1. Inventariar schema, dados, Auth/configuração, papéis e objetos Storage separadamente. Backup de banco Supabase não contém os bytes dos objetos. Não presumir que dump padrão inclua integralmente Auth/configuração/provedores.
2. Exportar por ferramenta oficial para ambiente protegido, sem imprimir segredos; criptografar com chave em cofre independente. A primitiva fornecida só processa artefatos até 64 MB em memória; para bancos maiores, implementar streaming/ferramenta externa validada. Não particionar dumps SQL arbitrariamente.
3. Inventariar arquivos e hashes, gerar referência do backup e guardar em destino externo com controle de acesso; não commitar dumps, chaves ou dados de clientes no GitHub.
4. Restaurar exclusivamente em projeto temporário autorizado, com e-mail/WhatsApp/cobranças desligados. Validar contagens, vínculos, RLS, contas, saldos, hashes de arquivos e acesso negado entre unidades.
5. Medir distância temporal da cópia e duração da recuperação, registrar falhas e evidências. Só registrar databaseRestore/storageRestore após execução verificável, não após existir arquivo de backup.

## Operação e piloto

Evidências obrigatórias: isolatedPreview, databaseRestore, storageRestore, rollbackRehearsal, monitoring, supportOwner e pilotApproval. O avaliador é uma biblioteca de critérios; ainda não está conectado a um painel/bloqueio de publicação automático.

Incidente: identificar o fluxo, interromper apenas a operação afetada, registrar horário/referência sem PII, acionar responsável, preservar auditoria, corrigir e verificar antes de reabrir. Nunca enviar token/CPF/senha em chat ou log. Definir o dono do incidente e a comunicação ao cliente antes do piloto.

Cliente-piloto: conta confirmada, organização/unidade corretas, primeiro acesso, importação com prévia, delegação restrita, teste de suporte e acompanhamento de erros. Financeiro só entra no piloto após saldo inicial validado, lançamento, transferência, estorno, fechamento e conciliação com extrato/contador. Não editar/apagar movimento confirmado para corrigir valor; usar estorno e novo lançamento. Os sinais das partidas seguem débito positivo/crédito negativo; apresentações de receitas/despesas precisam de adaptação contábil antes da tela final.

## Dependências e limite desta execução

Não informados: destino de backup/cofre, coletor/alertas, ambiente de teste disponível, remetente/SMTP e conta real de teste, acesso sandbox de pagamentos/fiscal, modelos Meta e aceite contábil. Não inventar credenciais, contratar serviços ou enviar mensagens para suprir essas lacunas. Enquanto isso, concluir testes isolados e manter produção sem alterações.

Referências: [Backups Supabase](https://supabase.com/docs/guides/platform/backups), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security). A matriz acima conserva todos os 14 blocos originais; não os transforma em concluídos apenas por consolidá-los.

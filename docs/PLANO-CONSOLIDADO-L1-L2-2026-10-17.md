# Vinha — execução consolidada L1 + L2

Data de referência: 17/10/2026 (America/Sao_Paulo). Base de produção: c72f938493fe7fe4253750bcb6c981d4dd66e74a. Esta entrega substitui a sequência de microblocos por uma revisão integrada. Não declarar as duas fases concluídas por quantidade de testes ou telas.

## Estado de entrega

Código em revisão/homologação, sem aplicar as novas migrações em produção. Conexão autorizada: somente Vinha Igrejas, projeto aoxibaaydfgffrdqtkva. Não há escrita fictícia em clientes, envio de e-mail/WhatsApp, compra de serviço, cobrança nem alteração automática de papéis existentes nesta preparação.

| Frente | O que foi desenvolvido nesta revisão | Aceite ainda necessário |
|---|---|---|
| Autenticação e sessão | Proxy SSR renova cookies no pedido encaminhado e na resposta; APIs continuam verificando identidade e participação | Teste real de expiração, recuperação, MFA e revogação; renovação de cookies não comprova invalidação imediata de todo JWT no Data API |
| Equipe | APIs antigas de usuários/convites/unidades substituídas por Supabase; diretório restrito; convites pessoais confirmados, papel atual do emissor e unidade ativa; não promove participante existente nem reativa suspensão; governança anterior protege último proprietário | Suíte SQL, concorrência própria dos convites, homologação com contas reais e e-mail |
| Hierarquia | Autores e participações dos dois aceites; revalidação/locks na conclusão; RPC administrativa auditada; revogados DML diretos em pedidos/vínculos/pagadores; renovação explícita de aceite legado sem autor; metadados sem compartilhamento operacional de dados | Suíte completa e corrida real entre revogação/aceite e aceite duplicado; revisão visual por papel |
| Importação | CSV com prévia, limites, CPF/data/e-mail, unidade-alvo e contrato; 500 linhas por arquivo, lotes de 100; transação por lote, comprovante de reexecução, nenhum overwrite de duplicados ou criação de login/consentimento | Regressão de interrupção/reexecução, fonte antiga autorizada e reconciliação |
| Membresia | Cadastro transacional anterior preservado; listagem com busca no banco, paginação, filtros e escopo por unidade; apenas complementos dos IDs da página | Teste de navegador e perfis restritos; arquivamento/restauração administrativo não equivale a DELETE físico |
| Arquivos | Bucket privado novo, limite 4 MB, caminho por organização/pessoa, PDF/PNG/JPEG, downloads com autorização atual e attachment; sem URL pública, upsert ou purga de cliente | Testar Storage API em ambiente isolado; não é antivírus; arquivos antigos não são considerados migrados sem origem |
| Dependências | Next 16.3.8, React/ReactDOM/RSC 19.2.8, Vite 8.0.16 e source-map-js 1.2.2 travados; build Vercel local aprovado durante integração | Reexecutar build final e auditoria completa; pnpm audit --prod retornou zero avisos em 17/10, não é certificado de segurança |
| CI/qualidade | Testes de importação/hierarquia/arquivos, SQL e concorrência; verificação estática de segredos e botões; relatório de dependências como artefato | TypeScript global ainda possui dívida; zero avisos de produção não significa zero avisos em ferramentas de build |

## Critérios de segurança

- Funções privilegiadas novas não usam chave de serviço no navegador, metadados editáveis como autorização ou cabeçalhos antigos. São limitadas por conta atual, papel, organização, unidade e operação. Funções invoker existentes e RLS permanecem no caminho de gravação de membros.
- Um convite não concede propriedade, não altera a identidade de uma participação e não restaura suspensão. Papéis altos continuam sob governança existente. A Central mantém operação por RPC autorizado, não por edição livre de dados de aceite.
- Histórico de importação contém resumo, não CSV/CPF bruto. O comprovante é de reexecução do lote, não documento fiscal nem relatório comercial autoritativo. O núcleo administrativo deve usar dados reais e auditoria dos cadastros para reconciliação.
- Arquivos novos não são publicados. Limite e assinatura básica do arquivo não substituem análise antimalware ou validação do conteúdo. Nenhum objeto antigo é movido automaticamente.
- Módulos não migrados continuam contidos. A consulta de vínculo não libera financeiro, Kids ou pessoas de outro ministério. A página de permissões operacionais entre ministérios permanece bloqueada até seu modelo e testes próprios.

## Pendências que não podem ser inventadas

1. Remetente/SMTP e destinatário real autorizado ainda não informados. Não desativar confirmação de e-mail para mascarar a falta. O convite retorna explicitamente emailQueued=false até integração real.
2. Exportação e arquivos do sistema antigo ainda não fornecidos. A nova persistência não comprova que todos os registros antigos chegaram ao destino. Exigir contagens, vínculos, rejeições, mapa de IDs e reconciliação por ministério/unidade.
3. Docker local não disponibilizou o daemon após tentativa de início. Usar banco efêmero do CI, nunca os clientes como ambiente de teste.
4. TypeScript global, abuso de APIs públicas e revogação estrita de sessões ainda exigem fechamento verificável; não esconder erros com desativação de strict ou trocar unknown por any globalmente.
5. Os avisos anteriores do Security Advisor e a proteção de senhas comprometidas precisam de tratamento/classificação individual. Não remover controles apenas para silenciar o diagnóstico.

## Sequência de liberação

1. Executar todas as migrações desde zero e suítes SQL em banco efêmero; corrigir os testes de regressão usando os novos caminhos autorizados, preservando casos negativos.
2. Executar testes da aplicação, build final, auditoria de dependências, análise de segredos e botões; registrar SHA, resultados e limites na PR.
3. Homologar com perfis restritos e sessões, com banco de teste separado e sem provedores financeiros reais.
4. Obter autorização específica para migrações/alterações de acesso na produção e publicar somente o SHA aprovado. Conciliar versões efetivamente registradas no Supabase.
5. Revalidar por leitura, acompanhar erros e corrigir regressões seletivamente sem reabrir permissões amplas.

L3 (backup/restauração, observabilidade, operação e piloto assistido) continua necessária antes da liberação comercial. Não confundir a entrega deste código com aceite integral L1/L2 ou certificação de segurança.

Referências técnicas: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Storage privado](https://supabase.com/docs/guides/storage/buckets/fundamentals), [controle de Storage](https://supabase.com/docs/guides/storage/security/access-control), [SSR](https://supabase.com/docs/guides/auth/server-side/nextjs), [configuração pnpm](https://pnpm.io/settings).

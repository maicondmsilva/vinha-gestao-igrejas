# F3 — contas recebedoras e provedores

## Escopo e referência

Segue o plano fornecido pelo responsável em 20/10/2026: F3 é conexão/abertura de contas recebedoras. Conciliação OFX pertence à F5 e pagamentos automáticos e taxas à F4. O arquivo vazio inicialmente gerado para conciliação foi removido antes de qualquer aplicação.

Local de acesso: Financeiro → Contas recebedoras. Configurações → Financeiro → Recebimentos abre a mesma configuração. A Central possui Contas recebedoras, sem acesso às credenciais. A assinatura da Vinha é independente destas contas.

## Implementação

- Abertura oficial de Mercado Pago, Asaas e Safe2Pay, com situação pendente persistida e retomada da conexão. Nenhuma conta externa é declarada criada por ter aberto um link. Não existe contrato de subcontas integrado configurado; portanto não é chamado endpoint de abertura integrada.
- Mercado Pago: OAuth Authorization Code com PKCE S256; aplicativo e retorno fixo por ambiente. Nenhuma senha pessoal solicitada. Estado aleatório, validade de dez minutos, cookie HttpOnly/SameSite Lax, consumo único no banco, vínculo com conta autenticada, ministério, unidade e ambiente.
- Asaas: conexão por chave oficial, verificações somente de leitura dos dados comerciais e da identificação bancária na base de cada ambiente. Não cria subcontas ou cobranças. Dados completos de documento/conta não são persistidos na configuração pública; identificador protegido por hash. Conferência de destinação exige verificação recente (24 horas); revalidar não é renovar a validade da chave no provedor. Chave protegida no mesmo cofre, sem armazenamento no navegador.
- Troca de código no servidor; validação de `live_mode`, usuário retornado por `/users/me`, país MLB e marcador `test_user` para o ambiente de testes. Ausência ou divergência recusa a conexão, sem inferir ambiente pelo prefixo do token.
- Token de acesso e refresh token protegidos com AES-256-GCM; contexto autenticado inclui ministério/unidade/provedor/ambiente. Chave de 32 bytes em variável exclusivamente de servidor. Nenhum segredo em resposta, auditoria, armazenamento do navegador ou URL de autorização.
- Retorno remove código e estado da URL por redirecionamento, cache privado/no-store e Referrer-Policy no-referrer. Falha após consumo requer nova autorização; não reutiliza código OAuth.
- Renovação explícita consulta novamente identidade. Versão exata impede substituir uma autorização revogada ou alterada enquanto a chamada externa estava em andamento.
- Responsável confirma o titular retornado pelo provedor, conta financeira e igrejas beneficiárias. Somente sede pode atender outras igrejas; todas no mesmo ministério, ativas e com módulo financeiro permitido. A confirmação não substitui a análise cadastral pelo provedor.
- Métodos desejados separados de métodos habilitados. Nenhum método de pagamento é habilitado por marcar uma opção ou conectar uma conta. A habilitação e suas evidências pertencem à homologação F4.
- Revogação local remove os segredos da Vinha e invalida autorizações em andamento. O responsável deve remover a permissão também no painel oficial do provedor para revogação remota. Histórico e dados financeiros preservados.
- Central com segundo fator: leitura operacional sem tokens; gestor pode bloquear com justificativa. Desbloquear exige nova autorização da igreja, não ativa automaticamente recebimentos.

## Segurança

Tabelas no schema privado, RLS e políticas restritivas, sem leitura/escrita direta por clientes ou service_role. Função de prova separada, executável somente pelo serviço; revalida usuário atual confirmado, não anônimo, não removido/suspenso, participação ativa owner/admin, ministério/unidade ativos e decisão do módulo no contrato. Clientes comuns não podem fabricar uma prova de identidade externa.

Somente owner/admin do ministério conecta/configura/revoga. Leitura respeita o acesso financeiro da unidade. Locks ministério → unidade → conexão e versões protegem trocas simultâneas. Retorno atrasado não reativa conexão revogada. Eventos privados e imutáveis, sem token ou verifier no histórico. Não altera antigos endpoints contidos nem relaxa a segurança por remover o rótulo de piloto.

## Configuração externa ainda necessária

1. Definir `FINANCE_RECEIVER_ENCRYPTION_KEY` no servidor, sem enviar a chave pelo chat.
2. Configurar aplicativos OAuth de teste e produção, PKCE e URLs de retorno exatas. Usar `FINANCE_MP_TEST_*` e `FINANCE_MP_LIVE_*` descritas no `.env.example`.
3. Homologar conta vendedora real de teste: autorização, recusa, titular, renovação, expiração, substituição e remoção da permissão no painel oficial.
4. Asaas: código de conexão por chave implementado com transporte fictício; falta homologação externa com conta autorizada. Safe2Pay: abertura oficial e catálogo disponíveis; conector por credenciais e homologação própria continuam pendentes. Não é apresentado como conectado. Acesso à API, prova de titularidade e contratos deverão ser verificados antes de implementar a ativação desse conector.
5. Cadastro integrado/subcontas: depende de acordo técnico/comercial efetivo; o caminho oficial é a alternativa operacional prevista no plano.

Sem esses itens a F3 **não deve ser declarada integralmente homologada**. Nenhuma cobrança ou movimentação real é feita por este código. Não pressupõe que variáveis do antigo financeiro SaaS autorizem automaticamente contas de igrejas.

## Validação por módulo

Retirado o aviso visual de piloto das páginas e banners. O catálogo passa a distinguir `validation`, `ready` e `development`, sem marcar módulos incompletos como prontos. Nomes técnicos antigos permanecem por compatibilidade de código/migrações, não como rótulos de interface. Caminhos legados continuam contidos.

Revisão do plano também identifica itens F2 ainda não entregues no núcleo manual publicado: rateios, recibos emitidos pela aplicação e aprovação segregada por valor/responsabilidade. A entrega F2 anterior é um subconjunto operacional manual, não comprovação de conclusão de todo o plano anexado. Esses itens precisam ser retomados e homologados, sem habilitação fictícia nesta F3.

## Testes e implantação

Aplicação: `scripts/finance-f3.test.mjs`; banco: `supabase/tests/finance_f3.sql`; execução isolada com rollback: `scripts/local-finance-f3-test.mjs --local-synthetic`. Os testes de transporte usam respostas fictícias; não provam homologação externa. Recibo de publicação deve registrar o commit, CI, migração e implantação reais; este documento não comprova publicação.

Referências oficiais consultadas: https://www.mercadopago.com.br/developers/pt/docs/security/oauth/creation ; https://docs.asaas.com/reference/criar-subconta ; https://developers.safe2pay.com.br/reference/autentica%C3%A7%C3%A3o ; https://supabase.com/docs/guides/database/functions .

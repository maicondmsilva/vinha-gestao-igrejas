# Células — arquivos, consolidação e canais

Complementa a entrega interna anterior. Publicação de código não equivale a entrega de e-mail/WhatsApp.

## Estudos e arquivos

Salve primeiro o estudo em Materiais e estudos. Seu cartão oferece arquivos privados PDF, PNG ou JPEG de até 4 MB. O servidor detecta assinatura do conteúdo, não confia no nome/MIME enviado. Nomes físicos são UUIDs; a lista mostra os cem arquivos mais recentes de cada estudo. Não há execução/visualização HTML, sobrescrita, movimentação ou exclusão física por clientes. Download é anexo e revalida a autorização a cada solicitação, sem URL pública ou link assinado que sobreviva a uma revogação. Gestores podem enviar; supervisores somente ler os estudos publicados de seu escopo. Arquivar o estudo retira o acesso de supervisores. PDF não é garantia de conteúdo inofensivo: não há antivírus/CDR nesta entrega; não abrir anexos desconhecidos fora do ambiente de confiança.

## Consolidação de unidades

Em Indicadores por rede, abrir “Consolidar unidades do ministério”, selecionar unidades e consultar o período (até 366 dias). Um único snapshot do banco agrega o escopo autorizado em cada unidade. Até cem unidades e dez mil grupos, recusando o excesso, sem truncar totais. Uma unidade proibida/bloqueada recusa a consulta inteira. A consolidação não concede acesso, não agrupa ministérios diferentes por vínculo comercial e não expõe nomes de membros. Pessoas distintas são deduplicadas por cadastro, não por nome/CPF. Não mescla automaticamente cadastros duplicados em unidades distintas. A rede corresponde à associação atual dos grupos.

## Agendamento interno

Job do Supabase Cron `vinha-cell-report-reminders`: `0 11 * * *`, 08h em São Paulo. Executa exclusivamente `private.run_cell_reminders()`. Não usa Vercel, não depende de CRON_SECRET, não chama cobrança nem envia mensagens externas. Migração cria o job inativo; após CI/homologação é ativado e uma execução real do scheduler deve ser observada em `cron.job_run_details`, restaurando então o horário diário. Não se deve declarar ativo sem essa evidência.

Lotes limitados, cursor persistente e avisos deduplicados. A função registra apenas horário e contagens em `private.cell_reminder_runs`. Falha de execução fica no histórico do Cron; não inventa sucesso. Usuários, anônimos e service_role não podem chamar essa função diretamente. O scanner antigo continua deduplicado, mas não precisa ser acionado junto da rotina financeira.

## Preferências e entrega externa

Em Pendências e avisos → Meus canais de aviso, cada pessoa pode consentir/retirar os próprios canais por unidade. E-mail usa o endereço atual confirmado da conta. WhatsApp exige telefone confirmado na autenticação; não aceita números digitados livremente. A ativação de verificação de telefone via provedor/OTP não é implementada por esta entrega. Nenhum opt-in é criado automaticamente.

Só avisos novos posteriores ao consentimento entram na fila. Antes do claim, o banco revalida conta, unidade, ministério, módulos/contrato, concessão, pendência e preferências. A autorização é a do instante do claim; uma revogação posterior não pode recolher uma mensagem já aceita pelo provedor. As mensagens são genéricas: não enviam nomes, presença ou conteúdo dos grupos. O acesso aos detalhes exige login. Não enviar histórico antigo em massa.

Fila privada, uma mensagem por aviso/canal, claim exclusivo e token de finalização. `submitted` significa aceito pelo provedor, não entregue/lido. Falha ou claim abandonado vira `uncertain`, sem retry automático para evitar duplicidade. Não há webhook de entrega/bounce nesta versão. Reconciliar no provedor antes de qualquer reenvio administrativo. Chamadas HTTP e SMTP têm limites de tempo; uma execução processa até 25 mensagens. `pending` sem execução não é entrega confirmada.

### Hostinger (server-only)

Configurar no ambiente de produção, sem enviar senhas ao chat, Git ou arquivos públicos:

- `CELL_EMAIL_ENABLED=true`
- `CELL_SMTP_HOST=smtp.hostinger.com`
- `CELL_SMTP_PORT=465` (TLS) ou `587` (STARTTLS obrigatório)
- `CELL_SMTP_USER=notificacoes@vinhaigrejas.com.br`
- `CELL_SMTP_PASSWORD`: senha da caixa, digitada pelo responsável no gerenciador de segredos.

SMTP de Auth no Supabase permanece independente. O código não lê/copia sua senha. TLS e validação de certificado não podem ser desligados. Remetente Vinha, assunto e conteúdo em português.

### WhatsApp oficial

É necessária conta Meta, número remetente, credencial de serviço e modelo aprovado em português sem parâmetros, de categoria apropriada ao aviso transacional. O texto deve orientar consultar Células → Pendências e avisos; não incluir dados de membros.

- `CELL_WHATSAPP_ENABLED=true`
- `CELL_WHATSAPP_PHONE_ID`
- `CELL_WHATSAPP_API_VERSION`: versão Graph suportada pela conta, verificada na configuração.
- `CELL_WHATSAPP_TEMPLATE`: nome do modelo aprovado, sem parâmetros.
- `CELL_WHATSAPP_TOKEN`: segredo de serviço.

### Execução da fila externa

Endpoint isolado `GET /api/cell-deliveries/run`, protegido por `Authorization: Bearer <CELL_DELIVERY_CRON_SECRET>`. Gerar e cadastrar segredo longo no gerenciador de segredos; não reutilizar credenciais do usuário ou chave de banco. Provedor/agendador precisa enviar esse cabeçalho. A rotina geral de ciclo de vida NÃO é usada como teste, pois processa cobrança. Sem canais completos, retorna `waitingConfiguration`, sem claim/envio. Não cadastrar cron externo até configurar canais e homologar com destinatário autorizado. Na Vercel Cron, o nome padrão do segredo é CRON_SECRET; este endpoint usa segredo próprio, portanto usar agendador com cabeçalho configurável ou extensão controlada posterior, sem supor autenticação automática da Vercel.

Pendências externas: configuração segura SMTP, conta/modelo Meta, verificação do telefone do usuário, teste real de entrega e agendador externo autenticado. Código implementado e testes com provedores simulados não removem essas dependências.

// E-mails de autenticação (Supabase Auth) no padrão Vinha.
// Uso: node scripts/auth-emails.mjs            → gera os HTML em supabase/email-templates/
//      REF=<projeto> node scripts/auth-emails.mjs --apply   → também aplica no projeto (via API de gestão)
// Membros do app recebem o texto com o nome da pessoa e da igreja (dados enviados na criação da conta);
// administradores que criam o ministério pelo site recebem o texto da Vinha.
import {mkdirSync, writeFileSync} from 'node:fs';

const c = {
  brand: '#285c45',
  dark: '#163d2f',
  soft: '#e5eee8',
  gold: '#dbbb70',
  goldDeep: '#7f6420',
  bg: '#f5f6f2',
  line: '#dce6df',
  ink: '#1f2a22',
  muted: '#5f6f64',
};
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const hello = `{{ if .Data.full_name }}Olá, {{ .Data.full_name }}!{{ else }}Olá!{{ end }}`;
const church = `{{ if .Data.church_name }}{{ .Data.church_name }}{{ else }}sua igreja{{ end }}`;

function layout({title, preheader, over, heading, body, button, url, code, note}) {
  const btn = button
    ? `<tr><td style="padding:8px 0 4px"><a href="${url}" style="display:inline-block;background:${c.brand};color:#ffffff;text-decoration:none;font-weight:700;font-size:16px;padding:15px 28px;border-radius:14px">${button}</a></td></tr>
<tr><td style="padding:14px 0 0;font-size:13px;line-height:20px;color:${c.muted}">Se o botão não abrir, copie e cole este endereço no navegador:<br><span style="word-break:break-all;color:${c.brand}">${url}</span></td></tr>`
    : '';
  const codeBox = code
    ? `<tr><td style="padding:18px 0 4px"><div style="display:inline-block;background:${c.soft};border:1px dashed ${c.brand};border-radius:14px;padding:14px 22px;font-size:28px;letter-spacing:6px;font-weight:800;color:${c.dark};font-family:'Courier New',monospace">{{ .Token }}</div></td></tr>`
    : '';
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${esc(title)}</title></head>
<body style="margin:0;padding:0;background:${c.bg};font-family:'Segoe UI',Arial,Helvetica,sans-serif;color:${c.ink}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${preheader}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${c.bg}"><tr><td align="center" style="padding:28px 14px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:580px;background:#ffffff;border:1px solid ${c.line};border-radius:22px;overflow:hidden">
<tr><td style="background:${c.dark};padding:26px 30px;border-bottom:4px solid ${c.gold}">
 <table role="presentation" cellspacing="0" cellpadding="0"><tr>
  <td style="width:46px;height:46px;background:${c.brand};border-radius:14px;text-align:center;vertical-align:middle;color:${c.gold};font-family:Georgia,serif;font-size:26px;font-weight:700">V</td>
  <td style="padding-left:14px;color:#ffffff"><div style="font-size:20px;font-weight:800;letter-spacing:.3px">{{ if .Data.app_name }}{{ .Data.app_name }}{{ else }}Vinha{{ end }}</div>
   <div style="font-size:12px;color:${c.gold};letter-spacing:1.5px;text-transform:uppercase">{{ if .Data.church_name }}{{ .Data.church_name }}{{ else }}Gestão que frutifica{{ end }}</div></td>
 </tr></table>
</td></tr>
<tr><td style="padding:30px 30px 8px">
 <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
 <tr><td style="font-size:11px;font-weight:700;letter-spacing:2px;color:${c.goldDeep};text-transform:uppercase;padding-bottom:8px">${over}</td></tr>
 <tr><td style="font-size:24px;line-height:31px;font-weight:800;color:${c.dark};padding-bottom:14px">${heading}</td></tr>
 <tr><td style="font-size:16px;line-height:25px;color:${c.ink};padding-bottom:18px">${body}</td></tr>
 ${btn}${codeBox}
 </table>
</td></tr>
<tr><td style="padding:18px 30px 26px"><div style="background:${c.soft};border-radius:16px;padding:14px 16px;font-size:13px;line-height:20px;color:${c.muted}">${note}</div></td></tr>
<tr><td style="border-top:1px solid ${c.line};padding:18px 30px 24px;font-size:12px;line-height:19px;color:${c.muted}">
 Mensagem automática. Nunca pedimos sua senha ou código por telefone, WhatsApp ou chat.<br>
 Enviado com <b style="color:${c.brand}">Vinha</b> · <a href="https://vinhaigrejas.com.br" style="color:${c.brand};text-decoration:none">vinhaigrejas.com.br</a>
</td></tr>
</table></td></tr></table></body></html>`;
}

const sentTo = `Este e-mail foi enviado para <b>{{ .Email }}</b>.`;
const ignore = `Se não foi você, é só ignorar: nada muda na sua conta.`;
export const templates = {
  confirmation: {
    subject: '{{ if .Data.church_name }}Confirme seu e-mail · {{ .Data.church_name }}{{ else }}Confirme seu e-mail na Vinha{{ end }}',
    html: layout({
      title: 'Confirme seu e-mail',
      preheader: 'Falta só um passo para entrar.',
      over: '{{ if .Data.church_name }}Sua conta no aplicativo{{ else }}Sua conta Vinha{{ end }}',
      heading: hello,
      body: `{{ if .Data.church_name }}Que alegria ter você com a gente! Você criou sua conta no aplicativo da <b>${church}</b>. Falta só confirmar este e-mail para entrar com a senha que você escolheu.<br><br>Depois de entrar, abra <b>Menu › Meu perfil</b> para completar seu cadastro e enviar para a igreja.{{ else }}Falta só confirmar seu e-mail para continuar o cadastro do seu ministério com segurança.{{ end }}`,
      button: 'Confirmar meu e-mail',
      url: '{{ .ConfirmationURL }}',
      note: `${sentTo} ${ignore}`,
    }),
  },
  recovery: {
    subject: 'Crie uma nova senha{{ if .Data.app_name }} · {{ .Data.app_name }}{{ else }} · Vinha{{ end }}',
    html: layout({
      title: 'Nova senha',
      preheader: 'Use o botão para criar uma nova senha.',
      over: 'Recuperar acesso',
      heading: 'Vamos criar uma nova senha',
      body: `${hello} Recebemos um pedido para trocar a senha da sua conta. Toque no botão abaixo e escolha uma senha nova. O link vale por 1 hora.`,
      button: 'Criar nova senha',
      url: '{{ .ConfirmationURL }}',
      note: `${sentTo} Se você não pediu a troca, ignore esta mensagem: sua senha atual continua valendo.`,
    }),
  },
  magic_link: {
    subject: 'Seu link de acesso{{ if .Data.app_name }} · {{ .Data.app_name }}{{ else }} · Vinha{{ end }}',
    html: layout({
      title: 'Link de acesso',
      preheader: 'Entre com um toque.',
      over: 'Acesso rápido',
      heading: 'Seu link para entrar',
      body: `${hello} Toque no botão para entrar na sua conta sem digitar a senha. O link vale por 1 hora e só funciona uma vez.`,
      button: 'Entrar agora',
      url: '{{ .ConfirmationURL }}',
      note: `${sentTo} ${ignore}`,
    }),
  },
  email_change: {
    subject: 'Confirme seu novo e-mail{{ if .Data.app_name }} · {{ .Data.app_name }}{{ else }} · Vinha{{ end }}',
    html: layout({
      title: 'Novo e-mail',
      preheader: 'Confirme a troca do seu e-mail.',
      over: 'Troca de e-mail',
      heading: 'Confirme o novo endereço',
      body: `${hello} Você pediu para trocar o e-mail da sua conta de <b>{{ .Email }}</b> para <b>{{ .NewEmail }}</b>. Toque no botão para confirmar.`,
      button: 'Confirmar novo e-mail',
      url: '{{ .ConfirmationURL }}',
      note: `Se você não pediu esta troca, ignore esta mensagem e avise a secretaria da sua igreja.`,
    }),
  },
  invite: {
    subject: 'Você recebeu um convite{{ if .Data.church_name }} · {{ .Data.church_name }}{{ else }} da Vinha{{ end }}',
    html: layout({
      title: 'Convite',
      preheader: 'Aceite o convite para acessar.',
      over: 'Convite',
      heading: 'Você foi convidado',
      body: `${hello} Você recebeu um convite para acessar {{ if .Data.church_name }}a <b>{{ .Data.church_name }}</b>{{ else }}a Vinha{{ end }}. Toque no botão para aceitar e criar sua senha.`,
      button: 'Aceitar convite',
      url: '{{ .ConfirmationURL }}',
      note: `${sentTo} Se você não esperava este convite, ignore esta mensagem.`,
    }),
  },
  reauthentication: {
    subject: 'Seu código de verificação{{ if .Data.app_name }} · {{ .Data.app_name }}{{ else }} · Vinha{{ end }}',
    html: layout({
      title: 'Código de verificação',
      preheader: 'Use este código para confirmar.',
      over: 'Verificação de segurança',
      heading: 'Seu código',
      body: `${hello} Use o código abaixo para confirmar que é você. Ele vale por poucos minutos.`,
      code: true,
      note: `${sentTo} Nunca compartilhe este código com ninguém.`,
    }),
  },
};
const notice = (key, subject, heading, body) => ({
  subject: subject + '{{ if .Data.app_name }} · {{ .Data.app_name }}{{ else }} · Vinha{{ end }}',
  html: layout({
    title: heading,
    preheader: heading,
    over: 'Aviso de segurança',
    heading,
    body: `${hello} ${body}`,
    note: `Se não foi você, troque sua senha agora e avise a secretaria da sua igreja.`,
  }),
});
Object.assign(templates, {
  password_changed_notification: notice('password', 'Sua senha foi alterada', 'Sua senha foi alterada', 'A senha da sua conta acabou de ser trocada.'),
  email_changed_notification: notice(
    'email',
    'Seu e-mail foi alterado',
    'Seu e-mail foi alterado',
    'O e-mail da sua conta foi trocado para <b>{{ .Email }}</b>.',
  ),
  phone_changed_notification: notice('phone', 'Seu telefone foi alterado', 'Seu telefone foi alterado', 'O telefone da sua conta foi alterado.'),
  mfa_factor_enrolled_notification: notice(
    'mfa+',
    'Nova verificação de segurança',
    'Nova verificação de segurança',
    'Uma nova forma de verificação foi adicionada à sua conta.',
  ),
  mfa_factor_unenrolled_notification: notice(
    'mfa-',
    'Verificação de segurança removida',
    'Verificação de segurança removida',
    'Uma forma de verificação foi removida da sua conta.',
  ),
  identity_linked_notification: notice('id+', 'Novo jeito de entrar vinculado', 'Novo jeito de entrar', 'Um novo método de acesso foi vinculado à sua conta.'),
  identity_unlinked_notification: notice('id-', 'Jeito de entrar removido', 'Método de acesso removido', 'Um método de acesso foi removido da sua conta.'),
});

export function authConfigPatch() {
  // O nome do remetente só pode ser definido em projetos com SMTP próprio (produção).
  const patch = process.env.NO_SENDER ? {} : {smtp_sender_name: 'Vinha'};
  for (const [k, t] of Object.entries(templates)) {
    patch[`mailer_subjects_${k}`] = t.subject;
    patch[`mailer_templates_${k}_content`] = t.html;
  }
  return patch;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = new URL('../supabase/email-templates/', import.meta.url);
  mkdirSync(dir, {recursive: true});
  for (const [k, t] of Object.entries(templates)) writeFileSync(new URL(`${k}.html`, dir), t.html);
  console.log('gerados:', Object.keys(templates).length);
  if (process.argv.includes('--apply')) {
    const ref = process.env.REF;
    if (!ref) throw Error('Informe REF=<projeto>.');
    const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/config/auth`, {
      method: 'PATCH',
      headers: {Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN || 'proxy-injected'}`, 'Content-Type': 'application/json'},
      body: JSON.stringify(authConfigPatch()),
    });
    console.log('aplicado em', ref, r.status);
    if (!r.ok) console.log((await r.text()).slice(0, 400));
  }
}

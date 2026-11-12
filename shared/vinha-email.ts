// Base única dos e-mails enviados pelo sistema Vinha (mesmo visual dos modelos do Supabase Auth).
// Referência visual: docs/email/vinha-base.html.

export type VinhaEmail={title:string;intro:string;items?:string[];note?:string;action?:{label:string;url:string};church?:string};

const esc=(v:string)=>v.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const httpsUrl=(v:string)=>{try{const u=new URL(v);return u.protocol==='https:'&&!u.username&&!u.password?u.toString():null}catch{return null}};

export function vinhaEmail({title,intro,items=[],note,action,church}:VinhaEmail):{html:string;text:string}{
 const href=action?httpsUrl(action.url):null;
 if(action&&!href)throw Error('Link do e-mail inválido.');
 const list=items.length?'<ul style="margin:0 0 22px;padding:0 0 0 20px;font-size:15px;line-height:1.8;color:#263f32;">'+items.map(i=>'<li style="margin:0 0 4px;">'+esc(i)+'</li>').join('')+'</ul>':'';
 const button=href?'<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 24px;"><tr><td style="background:#285c45;border-radius:9px;"><a href="'+esc(href)+'" style="display:inline-block;padding:16px 24px;font-size:15px;color:#ffffff;text-decoration:none;font-weight:bold;border-radius:9px;">'+esc(action!.label)+'</a></td></tr></table><p style="font-size:12px;line-height:1.7;word-break:break-all;">Se o botão não abrir, copie e cole este link no navegador:<br><a href="'+esc(href)+'" style="color:#285c45;">'+esc(href)+'</a></p>':'';
 const html='<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>'+esc(title)+'</title></head>'
  +'<body style="margin:0;padding:0;background:#f2f5f1;font-family:Arial,Helvetica,sans-serif;color:#263f32;">'
  +'<div style="display:none;max-height:0;overflow:hidden;opacity:0;">'+esc(title)+' — Vinha · Gestão que frutifica.</div>'
  +'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f5f1;"><tr><td align="center" style="padding:32px 16px;">'
  +'<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #dce5dd;border-radius:18px;overflow:hidden;">'
  +'<tr><td style="background:#193f30;padding:30px 34px;border-bottom:4px solid #d9b960;"><table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="width:48px;height:48px;border:1px solid #96b49e;border-radius:12px;color:#ffffff;text-align:center;font-family:Georgia,serif;font-size:30px;">V</td><td style="padding-left:14px;color:#ffffff;"><div style="font-family:Georgia,serif;font-size:29px;font-weight:bold;">Vinha</div><div style="font-size:11px;color:#d5e3d6;line-height:20px;">Gestão que frutifica</div></td></tr></table></td></tr>'
  +'<tr><td style="padding:36px 34px 18px;">'+(church?'<div style="font-size:11px;letter-spacing:2px;color:#6f806f;font-weight:bold;">'+esc(church.toUpperCase())+'</div>':'')
  +'<h1 style="font-family:Georgia,serif;font-size:27px;line-height:1.3;color:#193f30;margin:16px 0 20px;">'+esc(title)+'</h1>'
  +'<p style="font-size:15px;line-height:1.8;margin:0 0 18px;white-space:pre-wrap;">'+esc(intro)+'</p>'+list
  +(note?'<p style="font-size:15px;line-height:1.8;margin:0 0 22px;padding:12px 16px;background:#f6f1e2;border-left:4px solid #d9b960;border-radius:6px;white-space:pre-wrap;">'+esc(note)+'</p>':'')
  +button+'<p style="font-size:13px;line-height:1.8;margin:20px 0 0;">Conte com a gente,<br><strong>'+esc(church||'Equipe Vinha')+'</strong></p></td></tr>'
  +'<tr><td style="padding:22px 34px 30px;"><div style="border-top:1px solid #e3e9e2;padding-top:20px;font-size:11px;line-height:1.9;color:#768478;">'+(church?esc(church)+' · ':'')+'Você recebeu este e-mail porque tem cadastro na Vinha.<br>A Vinha nunca solicita sua senha ou seu código por chat.<br><a href="https://vinhaigrejas.com.br" style="color:#285c45;text-decoration:none;">vinhaigrejas.com.br</a></div></td></tr>'
  +'</table></td></tr></table></body></html>';
 const text=[title,'',intro,...(items.length?['',...items.map(i=>'- '+i)]:[]),...(note?['',note]:[]),...(href?['',action!.label+': '+href]:[]),'','— '+(church||'Equipe Vinha'),'Você recebeu este e-mail porque tem cadastro na Vinha.'].join('\n');
 return{html,text};
}

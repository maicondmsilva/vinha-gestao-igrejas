export function organizationInviteToken(value:unknown):string|null{
 return typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)?value:null;
}
export function organizationInviteError(message:string){
 if(message.includes('confirmed_email_required'))return 'Confirme seu e-mail antes de ativar o ministério.';
 if(message.includes('invite_email_mismatch'))return 'Entre com o mesmo e-mail que recebeu o convite.';
 if(message.includes('invite_expired'))return 'Este convite expirou. Solicite um novo link à equipe da Vinha.';
 if(message.includes('invite_access_revoked')||message.includes('invite_existing_membership'))return 'Seu vínculo precisa ser revisado pela equipe da Vinha. O convite não altera nem reativa acessos existentes.';
 if(message.includes('authentication_required'))return 'Entre ou crie sua conta para ativar a organização.';
 return 'Convite inválido ou indisponível. Solicite o link atual à equipe da Vinha.';
}

export const memberFields=[['full_name','Nome completo'],['phone','Telefone'],['birth_date','Nascimento (AAAA-MM-DD)'],['gender','Gênero'],['marital_status','Estado civil'],['cpf','CPF (somente números)'],['postal_code','CEP'],['street','Rua'],['number','Número'],['complement','Complemento'],['district','Bairro'],['city','Cidade'],['state','UF']] as const;
export type AppConfig={id:string;name:string;appName:string;primary:string;accent:string;logo:string|null;units:{id:string;name:string;city?:string}[]};
export type MemberProfile={personId:string|null;unitId:string|null;profile:Record<string,string>|null;membershipStatus:string|null;requests:{id:string;kind:string;status:string;payload:Record<string,string>;acceptedFields:string[];reason:string|null;createdAt:string}[]};
export function memberError(code?:string,message=''){
 if(message.includes('member_request_pending'))return 'Você já tem uma solicitação aguardando revisão.';
 if(code==='40001')return 'O cadastro mudou ou exige conferência de identidade. Atualize a consulta e procure a administração da igreja.';
 if(code==='42501')return 'Acesso indisponível. Confirme seu e-mail e verifique seu vínculo com a igreja.';
 if(['22023','22007','22008','23514'].includes(code||''))return 'Revise os campos. Use data AAAA-MM-DD, CPF com 11 números e UF com duas letras maiúsculas.';
 return 'Não foi possível confirmar a operação. Atualize antes de tentar novamente.';
}

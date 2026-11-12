export const memberFields=[['full_name','Nome completo'],['phone','Telefone'],['birth_date','Data de nascimento'],['gender','Gênero'],['marital_status','Estado civil'],['cpf','CPF'],['postal_code','CEP'],['street','Rua'],['number','Número'],['complement','Complemento'],['district','Bairro'],['city','Cidade'],['state','UF']] as const;
export type AppConfig={id:string;name:string;appName:string;primary:string;accent:string;logo:string|null;units:{id:string;name:string;city?:string}[]};
export type MemberProfile={personId:string|null;unitId:string|null;profile:Record<string,string>|null;membershipStatus:string|null;requests:{id:string;kind:string;status:string;payload:Record<string,string>;acceptedFields:string[];reason:string|null;createdAt:string}[]};
export function memberError(code?:string,message=''){
 if(message.includes('member_request_pending'))return 'Você já tem uma solicitação aguardando revisão.';
 if(message.includes('member_identity_conflict'))return 'O cadastro escolhido não confere com esta conta (e-mail ou CPF) ou já está ligado a outra conta. Escolha outro cadastro ou crie um novo.';
 if(code==='40001')return 'O cadastro mudou ou exige conferência de identidade. Atualize a consulta e procure a administração da igreja.';
 if(code==='42501')return 'Acesso indisponível. Confirme seu e-mail e verifique seu vínculo com a igreja.';
 if(['22023','22007','22008','23514'].includes(code||''))return 'Revise a data de nascimento, os 11 números do CPF e a UF selecionada.';
 return 'Não foi possível confirmar a operação. Atualize antes de tentar novamente.';
}

export function safeNext(value:string|null|undefined,fallback='/acesso'){
 if(!value||!value.startsWith('/')||value.startsWith('//')||/[\\\r\n]/.test(value))return fallback;
 return value;
}
export function inviteStatus(status:string){return{disabled:status==='revoked'||status==='expired',label:status==='accepted'?'Acessar meu ministério':status==='revoked'?'Convite cancelado':status==='expired'?'Convite expirado':'Entrar e ativar organização'}}

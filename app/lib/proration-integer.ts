/** Refuse JSON numbers already rounded by the database transport. */
export function exactProrationInteger(value:unknown,signed=false){
 if(typeof value==='number'&&!Number.isSafeInteger(value))throw Error('Inteiro sem precisão confirmada.');
 if(typeof value!=='string'&&typeof value!=='number')throw Error('Inteiro ausente.');
 const text=String(value);
 if(!(signed?/^-?\d{1,50}$/:/^\d{1,50}$/).test(text))throw Error('Inteiro inválido.');
 return text;
}
export function safeProrationNumber(value:unknown){
 const number=Number(exactProrationInteger(value));
 if(!Number.isSafeInteger(number))throw Error('Inteiro fora da faixa suportada.');
 return number;
}

export const eventPaymentMethods=[['pix','Pix'],['card','Cartão'],['boleto','Boleto']] as const;
/** Only the server-provided order snapshot may narrow the verified receiver. */
export function eventCheckoutMethods(available:string[]|undefined,snapshot:unknown):string[]|undefined{
 if(snapshot===null||snapshot===undefined)return available; // Orders created before method snapshots.
 if(!Array.isArray(snapshot)||!snapshot.length||snapshot.length>3||new Set(snapshot).size!==snapshot.length||snapshot.some(x=>typeof x!=='string'||!eventPaymentMethods.some(([id])=>id===x)||!available?.includes(x)))throw Error('As formas de pagamento deste pedido não estão disponíveis.');
 return snapshot;
}

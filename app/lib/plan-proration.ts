// Pure quote only. Contract/payer authorization and atomic persistence belong to
// the server transaction; never trust a browser quote to create an invoice.
export type ProrationInput={currentNetCents:number;nextNetCents:number;cycleStart:number;cycleEnd:number;effectiveAt:number};
export function quotePlanProration(input:ProrationInput){
 const {currentNetCents,nextNetCents,cycleStart,cycleEnd,effectiveAt}=input;
 if(![currentNetCents,nextNetCents,cycleStart,cycleEnd,effectiveAt].every(Number.isSafeInteger)||currentNetCents<0||nextNetCents<0||cycleStart<0||cycleEnd<=cycleStart||effectiveAt<cycleStart||effectiveAt>cycleEnd)throw Error('Preço líquido ou ciclo inválido.');
 const duration=BigInt(cycleEnd)-BigInt(cycleStart),remaining=BigInt(cycleEnd)-BigInt(effectiveAt);
 const difference=BigInt(nextNetCents)-BigInt(currentNetCents),numerator=difference*remaining;
 const absolute=numerator<BigInt(0)?-numerator:numerator;
 // Half away from zero, in integer cents; preserve rational basis for auditing.
 const rounded=(absolute*BigInt(2)+duration)/(duration*BigInt(2));
 const signed=numerator<BigInt(0)?-rounded:rounded;
 return {policy:'immediate-proration-v1',effectiveAt,cycleStart,cycleEnd,currentNetCents:String(currentNetCents),nextNetCents:String(nextNetCents),basisNumerator:String(numerator),basisDenominator:String(duration),adjustmentCents:String(signed),chargeCents:String(signed>BigInt(0)?signed:BigInt(0)),creditCents:String(signed<BigInt(0)?-signed:BigInt(0)),creditDestination:'next_invoice',automaticRefund:false} as const;
}

import {quotePlanProration,type ProrationInput} from './plan-proration.ts';
/** Mirrors cumulative rounding in the transactional pilot. Never authorizes a write. */
export function previewCumulativeProration(input:ProrationInput&{accumulatedNumerator:string;roundedAdjustmentCents:string}){
 const quote=quotePlanProration(input);
 const signed=(value:string)=>{if(!/^-?\d{1,50}$/.test(value))throw Error('Histórico proporcional inválido.');return BigInt(value)};
 const previous=signed(input.accumulatedNumerator),previousRounded=signed(input.roundedAdjustmentCents),denominator=BigInt(quote.basisDenominator);
 const round=(value:bigint)=>{const absolute=value<BigInt(0)?-value:value;const amount=(absolute*BigInt(2)+denominator)/(denominator*BigInt(2));return value<BigInt(0)?-amount:amount};
 if(round(previous)!==previousRounded)throw Error('Histórico proporcional inconsistente. Atualize a consulta.');
 const accumulated=previous+BigInt(quote.basisNumerator),rounded=round(accumulated),delta=rounded-previousRounded;
 return {...quote,adjustmentCents:String(delta),chargeCents:String(delta>BigInt(0)?delta:BigInt(0)),creditCents:String(delta<BigInt(0)?-delta:BigInt(0)),accumulatedNumerator:String(accumulated),roundedAdjustmentCents:String(rounded),estimateOnly:true} as const;
}

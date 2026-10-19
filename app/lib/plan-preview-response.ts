export function readPlanPreview(value:unknown,contractId:string,nextPlanId:string){
 if(!value||typeof value!=='object')throw Error('Prévia não confirmada.');
 const data=value as Record<string,unknown>,estimate=data.estimate as Record<string,unknown>|undefined;
 if(data.pilot!==true||data.confirmationAvailable!==false||data.contractId!==contractId||data.nextPlanId!==nextPlanId||!estimate||estimate.estimateOnly!==true||estimate.automaticRefund!==false||estimate.creditDestination!=='next_invoice')throw Error('Prévia incompatível com a seleção.');
 for(const field of ['chargeCents','creditCents','currentNetCents','nextNetCents'])if(typeof estimate[field]!=='string'||!/^\d{1,30}$/.test(estimate[field] as string))throw Error('Valor da prévia inválido.');
 if(BigInt(estimate.chargeCents as string)>BigInt(0)&&BigInt(estimate.creditCents as string)>BigInt(0))throw Error('Ajuste da prévia inconsistente.');
 for(const field of ['effectiveAt','cycleStart','cycleEnd'])if(!Number.isSafeInteger(estimate[field]))throw Error('Período inválido.');
 if(Number(estimate.cycleStart)>Number(estimate.effectiveAt)||Number(estimate.effectiveAt)>=Number(estimate.cycleEnd))throw Error('Período encerrado ou inválido.');
 return{chargeCents:estimate.chargeCents as string,creditCents:estimate.creditCents as string,currentNetCents:estimate.currentNetCents as string,nextNetCents:estimate.nextNetCents as string,effectiveAt:Number(estimate.effectiveAt),cycleEnd:Number(estimate.cycleEnd)};
}

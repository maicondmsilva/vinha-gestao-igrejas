import {requireValue,type Row} from './operations';
export function billingPreferences(data:Row,existing:Row|null){
 const number=String(data.whatsappNumber||'').replace(/\D/g,'');
 requireValue(!data.whatsappEnabled||data.whatsappConsent===true&&/^[0-9]{10,15}$/.test(number),'Informe número com DDI/DDD e confirme a autorização para WhatsApp.');
 return{email_enabled:!!data.emailEnabled,whatsapp_enabled:!!data.whatsappEnabled,whatsapp_number:number,whatsapp_consent_at:data.whatsappEnabled?(existing?.whatsapp_number===number?existing?.whatsapp_consent_at||new Date().toISOString():new Date().toISOString()):null};
}

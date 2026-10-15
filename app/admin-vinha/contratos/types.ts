export type Unit={id:string;name:string;organization_id:string;unit_type:string;registration_code:number};
export type Contract={id:string;unit_id:string;payer_unit_id:string;plan_id:string;status:string;module_decisions:Record<string,boolean>;requested_modules:string[];requested_due_day:number|null;request_updated_at:string|null;due_day:number;financial_profile:Record<string,string>;email_enabled:boolean;whatsapp_enabled:boolean;whatsapp_number:string;whatsapp_consent_at:string|null;autopay_requested:boolean};
export type Plan={id:string;name:string;active:boolean;base_price_cents:number};
export type Module={code:string;name:string;active:boolean;monthly_price_cents:number};
export type ContractData={error?:string;units:Unit[];contracts:Contract[];plans:Plan[];modules:Module[];planModules:{plan_id:string;module_code:string;included:boolean}[]};
export type ContractForm={planId:string;payerUnitId:string;status:string;dueDay:number;modules:Record<string,boolean>;profile:Record<string,string>;emailEnabled:boolean;whatsappEnabled:boolean;whatsappNumber:string;whatsappConsent:boolean;autopayRequested:boolean};
export const emptyContract:ContractForm={planId:'',payerUnitId:'',status:'draft',dueDay:10,modules:{},profile:{},emailEnabled:false,whatsappEnabled:false,whatsappNumber:'',whatsappConsent:false,autopayRequested:false};

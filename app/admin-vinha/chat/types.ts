export type Conversation={id:string;department_id:string;organization_name?:string;registration_code?:number;contact_name:string;contact_email:string;source:string;status:string;assigned_operator_id:string|null;unread:boolean;last_message_at:string};
export type Message={id:string;sender:string;author_name:string;body:string;created_at:string};
export type Operator={id:string;name:string;role:string};
export type Sector={id:string;name:string;active:boolean};
export type Member={operator_id:string;department_id:string};
export type ChatData={error?:string;role:string;conversations:Conversation[];conversation:Conversation;messages:Message[];operators:Operator[];departments:Sector[];memberships:Member[]};

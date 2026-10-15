/* eslint-disable @typescript-eslint/no-explicit-any */
import type {SupabaseClient} from '@supabase/supabase-js';
import {NextResponse} from 'next/server';
import {createSupabaseRequestClient} from './request';
import {platformSessionFrom} from '../../api/_auth';

export type Row=Record<string,any>;
export type OperationsClient=SupabaseClient<any>;
export class OperationError extends Error{constructor(message:string,public status=400){super(message)}}
export const db=(request:Request)=>createSupabaseRequestClient(request) as unknown as OperationsClient;
export function check<T>(result:{data:T;error:any}):T{if(result.error)throw new OperationError(result.error.code==='42501'?'Você não possui permissão para esta operação.':result.error.code==='23505'?'Já existe um registro com estes dados.':result.error.message);return result.data}
export async function rows(client:OperationsClient,table:string){return check(await client.from(table).select('*')) as Row[]}
export async function one(client:OperationsClient,table:string,key:string,value:string){return check(await client.from(table).select('*').eq(key,value).maybeSingle()) as Row|null}
export async function insert(client:OperationsClient,table:string,value:Row){return check(await client.from(table).insert(value).select().single()) as Row}
export async function update(client:OperationsClient,table:string,key:string,value:string,patch:Row){const result=check(await client.from(table).update(patch).eq(key,value).select());if(!result?.length)throw new OperationError('Registro não encontrado ou acesso não autorizado.',404);return result[0] as Row}
export async function upsert(client:OperationsClient,table:string,value:Row,onConflict:string){return check(await client.from(table).upsert(value,{onConflict}).select().single()) as Row}
export async function rpc(client:OperationsClient,name:string,args:Row={}):Promise<any>{return check(await client.rpc(name,args))}
export const clean=(value:unknown,max=2000)=>String(value??'').trim().slice(0,max);
export const millis=(value:unknown)=>typeof value==='number'?value:value?new Date(String(value)).getTime():null;
export const uuid=(value:unknown)=>/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value));
export function requireValue(condition:unknown,message:string,status=400):asserts condition{if(!condition)throw new OperationError(message,status)}
export async function recordAudit(client:OperationsClient,userId:string,action:string,entityType:string,entityId?:string,metadata:Row={}){check(await client.from('platform_audit_events').insert({actor_user_id:userId,action,entity_type:entityType,entity_id:entityId,metadata}))}
export async function organizationOverview(client:OperationsClient):Promise<Row[]>{const[organizations,subscriptions,progress]=await Promise.all([rows(client,'organizations'),rows(client,'saas_subscriptions'),rows(client,'saas_onboarding_progress')]);return organizations.map<Row>(o=>{const sub=subscriptions.find(s=>s.organization_id===o.id),onboarding=progress.find(p=>p.organization_id===o.id);return{...o,subscription_status:sub?.status,trial_ends_at:sub?.trial_ends_at,onboarding_status:onboarding?.status,onboarding_step:onboarding?.current_step}})}
export function centralRoute(handler:(request:Request,client:OperationsClient,session:{id:string;name:string;role:string})=>Promise<Row>){return async(request:Request)=>{try{const session=await platformSessionFrom(request);if(!session)return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});return NextResponse.json(await handler(request,db(request),session),{headers:{'cache-control':'no-store'}})}catch(error){console.error('Central Vinha:',error instanceof Error?error.message:'Falha');return NextResponse.json({error:error instanceof OperationError?error.message:'Não foi possível concluir. Tente novamente.'},{status:error instanceof OperationError?error.status:500})}}}

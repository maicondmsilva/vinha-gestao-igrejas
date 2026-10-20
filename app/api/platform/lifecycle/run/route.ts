import {NextResponse} from 'next/server';
import {timingSafeEqual} from 'node:crypto';
import {runsGET,runsPOST,runScheduledLifecycle} from '../../../../lib/supabase/central-lifecycle';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';
import {processBillingNotifications} from '../../../../lib/supabase/billing-notifications';
import {processCellReportReminders} from '../../../../lib/supabase/cell-reminders';
export async function GET(request:Request){const expected=process.env.CRON_SECRET,authorization=request.headers.get('authorization')||'';if(!authorization)return runsGET(request);const received=authorization.replace(/^Bearer /,'');if(!expected||Buffer.byteLength(received)!==Buffer.byteLength(expected)||!timingSafeEqual(Buffer.from(received),Buffer.from(expected)))return NextResponse.json({error:'Rotina não autorizada.'},{status:401});try{const client=supabaseAdminClient(),cellReminders=await processCellReportReminders(client),result=await runScheduledLifecycle(client),billingNotifications=await processBillingNotifications(client);return NextResponse.json({...result,billingNotifications,cellReminders})}catch{return NextResponse.json({error:'Não foi possível executar a rotina agendada.'},{status:503})}}
export const POST=runsPOST;

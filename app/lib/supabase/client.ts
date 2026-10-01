import {createBrowserClient} from '@supabase/ssr';
import type {Database} from './database.types';

export const supabaseConfigured=Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
export function createSupabaseBrowserClient(){if(!supabaseConfigured)throw new Error('Supabase Auth ainda não foi configurado.');return createBrowserClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!)}

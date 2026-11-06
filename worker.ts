import app from 'vinext/server/app-router-entry';

// Notification automation lives in Supabase/Vercel crons; the legacy D1 endpoint is contained and must not be polled.
export default {
  fetch(request:Request,env:Record<string,any>,context:any){return app.fetch(request,env,context)},
};

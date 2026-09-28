import app from 'vinext/server/app-router-entry';

export default {
  fetch(request:Request,env:Record<string,any>,context:any){return app.fetch(request,env,context)},
  scheduled(_controller:any,env:Record<string,any>,context:any){
    const token=String(env.NOTIFICATION_WORKER_TOKEN||'');
    if(!token)return;
    const request=new Request('https://vinha.internal/api/notifications/automation',{method:'POST',headers:{'x-vinha-worker-token':token}});
    context.waitUntil(app.fetch(request,env,context));
  },
};

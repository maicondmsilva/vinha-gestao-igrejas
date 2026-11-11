import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {uuidPattern} from '../../lib/private-files';
import type {ScaleReport} from '../../../shared/scale-insights';

const headers = {'Cache-Control': 'private, no-store'};
const error = (message: string, status: number) => Response.json({error: message}, {status, headers});

export async function GET(request: Request) {
  const query = new URL(request.url).searchParams;
  const allowed = ['unit', 'tenant', 'action', 'from', 'to', 'team', 'role', 'page', 'search', 'format', 'service'];
  const unit = query.get('unit') || '';
  const action = query.get('action') || 'report';
  const format = query.get('format') || 'json';
  const page = Number(query.get('page') || '1');
  const from = query.get('from');
  const to = query.get('to');
  const team = query.get('team') || '';
  const role = query.get('role') || '';
  const service = query.get('service') || '';
  const search = query.get('search') || '';
  const isDate = (value: string | null) => value !== null && /^\d{4}-\d{2}-\d{2}$/.test(value);
  if (
    [...query.keys()].some((k) => !allowed.includes(k) || query.getAll(k).length !== 1) ||
    !uuidPattern.test(unit) ||
    [team, role].some((id) => id && !uuidPattern.test(id)) ||
    !['filters', 'pending', 'report', 'connections'].includes(action) ||
    (action === 'connections' && !uuidPattern.test(service)) ||
    !['json', 'pdf', 'xlsx'].includes(format) ||
    (action !== 'report' && format !== 'json') ||
    !Number.isInteger(page) ||
    page < 1 ||
    page > 10000 ||
    search.length > 100 ||
    (action === 'report' && (!isDate(from) || !isDate(to)))
  )
    return error('Revise a igreja, os filtros e o período.', 400);

  const auth = await authorizeSupabaseChurch(request, 'units.read');
  if (!auth || auth.response) return auth?.response || error('Acesso indisponível.', 503);
  if (!auth.access!.membership.units.some((u) => u.id === unit)) return error('Igreja sem acesso.', 403);
  try {
    const result = await (auth.access!.client as unknown as OperationsClient).rpc('scale_insights', {
      p_org: auth.access!.membership.organization_id,
      p_unit: unit,
      p_action: format === 'json' ? action : 'export',
      p_data: {from, to, team, role, page, search, service},
    });
    if (result.error) {
      if (result.error.code === '42501') return error('Você não tem acesso a estes dados de Escalas.', 403);
      if (result.error.message.includes('scale_insights_period')) return error('Escolha um período de até 366 dias, com início anterior ou igual ao fim.', 400);
      if (['22007', '22008'].includes(result.error.code)) return error('Informe datas válidas.', 400);
      return error('Não foi possível consultar Escalas.', 503);
    }
    if (format === 'json') return Response.json(result.data, {headers});
    const report = result.data as ScaleReport;
    if (report.distributionTotal > report.distribution.length)
      return error('A exportação comporta até 2.000 pessoas. Reduza o período ou filtre uma equipe.', 422);
    const period = `${from!.split('-').reverse().join('/')} a ${to!.split('-').reverse().join('/')}`;
    const {scaleReportPdf, scaleWorkbook} = await import('../../lib/scale-report-export');
    const bytes = format === 'pdf' ? await scaleReportPdf(report, period) : await scaleWorkbook(report, period);
    return new Response(Uint8Array.from(bytes).buffer, {
      headers: {
        ...headers,
        'Content-Type': format === 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': `attachment; filename="escalas-${from}-${to}.${format}"`,
      },
    });
  } catch {
    return error('Não foi possível concluir. Tente novamente.', 503);
  }
}

// Kids station mode, ready for the Vinha Equipe screens (next app step). Same contract and endpoints as the panel.
import {Platform} from 'react-native';
import {api} from './api';
import type {KidsOperationCommand, KidsOperationsPage, KidsStationList} from '../../shared/contract/kids.ts';

const platform = Platform.OS === 'android' || Platform.OS === 'ios' ? Platform.OS : 'other';
const station = (unit: string) => '/api/kids-station?' + new URLSearchParams({unit});

/** Registers this device as a reception station (Kids coordination or session supervisor). */
export const registerStation = (org: string, unit: string, name: string) =>
  api<{ok: true; id: string; name: string}>(station(unit), org, {method: 'POST', body: {action: 'register', data: {name, platform}}});
/** Keeps the station alive; fails with status 423 once the coordination turns it off. */
export const stationHeartbeat = (org: string, unit: string, id: string) =>
  api<{ok: true; active: true}>(station(unit), org, {method: 'POST', body: {action: 'heartbeat', id}});
export const listStations = (org: string, unit: string) => api<KidsStationList>(station(unit), org);

/** Current session board (present children, rooms, team) in the church's time zone. */
export const kidsPage = (org: string, unit: string, sessionId?: string) =>
  api<KidsOperationsPage & {timezone?: string}>(
    '/api/kids-operations?' + new URLSearchParams({unitId: unit, ...(sessionId ? {sessionId} : {}), status: 'present'}),
    org,
  );
/** Entry and exit. Each command carries its own requestId, so a retry after a lost connection never duplicates it. */
export const kidsCommand = (org: string, unit: string, command: KidsOperationCommand) =>
  api<{ok: true; id: string; version: number}>('/api/kids-operations?' + new URLSearchParams({unitId: unit}), org, {method: 'POST', body: command});

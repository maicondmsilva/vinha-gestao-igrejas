/** Séries de mensagens no app: tipos e regras puras. */
export type SeriesEpisode = {
  id: string;
  title: string;
  description: string;
  source: string;
  poster: string;
  episode: number | null;
  download_allowed: boolean;
  version: number;
};
export type Series = {id: string; title: string; description: string; poster: string; latest: string; episodes: SeriesEpisode[]};

/** Próxima parte a assistir: a primeira depois da última iniciada; se nenhuma foi iniciada, a primeira. */
export function nextEpisode(episodes: SeriesEpisode[], watched: (id: string) => number) {
  let last = -1;
  episodes.forEach((e, i) => {
    if (watched(e.id) > 0) last = i;
  });
  return episodes[last + 1] || episodes[last] || null;
}

/** O episódio vira um item da biblioteca para usar o mesmo player, progresso e favoritos. */
export function episodeMedia(e: SeriesEpisode, unit: string) {
  return {
    id: e.id,
    unit_id: unit,
    kind: 'video' as const,
    title: e.title,
    description: e.description,
    source: e.source,
    poster: e.poster,
    live_state: 'ended' as const,
    starts_at: null,
    ends_at: null,
    download_allowed: e.download_allowed,
    version: e.version,
  };
}

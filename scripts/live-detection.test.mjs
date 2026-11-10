import test from 'node:test';
import assert from 'node:assert/strict';
import {youtubeVideoId, youtubeLiveStates, syncYoutubeLives} from '../app/lib/live-detection.ts';

test('reconhece o vídeo nos formatos de link do YouTube', () => {
  for (const u of ['https://www.youtube.com/watch?v=abcdefghijk', 'https://youtu.be/abcdefghijk', 'https://www.youtube.com/live/abcdefghijk?si=x', 'https://m.youtube.com/embed/abcdefghijk'])
    assert.equal(youtubeVideoId(u), 'abcdefghijk', u);
  for (const u of ['https://www.youtube.com/@igreja/live', 'http://youtu.be/abcdefghijk', 'https://evil.com/watch?v=abcdefghijk', 'nada']) assert.equal(youtubeVideoId(u), null, u);
});

test('estado da live vem do próprio YouTube', async () => {
  const states = await youtubeLiveStates(['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc'], 'key', async (url) => {
    assert.equal(url.searchParams.get('part'), 'liveStreamingDetails');
    return Response.json({items: [
      {id: 'aaaaaaaaaaa', liveStreamingDetails: {actualStartTime: 'x'}},
      {id: 'bbbbbbbbbbb', liveStreamingDetails: {actualStartTime: 'x', actualEndTime: 'y'}},
      {id: 'ccccccccccc', liveStreamingDetails: {}},
    ]});
  });
  assert.deepEqual(states, {aaaaaaaaaaa: 'live', bbbbbbbbbbb: 'ended', ccccccccccc: 'scheduled'});
});

test('sem chave do YouTube nada é consultado; com chave só muda o que mudou', async () => {
  assert.deepEqual(await syncYoutubeLives(async () => assert.fail('sem consulta'), undefined), {enabled: false, changed: 0});
  const sets = [];
  const rpc = async (action, data) => {
    if (action === 'due') return {items: [{id: 'i1', source: 'https://youtu.be/aaaaaaaaaaa', state: 'scheduled'}, {id: 'i2', source: 'https://youtu.be/bbbbbbbbbbb', state: 'live'}, {id: 'i3', source: 'https://www.youtube.com/@canal', state: 'scheduled'}]};
    sets.push(data);
    return {changed: true};
  };
  const r = await syncYoutubeLives(rpc, 'key', async () => Response.json({items: [{id: 'aaaaaaaaaaa', liveStreamingDetails: {actualStartTime: 'x'}}, {id: 'bbbbbbbbbbb', liveStreamingDetails: {actualStartTime: 'x'}}]}));
  assert.deepEqual(sets, [{id: 'i1', state: 'live'}]);
  assert.equal(r.changed, 1);
});

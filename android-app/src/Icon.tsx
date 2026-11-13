import type {ReactElement} from 'react';
import Svg, {Circle, Path, Rect} from 'react-native-svg';

/** Ícones da Vinha: traço único de 1.8, grade 24×24, mesma área visual em todos (não dependem da fonte do celular). */
export type IconName =
  | 'home' | 'calendar' | 'play' | 'give' | 'menu' | 'prayer' | 'bible' | 'live' | 'kids' | 'cells' | 'scales' | 'ticket' | 'bell' | 'chevron' | 'mail' | 'chat' | 'cake' | 'plus';
const paths: Record<IconName, (c: string) => ReactElement> = {
  home: (c) => <><Path d="M4 11.5 12 5l8 6.5" stroke={c} /><Path d="M6.5 10v9h11v-9" stroke={c} /><Path d="M10.5 19v-4.5h3V19" stroke={c} /></>,
  calendar: (c) => <><Rect x="4" y="5.5" width="16" height="14" rx="3" stroke={c} /><Path d="M4 10h16M8.5 3.5v4M15.5 3.5v4" stroke={c} /><Circle cx="12" cy="14.5" r="1.4" fill={c} /></>,
  play: (c) => <><Rect x="3.5" y="5" width="17" height="14" rx="4" stroke={c} /><Path d="M10.5 9.3v5.4l4.5-2.7z" fill={c} stroke={c} /></>,
  give: (c) => <><Path d="M12 19s-6.5-3.8-6.5-8.6A3.4 3.4 0 0 1 12 8.6a3.4 3.4 0 0 1 6.5 1.8C18.5 15.2 12 19 12 19z" stroke={c} /></>,
  menu: (c) => <><Path d="M5 7h14M5 12h14M5 17h9" stroke={c} /></>,
  prayer: (c) => <><Path d="M12 4.5v9.5M12 4.5c-1.6 1.4-3.4 4.6-3.6 7.6L6 15.5l3 3.5 3-3.5M12 4.5c1.6 1.4 3.4 4.6 3.6 7.6l2.4 3.4-3 3.5-3-3.5" stroke={c} /></>,
  bible: (c) => <><Path d="M6 4.5h10.5a1.5 1.5 0 0 1 1.5 1.5v13.5H7.5A1.5 1.5 0 0 1 6 18z" stroke={c} /><Path d="M6 18a1.5 1.5 0 0 1 1.5-1.5H18M12 7.5v6M9.5 10h5" stroke={c} /></>,
  live: (c) => <><Circle cx="12" cy="12" r="2" fill={c} /><Path d="M8.2 8.2a5.4 5.4 0 0 0 0 7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6M5.4 5.4a9.3 9.3 0 0 0 0 13.2M18.6 5.4a9.3 9.3 0 0 1 0 13.2" stroke={c} /></>,
  kids: (c) => <><Circle cx="12" cy="7.5" r="3" stroke={c} /><Path d="M6.5 20c.4-3.6 2.6-6 5.5-6s5.1 2.4 5.5 6M9 14.8 7 12.5M15 14.8l2-2.3" stroke={c} /></>,
  cells: (c) => <><Circle cx="12" cy="6.5" r="2.4" stroke={c} /><Circle cx="6" cy="16" r="2.4" stroke={c} /><Circle cx="18" cy="16" r="2.4" stroke={c} /><Path d="M10.7 8.6 7.3 13.9M13.3 8.6l3.4 5.3M8.4 16h7.2" stroke={c} /></>,
  scales: (c) => <><Rect x="4" y="5.5" width="16" height="14" rx="3" stroke={c} /><Path d="M4 10h16M8.5 3.5v4M15.5 3.5v4M9 14.5l2 2 4-4" stroke={c} /></>,
  ticket: (c) => <><Path d="M4 8a2 2 0 0 0 0 4v0a2 2 0 0 1 0 4v1.5h16V16a2 2 0 0 1 0-4 2 2 0 0 0 0-4V6.5H4z" stroke={c} /><Path d="M14 7v2M14 11v2M14 15v1.5" stroke={c} /></>,
  bell: (c) => <><Path d="M6.5 16.5V11a5.5 5.5 0 0 1 11 0v5.5l1.5 1.5H5z" stroke={c} /><Path d="M10 20a2 2 0 0 0 4 0" stroke={c} /></>,
  chevron: (c) => <Path d="m9.5 6 6 6-6 6" stroke={c} />,
  mail: (c) => <><Rect x="4" y="6" width="16" height="12" rx="2.5" stroke={c} /><Path d="m5 7.5 7 5.5 7-5.5" stroke={c} /></>,
  chat: (c) => <><Path d="M5 18.5 6.2 15A7 7 0 1 1 9 17.6z" stroke={c} /><Path d="M9 11.5h.01M12 11.5h.01M15 11.5h.01" stroke={c} strokeWidth={2.4} /></>,
  cake: (c) => <><Rect x="5" y="11" width="14" height="8" rx="2" stroke={c} /><Path d="M5 14.5c2.3 1.4 4.7 1.4 7 0s4.7-1.4 7 0M12 11V8M12 4.5c-.9 1-.9 2 0 2.6.9-.6.9-1.6 0-2.6z" stroke={c} /></>,
  plus: (c) => <Path d="M12 5.5v13M5.5 12h13" stroke={c} />,
};
export default function Icon({name, color, size = 24}: {name: IconName; color: string; size?: number}) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
      {paths[name](color)}
    </Svg>
  );
}

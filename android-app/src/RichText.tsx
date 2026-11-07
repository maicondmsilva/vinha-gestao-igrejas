import {Image, Linking, Text, View} from 'react-native';
import {parseRichText, publishingImagePath, safeHref, type Inline} from '../../shared/rich-text.ts';

const platform = 'https://app.vinhaigrejas.com.br';

/** Notice text from the panel (shared/rich-text.ts) rendered with native components. */
export default function RichText({body, color, muted, accent}: {body: string; color: string; muted: string; accent: string}) {
  const inline = (nodes: Inline[], key = ''): React.ReactNode[] =>
    nodes.map((n, i) =>
      n.type === 'text' ? (
        n.text
      ) : n.type === 'bold' ? (
        <Text key={key + i} style={{fontWeight: '700'}}>
          {inline(n.children, key + i + '.')}
        </Text>
      ) : n.type === 'italic' ? (
        <Text key={key + i} style={{fontStyle: 'italic'}}>
          {inline(n.children, key + i + '.')}
        </Text>
      ) : (
        <Text
          key={key + i}
          accessibilityRole="link"
          style={{color: accent, fontWeight: '600', textDecorationLine: 'underline'}}
          onPress={() => {
            const href = safeHref(n.href);
            if (href) void Linking.openURL(href);
          }}
        >
          {inline(n.children, key + i + '.')}
        </Text>
      ),
    );
  const text = {color, fontSize: 16, lineHeight: 24};
  return (
    <View style={{gap: 12}}>
      {parseRichText(body).map((b, i) =>
        b.type === 'paragraph' ? (
          <Text key={i} style={text}>
            {inline(b.children)}
          </Text>
        ) : b.type === 'heading' ? (
          <Text key={i} accessibilityRole="header" style={{color, fontSize: b.level === 2 ? 19 : 17, fontWeight: '700', lineHeight: 26}}>
            {inline(b.children)}
          </Text>
        ) : b.type === 'quote' ? (
          <View key={i} style={{borderLeftWidth: 4, borderLeftColor: accent, paddingLeft: 12}}>
            <Text style={[text, {color: muted}]}>{inline(b.children)}</Text>
          </View>
        ) : b.type === 'list' ? (
          <View key={i} style={{gap: 6}}>
            {b.items.map((it, j) => (
              <View key={j} style={{flexDirection: 'row', gap: 8}}>
                <Text style={[text, {minWidth: 22}]}>{b.ordered ? `${j + 1}.` : '•'}</Text>
                <Text style={[text, {flex: 1}]}>{inline(it)}</Text>
              </View>
            ))}
          </View>
        ) : (
          <View key={i} style={{gap: 6}}>
            <Image
              source={{uri: platform + publishingImagePath(b.id)}}
              accessibilityLabel={b.alt || 'Imagem do aviso'}
              style={{width: '100%', aspectRatio: 4 / 3, borderRadius: 12}}
              resizeMode="cover"
            />
            {!!b.alt && <Text style={{color: muted, fontSize: 13}}>{b.alt}</Text>}
          </View>
        ),
      )}
    </View>
  );
}

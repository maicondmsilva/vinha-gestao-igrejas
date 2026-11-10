import {Fragment, type ReactNode} from 'react';
import {parseRichText, publishingImagePath, type Inline} from '../shared/rich-text';
import './rich-text.css';

function inline(nodes: Inline[]): ReactNode {
  return nodes.map((n, i) =>
    n.type === 'text' ? (
      <Fragment key={i}>
        {n.text.split('\n').map((part, j) => (
          <Fragment key={j}>
            {j > 0 && <br />}
            {part}
          </Fragment>
        ))}
      </Fragment>
    ) : n.type === 'bold' ? (
      <strong key={i}>{inline(n.children)}</strong>
    ) : n.type === 'italic' ? (
      <em key={i}>{inline(n.children)}</em>
    ) : (
      <a key={i} href={n.href} target="_blank" rel="noopener noreferrer nofollow">
        {inline(n.children)}
      </a>
    ),
  );
}

/** Notice text (shared/rich-text.ts) as React elements — never as HTML. */
export default function RichText({body, className = ''}: {body: string; className?: string}) {
  return (
    <div className={'vinha-rich ' + className}>
      {parseRichText(body).map((b, i) =>
        b.type === 'paragraph' ? (
          <p key={i}>{inline(b.children)}</p>
        ) : b.type === 'heading' ? (
          b.level === 2 ? (
            <h3 key={i}>{inline(b.children)}</h3>
          ) : (
            <h4 key={i}>{inline(b.children)}</h4>
          )
        ) : b.type === 'quote' ? (
          <blockquote key={i}>{inline(b.children)}</blockquote>
        ) : b.type === 'list' ? (
          b.ordered ? (
            <ol key={i}>
              {b.items.map((it, j) => (
                <li key={j}>{inline(it)}</li>
              ))}
            </ol>
          ) : (
            <ul key={i}>
              {b.items.map((it, j) => (
                <li key={j}>{inline(it)}</li>
              ))}
            </ul>
          )
        ) : (
          <figure key={i}>
            <img src={publishingImagePath(b.id)} alt={b.alt} loading="lazy" referrerPolicy="no-referrer" />
            {b.alt && <figcaption>{b.alt}</figcaption>}
          </figure>
        ),
      )}
    </div>
  );
}

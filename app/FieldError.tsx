'use client';
import './vinha-forms.css';

/** Inline message for one field, using the paths of shared/contract (`title`, `items.0.cpf`). */
export default function FieldError({fields, name}: {fields: Record<string, string>; name: string}) {
  const message = fields[name];
  if (!message) return null;
  return (
    <small className="vinha-field-error" id={fieldErrorId(name)} role="alert">
      {message}
    </small>
  );
}

export const fieldErrorId = (name: string) => 'erro-' + name.replace(/[^a-z0-9]+/gi, '-');
/** Props for the input the message belongs to. */
export const invalidProps = (fields: Record<string, string>, name: string) =>
  fields[name] ? {'aria-invalid': true as const, 'aria-describedby': fieldErrorId(name)} : {};

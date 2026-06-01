# React component idioms (for design-to-ui)

Match the project's existing conventions first; the below is the modern default (React 18+, function
components, TypeScript).

## Component shape
```tsx
type ButtonProps = {
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  loading?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
};

export function Button({ variant = 'primary', size = 'md', disabled, loading, onClick, children }: ButtonProps) {
  return (
    <button
      className={cn('rounded-lg font-medium transition-colors', sizeCls[size], variantCls[variant])}
      disabled={disabled || loading}
      onClick={onClick}
    >
      {loading ? <Spinner /> : children}
    </button>
  );
}
```

## Idioms
- **Props in, callbacks out** (`onChange`, `onClick`). Controlled inputs via `value` + `onChange`.
- **Local state:** `useState`; derived values computed inline or with `useMemo`.
- **Conditionals/lists:** `{cond && <X/>}` / `{cond ? <A/> : <B/>}`; `{items.map(i => <Row key={i.id} .../>)}` (always a stable `key`).
- **Styling:** match the project — Tailwind `className`, CSS Modules (`styles.btn`), or styled-components.
- **Composition:** `children` and slot-like props; `forwardRef` for atoms that wrap a DOM element.
- **Files:** colocate `Button.tsx` (+ `Button.module.css` if CSS Modules); barrel-export via `index.ts`.

## Next.js note
Add `'use client'` to components that use state/effects/handlers. Server components stay prop-only.

# Angular component idioms (for design-to-ui)

Default: standalone components with signals (Angular 17+). Match the project's existing conventions.

## Standalone component template
```ts
import { Component, input, model, output, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-button',
  standalone: true,
  imports: [CommonModule],
  template: `
    <button [class]="computedClass()" [disabled]="disabled() || loading()" (click)="clicked.emit()">
      @if (loading()) { <app-spinner /> } @else { <ng-content /> }
    </button>
  `,
  styles: [`:host { display: inline-block; }`],
})
export class ButtonComponent {
  variant = input<'primary' | 'secondary' | 'ghost'>('primary');
  size = input<'sm' | 'md' | 'lg'>('md');
  disabled = input(false);
  loading = input(false);
  value = model<string>('');        // two-way binding when needed
  clicked = output<void>();
  computedClass = computed(() => `rounded-lg font-medium ${this.variant() === 'primary' ? 'bg-primary' : 'bg-gray-500'}`);
}
```

## Idioms
- **Inputs:** `input()` signal fn. **Two-way:** `model()`. **Outputs:** `output()`.
- **State:** `signal()`; **derived:** `computed()`.
- **Template control flow:** `@if`/`@else`, `@for (x of xs(); track x.id)`, `@switch`/`@case` (not `*ngIf`/`*ngFor`).
- **Naming:** file `<name>.component.ts`, selector `app-<name>`, class `<Name>Component`.
- **Styling:** Tailwind classes; avoid inline `[style.*]` except truly dynamic values; `dark:` variants for dark mode; theme tokens via Tailwind config / CSS variables.
- **Files:** `<type>/<name>/<name>.component.ts` (+ `index.ts` barrel `export * from './<name>.component'`).

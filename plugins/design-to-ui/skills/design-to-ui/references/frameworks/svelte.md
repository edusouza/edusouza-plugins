# Svelte component idioms (for design-to-ui)

Default: Svelte 5 runes with TypeScript. If the project is Svelte 4, use `export let` props, `$:` reactive
statements, and `on:click` — match what's there.

## Component shape (Svelte 5 runes)
```svelte
<script lang="ts">
  let { variant = 'primary', size = 'md', disabled = false, loading = false, onclick, children }:
    {
      variant?: 'primary' | 'secondary' | 'ghost';
      size?: 'sm' | 'md' | 'lg';
      disabled?: boolean;
      loading?: boolean;
      onclick?: () => void;
      children?: import('svelte').Snippet;
    } = $props();
</script>

<button class="rounded-lg font-medium transition-colors {sizeCls[size]} {variantCls[variant]}"
        disabled={disabled || loading} {onclick}>
  {#if loading}<Spinner />{:else}{@render children?.()}{/if}
</button>
```

## Idioms
- **Props:** `$props()` (Svelte 5) or `export let` (Svelte 4). **State:** `$state()`; **derived:** `$derived()`.
- **Events:** callback props (`onclick`) in Svelte 5; `createEventDispatcher`/`on:` in Svelte 4.
- **Conditionals/lists:** `{#if}…{:else}…{/if}`, `{#each items as i (i.id)}…{/each}` (keyed).
- **Composition:** snippets (`{@render children()}`) in v5, slots (`<slot />`) in v4.
- **Styling:** Tailwind in `class`, or component `<style>` (scoped by default).
- **Files:** one `.svelte` per component, typically under `src/lib/components/`.

# Vue component idioms (for design-to-ui)

Default: Vue 3 `<script setup>` with TypeScript. Match the project's existing style.

## Component shape
```vue
<script setup lang="ts">
withDefaults(defineProps<{
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  loading?: boolean;
}>(), { variant: 'primary', size: 'md' });

const emit = defineEmits<{ click: [] }>();
</script>

<template>
  <button
    class="rounded-lg font-medium transition-colors"
    :class="[sizeCls[size], variantCls[variant]]"
    :disabled="disabled || loading"
    @click="emit('click')"
  >
    <Spinner v-if="loading" /><slot v-else />
  </button>
</template>
```

## Idioms
- **Props in, events out:** `defineProps` / `defineEmits`. Two-way binding via `defineModel()` or `v-model`.
- **Local state:** `ref()` / `reactive()`; derived values with `computed()`.
- **Conditionals/lists:** `v-if` / `v-else`, `v-for="i in items" :key="i.id"` (always `:key`).
- **Slots** for composition (`<slot />`, named slots).
- **Styling:** Tailwind in `class`, or `<style scoped>`; match the project.
- **Files:** one `.vue` SFC per component; barrel-export if the project does.

## Nuxt note
Components in `components/` auto-import. Use `<ClientOnly>` for client-only widgets when needed.

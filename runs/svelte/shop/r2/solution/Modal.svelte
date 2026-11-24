<script>
  let { onclose, children } = $props();

  $effect(() => {
    function handleKeydown(event) {
      if (event.key === 'Escape') onclose();
    }
    window.addEventListener('keydown', handleKeydown);
    return () => window.removeEventListener('keydown', handleKeydown);
  });
</script>

<div role="dialog" aria-modal="true">
  <button type="button" aria-label="Close" onclick={onclose}>×</button>
  {@render children?.()}
</div>

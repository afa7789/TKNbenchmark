<script>
  let { onclose, children } = $props();

  function handleKeydown(event) {
    if (event.key === 'Escape') onclose();
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div role="dialog" aria-modal="true">
  <button type="button" aria-label="Close" onclick={onclose}>×</button>
  {@render children?.()}
</div>

<script>
  let { title, onclose, children } = $props();

  function onkeydown(event) {
    if (event.key === 'Escape') onclose();
  }
</script>

<svelte:window {onkeydown} />

<div role="dialog" aria-modal="true" aria-label={title}>
  {#if title}
    <h2>{title}</h2>
  {/if}
  <button type="button" aria-label="Close" onclick={onclose}>×</button>
  {@render children?.()}
</div>

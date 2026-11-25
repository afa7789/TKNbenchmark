<script>
  import { cart } from './cart.svelte.js';

  let { onsubmitted } = $props();

  let name = $state('');
  let email = $state('');

  const nameError = $derived(name.trim() ? '' : 'Name is required');
  const emailError = $derived(email.includes('@') ? '' : 'Email must contain @');
  const valid = $derived(!nameError && !emailError);

  function onsubmit(event) {
    event.preventDefault();
    if (!valid) return;
    cart.clear();
    onsubmitted?.();
  }
</script>

<form {onsubmit} novalidate>
  <label>
    Name
    <input type="text" bind:value={name} />
  </label>
  {#if nameError}
    <p>{nameError}</p>
  {/if}

  <label>
    Email
    <input type="email" bind:value={email} />
  </label>
  {#if emailError}
    <p>{emailError}</p>
  {/if}

  <button type="submit" disabled={!valid}>Place order</button>
</form>

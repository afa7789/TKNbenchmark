<script>
  import { cart } from './cart.svelte.js';

  let { oncomplete } = $props();

  let name = $state('');
  let email = $state('');

  const nameError = $derived(name.trim() ? '' : 'Name is required');
  const emailError = $derived(email.includes('@') ? '' : 'Email must contain @');
  const valid = $derived(!nameError && !emailError);

  function handleSubmit(event) {
    event.preventDefault();
    if (!valid) return;
    cart.clear();
    oncomplete?.();
  }
</script>

<form onsubmit={handleSubmit} novalidate>
  <label>
    Name
    <input type="text" bind:value={name} />
  </label>
  {#if nameError}<p role="alert">{nameError}</p>{/if}

  <label>
    Email
    <input type="email" bind:value={email} />
  </label>
  {#if emailError}<p role="alert">{emailError}</p>{/if}

  <button type="submit" disabled={!valid}>Place order</button>
</form>

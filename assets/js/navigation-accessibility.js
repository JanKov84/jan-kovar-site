// Preserve the standard Blox checkbox menu while enabling keyboard interaction.
const toggle = document.querySelector('#nav-toggle');
const control = document.querySelector('label[for="nav-toggle"]');
if (toggle && control) {
  control.tabIndex = 0;
  control.setAttribute('role', 'button');
  control.setAttribute('aria-controls', 'nav-menu');
  function sync() {
    control.setAttribute('aria-expanded', String(toggle.checked));
    control.setAttribute('aria-label', toggle.checked ? 'Close menu' : 'Open menu');
  }
  sync();
  toggle.addEventListener('change', sync);
  control.addEventListener('keydown', event => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggle.click();
    }
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && toggle.checked) {
      toggle.click();
      control.focus();
    }
  });
}

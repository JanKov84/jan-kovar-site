const form = document.querySelector('#publication-filters');
if (form) {
  const type = document.querySelector('#publication-type');
  const area = document.querySelector('#research-area');
  const items = [...document.querySelectorAll('.publication-result')];
  const count = document.querySelector('#publication-count');
  const empty = document.querySelector('#publication-empty');
  function update() {
    let visible = 0;
    for (const item of items) {
      const matchesType = !type.value || item.dataset.category === type.value;
      const matchesArea = !area.value || item.dataset.areas.split('|').includes(area.value);
      item.hidden = !(matchesType && matchesArea);
      if (!item.hidden) visible++;
    }
    count.textContent = `${visible} of ${items.length} publications · newest first`;
    empty.hidden = visible !== 0;
    const url = new URL(location.href);
    for (const [key, value] of [['type', type.value], ['area', area.value]]) {
      if (value) url.searchParams.set(key, value);
      else url.searchParams.delete(key);
    }
    history.replaceState(null, '', url);
  }
  const query = new URLSearchParams(location.search);
  for (const [select, key] of [[type, 'type'], [area, 'area']]) {
    const requested = query.get(key);
    if ([...select.options].some(option => option.value === requested)) select.value = requested;
  }
  form.hidden = false;
  form.addEventListener('change', update);
  form.addEventListener('submit', event => event.preventDefault());
  form.addEventListener('reset', () => { type.value = ''; area.value = ''; update(); });
  update();
}

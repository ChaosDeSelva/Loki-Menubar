'use strict';
const search = document.querySelector('#demo-search');
const favorites = document.querySelector('#favorites');
const all = document.querySelector('#all-tools');
let favoritesOnly = false;
function update() {
  const query = search.value.trim().toLocaleLowerCase();
  let count = 0;
  document.querySelectorAll('.demo-row').forEach(row => {
    row.hidden = !row.dataset.name.toLocaleLowerCase().includes(query) || (favoritesOnly && row.dataset.favorite !== 'true');
    if (!row.hidden) count += 1;
  });
  document.querySelector('#demo-empty').hidden = count !== 0;
  favorites.setAttribute('aria-pressed', String(favoritesOnly));
  favorites.classList.toggle('selected', favoritesOnly);
  all.classList.toggle('selected', !favoritesOnly);
}
search.addEventListener('input', update);
favorites.addEventListener('click', () => { favoritesOnly = !favoritesOnly; update(); });
all.addEventListener('click', () => { favoritesOnly = false; update(); });

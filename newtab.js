const homepage = 'https://homepage.fxtteam.ru/';
const statusLine = document.querySelector('#status');
const skeleton = document.querySelector('#skeleton');
const retry = document.querySelector('#retry');

const hours = document.querySelector('#hours');
const minutes = document.querySelector('#minutes');
const seconds = document.querySelector('#seconds');
const dateLine = document.querySelector('#date');
const dateFormat = new Intl.DateTimeFormat('ru-RU', { weekday: 'long', day: 'numeric', month: 'long' });
let clockTimer;

function updateClock() {
  const now = new Date();
  hours.textContent = String(now.getHours()).padStart(2, '0');
  minutes.textContent = String(now.getMinutes()).padStart(2, '0');
  seconds.textContent = String(now.getSeconds()).padStart(2, '0');
  dateLine.textContent = dateFormat.format(now);
}

async function openHomepage() {
  clearInterval(clockTimer);
  retry.hidden = true;
  skeleton.hidden = false;
  statusLine.textContent = 'Открываем стартовую страницу…';

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6000);
  try {
    const options = {
      cache: 'no-store',
      signal: controller.signal
    };
    let response = await fetch(homepage, { ...options, method: 'HEAD' });
    if (response.status === 405 || response.status === 501) {
      response = await fetch(homepage, options);
    }
    if (!response.ok) throw new Error('Homepage unavailable');
    window.location.replace(homepage);
  } catch {
    updateClock();
    clockTimer = setInterval(updateClock, 1000);
    skeleton.hidden = true;
    statusLine.textContent = 'Стартовая страница недоступна';
    retry.hidden = false;
    retry.focus();
  } finally {
    clearTimeout(timeout);
    controller.abort();
  }
}

retry.addEventListener('click', openHomepage);
openHomepage();

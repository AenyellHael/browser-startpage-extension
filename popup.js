const button = document.querySelector('#action');
const statusLine = document.querySelector('#status');
document.querySelector('#version').textContent = 'Версия ' + chrome.runtime.getManifest().version;

let nextAction = 'inspect';

button.addEventListener('click', async () => {
  if (button.disabled) return;
  const action = nextAction;
  button.disabled = true;
  button.textContent = action === 'apply' ? 'Устанавливаем…' : 'Проверяем…';
  statusLine.textContent = '';
  nextAction = 'inspect';
  let label = 'Проверить обновление';
  try {
    const result = await chrome.runtime.sendMessage({action});
    if (result.error) throw new Error(result.error);
    if (result.newer) {
      statusLine.textContent = 'Доступна версия ' + result.version + '.';
      label = 'Обновить до ' + result.version;
      nextAction = 'apply';
    } else {
      statusLine.textContent = 'Установлена последняя версия.';
    }
  } catch (error) {
    statusLine.textContent = error.message === 'host'
      ? 'Для ручного обновления запустите установщик версии 1.5.2 или новее и загрузите указанную им папку.'
      : 'Не удалось проверить или применить обновление. Проверьте соединение и повторите попытку.';
    label = 'Повторить проверку';
  } finally {
    button.textContent = label;
    button.disabled = false;
  }
});

# FXT Team New Tab

Расширение для Google Chrome открывает [стартовую страницу FXT Team](https://homepage.fxtteam.ru/) в каждой новой вкладке. Нажмите `Ctrl+T` или кнопку «+», чтобы перейти к поиску и своим ссылкам. Если сайт недоступен, во вкладке появятся часы и кнопка «Попробовать снова».

## Быстрая установка

1. Скачайте и запустите установщик для своей системы.
   - **Windows** — дважды щёлкните по скачанному файлу [install_FXT-Team-New-Tab_Windows.cmd](https://github.com/AenyellHael/browser-startpage-extension/releases/latest/download/install_FXT-Team-New-Tab_Windows.cmd).
   - **Linux** — скачайте [install_FXT-Team-New-Tab_Linux.sh](https://github.com/AenyellHael/browser-startpage-extension/releases/latest/download/install_FXT-Team-New-Tab_Linux.sh) и выполните `sh ./install_FXT-Team-New-Tab_Linux.sh` в папке загрузки. Понадобится Python 3.
2. Когда установщик предложит ежедневные автообновления, выберите **Да** или **Нет**.
3. Если профилей Chrome несколько, выберите нужный в установщике. Он откроет `chrome://extensions/` в этом профиле. Включите **Режим разработчика**, нажмите **Загрузить распакованное расширение** и выберите папку `extension`, путь к которой покажет установщик.

## Обновление по клику

Нажмите иконку FXT Team New Tab в меню расширений Chrome. В окне появятся описание расширения и установленная версия. Нажмите **Проверить обновление**, чтобы проверить последний подписанный пакет GitHub. Если появилась новая версия, нажмите **Обновить**. После установки расширение перезагрузится. Для этой кнопки ежедневное расписание включать необязательно.

При переходе с 1.5.1 один раз запустите установщик 1.5.2 или новее для своей системы и нажмите значок перезагрузки на карточке расширения в `chrome://extensions`. Если Chrome запросит разрешение на связь с локальным приложением, подтвердите его.

## Полное удаление


1. Откройте `chrome://extensions` и нажмите **Удалить** на карточке **FXT Team New Tab**. Повторите в каждом профиле Chrome, где подключали расширение.
2. Скачайте файл для своей системы и подтвердите удаление. Он уберёт расписание автообновлений и установленные файлы текущего пользователя.
   - **Windows** — запустите [uninstall_FXT-Team-New-Tab_Windows.cmd](https://github.com/AenyellHael/browser-startpage-extension/releases/latest/download/uninstall_FXT-Team-New-Tab_Windows.cmd).
   - **Linux** — скачайте [uninstall_FXT-Team-New-Tab_Linux.sh](https://github.com/AenyellHael/browser-startpage-extension/releases/latest/download/uninstall_FXT-Team-New-Tab_Linux.sh) и выполните `sh ./uninstall_FXT-Team-New-Tab_Linux.sh` в папке загрузки.

Если вы вручную распаковали ZIP в другую папку, отключите обновления из той папки (`update\windows.ps1 -Action Disable` в Windows или `python3 update/linux.py disable` в Linux), затем удалите её.

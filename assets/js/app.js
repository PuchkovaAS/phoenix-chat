// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html';
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix';
import { LiveSocket } from 'phoenix_live_view';
import { hooks as colocatedHooks } from 'phoenix-colocated/chat';
import topbar from '../vendor/topbar';

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content');

const myHooks = {
    // ✅ Хук автоскролла
    // assets/js/app.js
    AutoScroll: {
        mounted() {
            // ✅ Получаем количество непрочитанных
            const unreadCount = parseInt(this.el.dataset.unreadCount || '0', 10);

            console.log(`[AutoScroll] Mounted with ${unreadCount} unread messages`);

            // ✅ Даём DOM время отрисоваться перед скроллом
            setTimeout(() => {
                if (unreadCount > 0) {
                    // Ищем первое непрочитанное сообщение
                    const firstUnread = this.el.querySelector('[data-is-read="false"]');

                    if (firstUnread) {
                        console.log('[AutoScroll] Found unread message, scrolling to it');
                        firstUnread.scrollIntoView({ behavior: 'smooth', block: 'center' });

                        // Подсветка на 3 секунды
                        firstUnread.classList.add('ring-2', 'ring-yellow-400', 'transition-all');
                        setTimeout(() => {
                            firstUnread.classList.remove('ring-2', 'ring-yellow-400');
                        }, 3000);
                    } else {
                        console.log('[AutoScroll] No unread found, scrolling to bottom');
                        this.scrollToBottom();
                    }
                } else {
                    console.log('[AutoScroll] All read, scrolling to bottom');
                    this.scrollToBottom();
                }
            }, 100); // ✅ Задержка 100мс для рендера

            // Наблюдатель для новых сообщений
            this.observer = new MutationObserver(() => {
                const currentUnread = parseInt(this.el.dataset.unreadCount || '0', 10);
                // Скроллим только если пользователь внизу и нет непрочитанных
                if (this.isAtBottom() && currentUnread === 0) {
                    this.scrollToBottom();
                }
            });

            this.observer.observe(this.el, { childList: true, subtree: false });
        },

        updated() {
            const unreadCount = parseInt(this.el.dataset.unreadCount || '0', 10);
            if (this.isAtBottom() && unreadCount === 0) {
                this.scrollToBottom();
            }
        },

        destroyed() {
            if (this.observer) this.observer.disconnect();
        },

        isAtBottom() {
            const threshold = 100;
            return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < threshold;
        },

        scrollToBottom() {
            requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                    this.el.scrollTo({
                        top: this.el.scrollHeight,
                        behavior: 'smooth',
                    });
                });
            });
        },
    },
    ClearForm: {
        mounted() {
            this.handleEvent('clear_form', ({ selector }) => {
                const input = document.querySelector(selector);
                if (input) {
                    input.value = '';
                    input.focus();
                }
            });
        },
    },
    LocalTime: {
        mounted() {
            this.convert();
        },
        updated() {
            this.convert();
        },
        convert() {
            const utc = this.el.getAttribute('data-utc');
            if (!utc) return;

            const date = new Date(utc);
            if (isNaN(date.getTime())) return;

            // Форматируем в локальном времени пользователя
            this.el.textContent = date.toLocaleTimeString([], {
                hour: '2-digit',
                minute: '2-digit',
                // second: '2-digit',  // раскомментируйте, если нужны секунды
                hour12: false, // 24-часовой формат
            });
        },
    },
    // ✅ Хук для автоматической отметки сообщения как "прочитанное"
    MarkRead: {
        mounted() {
            // Не обрабатываем свои сообщения и системные
            if (this.el.dataset.username === this.el.dataset.currentUsername || this.el.dataset.username === 'system') {
                return;
            }

            this.marked = false;

            this.observer = new IntersectionObserver(
                (entries) => {
                    entries.forEach((entry) => {
                        if (entry.isIntersecting && !this.marked) {
                            this.marked = true;

                            // Отправляем событие на сервер
                            this.pushEvent('mark_as_read', {
                                message_id: this.el.dataset.messageId,
                                timestamp: this.el.dataset.timestamp,
                            });

                            // Визуально убираем индикатор "новое"
                            const badge = this.el.querySelector('.animate-pulse');
                            if (badge) badge.classList.remove('animate-pulse', 'bg-blue-500');

                            // Убираем подсветку контейнера
                            this.el.classList.remove('bg-blue-500/10', 'rounded-lg', 'p-1', '-m-1');

                            // Добавляем галочку "прочитано" (для чужих сообщений)
                            const timeEl = this.el.querySelector('.local-time');
                            if (timeEl && !timeEl.parentElement.querySelector('.text-emerald-400')) {
                                const check = document.createElement('span');
                                check.className = 'text-emerald-400 ml-1';
                                check.textContent = '✓';
                                check.title = 'Прочитано';
                                timeEl.parentElement.appendChild(check);
                            }
                        }
                    });
                },
                { threshold: 0.6 }, // 60% сообщения должно быть видно
            );

            this.observer.observe(this.el);
        },

        destroyed() {
            if (this.observer) this.observer.disconnect();
        },
    },
};

const liveSocket = new LiveSocket('/live', Socket, {
    longPollFallbackMs: 2500,
    params: { _csrf_token: csrfToken },
    hooks: { ...colocatedHooks, ...myHooks },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });
window.addEventListener('phx:page-loading-start', (_info) => topbar.show(300));
window.addEventListener('phx:page-loading-stop', (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === 'development') {
    window.addEventListener('phx:live_reload:attached', ({ detail: reloader }) => {
        // Enable server log streaming to client.
        // Disable with reloader.disableServerLogs()
        reloader.enableServerLogs();

        // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
        //
        //   * click with "c" key pressed to open at caller location
        //   * click with "d" key pressed to open at function component definition location
        let keyDown;
        window.addEventListener('keydown', (e) => (keyDown = e.key));
        window.addEventListener('keyup', (_e) => (keyDown = null));
        window.addEventListener(
            'click',
            (e) => {
                if (keyDown === 'c') {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    reloader.openEditorAtCaller(e.target);
                } else if (keyDown === 'd') {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    reloader.openEditorAtDef(e.target);
                }
            },
            true,
        );

        window.liveReloader = reloader;
    });
}

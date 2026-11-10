# Google Gemini Client для iOS 15.8 (iPhone SE 1-го поколения)

Полностью нативное приложение на **SwiftUI**, разработанное с учётом всех аппаратных и интерфейсных ограничений **iPhone SE 1-го поколения** (экран 4.0", разрешение 320x568 pt, чип Apple A9, iOS 15.8).

---

## Ключевые особенности архитектуры

1. **Мгновенный старт без задержек (0 ms Latency)**:
   - При запуске главный экран немедленно отображает легковесный нативный скелет чата (`ChatSkeletonView`).
   - Пока пользователь видит анимированный скелетон с системными шрифтами San Francisco и размытием `UIBlurEffect`, в фоновом режиме инициализируется сессия WebKit.
   - Никаких белых вспышек и зависаний на экране загрузки.

2. **Обертка `WKWebView` и фоновая авторизация Google Gemini**:
   - `GeminiWebView` инкапсулирует `WKWebView` через `UIViewRepresentable`.
   - Использование постоянного хранилища данных (`WKWebsiteDataStore.default()`) сохраняет все куки авторизации Google, сессионные токены и подписку **Gemini Advanced / Google One AI Premium** между перезапусками приложения.
   - Реализована плавная замена скелетона на загруженный чат через `withAnimation(.easeInOut(duration: 0.35))`.

3. **Полный обход блокировки Google 403 `disallowed_useragent`**:
   - Google блокирует стандартные встроенные WebViews при авторизации на `accounts.google.com`.
   - В `GeminiWebView` подставлен аутентичный Mobile Safari User-Agent для iOS 15:
     ```
     Mozilla/5.0 (iPhone; CPU iPhone OS 15_8_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1
     ```
   - Это гарантирует беспрепятственный вход через Google аккаунт.

4. **Адаптация под компактный экран 320x568 pt (iPhone SE 1st Gen)**:
   - Экран первого SE имеет ширину всего 320 pt — веб-версия Gemini обычно перегружена широкими отступами.
   - Через `WKUserScript` (`GeminiScript.swift`) внедряется точечный CSS:
     - Оптимизируются боковые отступы контейнера сообщений (`padding: 8px`).
     - Скрываются лишние веб-шапки и рекламные баннеры, дублирующие системный интерфейс.
     - Поле ввода Prompt автоматически масштабируется под ширину 320 px.
     - Блокируется случайное открытие ссылок в новых вкладках (`window.open`).

5. **Строгая совместимость со стандартами iOS 15**:
   - Никаких API из iOS 16+ (`NavigationStack`, `Grid`, `.scrollDismissesKeyboard` и т.д.).
   - Использование нативного `VisualEffectBlur` и `.background(.ultraThinMaterial)`.
   - Отсутствие тяжелых внешних зависимостей (CocoaPods/SPM) — только стандартные `SwiftUI`, `WebKit`, `UIKit` и `Combine`.

---

## Структура файлов проекта

| Файл | Описание |
| :--- | :--- |
| **`Gemini/GeminiApp.swift`** | Главная точка входа приложения на SwiftUI. |
| **`Gemini/ContentView.swift`** | Корневой экран с бесшовным переходом от скелетона к веб-чату. |
| **`Gemini/ChatSkeletonView.swift`** | Локальный скелет чата со скруглениями continuous и системным стилем. |
| **`Gemini/ShimmerModifier.swift`** | 60 FPS аппаратный шейдер мерцания (Shimmer) на LinearGradient. |
| **`Gemini/TranslucentBackground.swift`** | Нативная полупрозрачная размытая подложка (`UIBlurEffect`). |
| **`Gemini/GeminiWebView.swift`** | Интеграция `WKWebView`, обработка сессии, User-Agent и делегатов. |
| **`Gemini/WebViewModel.swift`** | Реактивная ViewModel (`ObservableObject`) с отслеживанием статуса и подписки. |
| **`Gemini/NativeHeaderView.swift`** | Верхняя навигационная панель с кнопками New Chat, Reload и бейджем Advanced. |
| **`Gemini/GeminiScript.swift`** | CSS/JS инъекция для подгонки Gemini под экран 320 pt. |
| **`Gemini/Info.plist`** | Настройки проекта, разрешения камеры, микрофона и фото. |
| **`Gemini.xcodeproj`** | Готовый проект Xcode 13+, собираемый в один клик. |

---

## Сборка и установка

### Способ 1: Сборка через Xcode (Mac)
1. Откройте `Gemini.xcodeproj` в Xcode 13, 14, 15 или 16.
2. Выберите таргет **Gemini** и ваше устройство (или симулятор iPhone SE).
3. Нажмите **Cmd + R** (Run).

### Способ 2: Установка на iPhone SE через TrollStore / AltStore
1. Соберите IPA-пакет (Release) в Xcode или используйте готовый IPA.
2. Установите IPA на iPhone SE 1st Gen через **TrollStore** без переподписи каждые 7 дней.

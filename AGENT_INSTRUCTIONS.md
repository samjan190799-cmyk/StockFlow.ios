# 📋 AGENT_INSTRUCTIONS.md — Инструкция для всех ИИ-агентов

> **ОБЯЗАТЕЛЬНО ПРОЧИТАТЬ ПЕРЕД ЛЮБЫМИ ДЕЙСТВИЯМИ!**  
> Этот файл — единый источник правды. Планировщик должен спрашивать этот файл перед составлением любого плана.

---

## 🔴 ПРАВИЛО №1 — ЯЗЫК

**ВСЁ пишем ТОЛЬКО на РУССКОМ языке:**
- Ответы пользователю
- Планы реализации
- Сообщения коммитов
- Комментарии в коде
- Логи и диагностика

Нарушение этого правила недопустимо.

---

## 📱 ПРОЕКТ — StockFlow.ios

**Что это:** iOS-приложение для загрузки фотографий на стоки (Shutterstock, Adobe Stock, Alamy и др.)  
**Платформа:** iOS 16+ (минимальная версия iOS 16, основная аудитория — iOS 17/18+)  
**Язык:** Swift + SwiftUI  
**Сборка:** GitHub Actions (workflow находится в `.github/`)

---

## 🎨 ДИЗАЙН-СИСТЕМА (спокойный плоский стиль)

**Стиль:** сплошной фон с едва заметной точечной сеткой, карточки с тонкой рамкой, акцентный синий цвет.
Неоновое свечение, анимированный фон и стеклянные шары из прежних версий убраны.

**Ключевые компоненты:**
- `DesignKit.swift` — карточки (`appCard`), секции и строки настроек, стили кнопок (`appPrimary`, `appSecondary`, `appDestructive`), шрифт `scaledFont` с учётом Dynamic Type
- `GalleryModel.swift` — палитра `GalleryPalette` (`AppPalette` — её псевдоним)
- `DesignSystem.swift` — `LiquidBackgroundView` (сплошной фон + точечная сетка), `HapticHelper`
- `GalleryComponents.swift` — плитка, лента этапов, нижняя панель действий

**Правила для нового интерфейса:**
- Текст — только системные стили (`.font(.subheadline)`); фиксированный размер допустим для иконок, для текста используйте `scaledFont`
- Кнопка-иконка обязана иметь `.accessibilityLabel`
- Нажимаемая зона не меньше 44 pt
- Новые строки — только через `.localized` с переводом в `Localizer.swift` (ключ в словаре не должен повторяться: дубликат роняет приложение при запуске)
- Навигация между вкладками — через `AppRouter.shared.selectedTab`
- На iOS 26+ панель вкладок остаётся системной (Liquid Glass), кастомный `UITabBarAppearance` только для iOS 16–25

## 📢 РЕКЛАМА (Яндекс Mobile Ads SDK 8.x)

- Показывается только без PRO: баннер под лентой очереди (`AdBannerView`) и ролик за бонусные действия (`AdManager.showRewardedAd`, +5, до 5 в день)
- SDK запускается лениво (`AdManager.startIfNeeded`), подписчикам он не нужен
- Идентификаторы блоков и выключатель `AdsEnabled` лежат в `project.yml` (свойства Info.plist). По умолчанию там **тестовые** блоки Яндекса: перед выпуском подставить свои из partner.yandex.ru
- Запроса ATT нет, отслеживания нет (`NSPrivacyTracking = false`), реклама неперсонализированная. Данные, которые собирает SDK (в нём же AppMetrica), перечислены в `PrivacyInfo.xcprivacy`, в App Privacy в App Store Connect они должны совпадать
- В `build.yml` нельзя задавать `SKIP_INSTALL` и `INSTALL_PATH` в командной строке архива: они применятся к пакетам и сломают экспорт

**Совместимость:**
```swift
// ОБЯЗАТЕЛЬНО оборачивать iOS 17+ API:
if #available(iOS 17.0, *) {
    // код для iOS 17+
} else {
    // fallback для iOS 16
}
```

---

## 🌐 СЕТЕВАЯ АРХИТЕКТУРА (FTP/FTPES)

### Почему не URLSession?
`URLSession` не поддерживает FTP на iOS 16+. Используем собственный клиент через `Network.framework`.

### Файлы
- `Sources/FTPClient.swift` — весь сетевой код

### Архитектура FTPESFramer

**КЛЮЧЕВОЕ ПРАВИЛО:** Рукопожатие FTPES (Explicit TLS) происходит ВНУТРИ фреймера, ДО того как соединение переходит в `.ready`.

```
Порядок работы FTPESFramer:
1. start() → возвращает .willMarkReady (НЕ .ready!)
2. handleInput() получает "220 ..." (banner)
3. Фреймер отправляет "AUTH TLS\r\n" 
4. handleInput() получает "234 ..."
5. prependApplicationProtocol(tlsOptions) — добавляем TLS
6. passThroughInput() + passThroughOutput() — фреймер уходит в сторону
7. markReady() — только ПОСЛЕ успешного TLS
```

**ЗАПРЕЩЕНО** в `testConnection` и `upload`:
- ❌ Вручную читать баннер "220"
- ❌ Вручную отправлять "AUTH TLS"
- ❌ Вызывать `upgradeToTLS()` после `waitForReady()`

**РАЗРЕШЕНО** после `waitForReady()`:
- ✅ Сразу отправлять "USER username\r\n" — соединение уже защищено TLS

---

## ⚠️ ИЗВЕСТНЫЕ ОШИБКИ И ИХ РЕШЕНИЯ

### 1. Error 53 (Software caused connection abort)
**Причина:** `prependApplicationProtocol` вызывался на соединении в состоянии `.ready`  
**Решение:** Перенести всё рукопожатие в `FTPESFramer.start()` + возвращать `.willMarkReady`

### 2. Таймаут USER (10.0 сек)
**Причина:** `DispatchQueue.main` в `sec_protocol_options_set_verify_block` блокирует UI-поток и вызывает дедлок при TLS-рукопожатии  
**Решение:** ВСЕГДА использовать `DispatchQueue.global()` для блоков верификации сертификатов:
```swift
// ✅ ПРАВИЛЬНО:
sec_protocol_options_set_verify_block(options, { _, _, done in
    done(true)
}, DispatchQueue.global())

// ❌ НЕПРАВИЛЬНО (вызывает дедлок):
sec_protocol_options_set_verify_block(options, { _, _, done in
    done(true)
}, DispatchQueue.main)
```

### 3. Ошибка баннера (Banner timeout)
**Причина:** Фреймер поглощает баннер "220" во время рукопожатия, но клиент пытается прочитать его повторно  
**Решение:** Никогда не читать баннер вручную в `testConnection`/`upload` — он уже обработан фреймером

### 4. Дублирующие объявления классов
**Причина:** Неточное применение diff-патчей при редактировании файлов  
**Решение:** Всегда проверять файл целиком после редактирования командой `git diff`

---

## 🔌 FTP-ХОСТЫ СТОКОВ

| Сток | Хост | Протокол | Порт |
|------|------|----------|------|
| Shutterstock | ftp.shutterstock.com | FTPES (Explicit TLS) | 21 |
| Adobe Stock | sftp.contributor.adobestock.com | SFTP | 22 |
| Alamy | ftp.upload.alamy.com | FTP/FTPES | 21 |
| Dreamstime | ftp.upload.dreamstime.com | FTP/FTPES | 21 |
| 123RF | ftp.123rf.com | FTP/FTPES | 21 |

**SFTP (Adobe Stock):** Полноценный SFTP не поддерживается. Для проверки соединения — только пинг TCP-порта 22 через `checkTCPReachability`.

### Shutterstock TLS
Сервер использует **TLSv1.2** с шифром `ECDHE-RSA-AES256-GCM-SHA384`.  
**SNI отключён** (закомментирован `sec_protocol_options_set_tls_server_name`) — некоторые FTP-серверы сбрасывают соединение при наличии SNI.

---

## 🚀 ПРОЦЕСС РАЗРАБОТКИ

### Обязательные шаги после изменений
1. `git diff` — проверить что изменилось
2. `git commit -m "Сообщение на русском языке"`
3. `git push origin main`
4. Проверить GitHub Actions на `https://github.com/samjan190799-cmyk/StockFlow.ios/actions`
5. Дождаться успешной сборки перед тестированием

### GitHub Actions
- Сборка происходит автоматически при каждом пуше в `main`
- Workflow файлы находятся в `.github/`
- Ошибки компиляции видны в логах Actions

---

## 📁 СТРУКТУРА ПРОЕКТА

```
StockFlow.ios/
├── Sources/
│   ├── FTPClient.swift       ← Весь сетевой код FTP/FTPES
│   ├── DesignSystem.swift    ← Дизайн-система (цвета, компоненты, анимации)
│   ├── AIManager.swift       ← Интеграция с ИИ для метаданных
│   ├── AIMetadataView.swift  ← UI генерации метаданных
│   ├── AIAssistantView.swift ← UI ИИ-ассистента
│   ├── StockSettingsView.swift ← UI настроек стоков
│   ├── GalleryView.swift     ← главный экран (сетка, этапы, панель действий)
│   ├── DesignKit.swift       ← общие элементы дизайна (карточки, секции, строки, кнопки)
│   ├── QueueViewModel.swift  ← очередь: ИИ, загрузка, импорт
│   ├── SystemSettingsView.swift ← Системные настройки
│   ├── AuthHelper.swift      ← Помощник авторизации
│   ├── KeychainHelper.swift  ← Работа с Keychain
│   ├── Models.swift          ← Модели данных
│   └── SmartStockApp.swift   ← Точка входа приложения
├── .github/                  ← GitHub Actions workflows
├── project.yml               ← XcodeGen конфигурация
└── AGENT_INSTRUCTIONS.md     ← ЭТОТ ФАЙЛ
```

---

## 🤖 КАК ПЛАНИРОВЩИКУ СОСТАВЛЯТЬ ПЛАН

**Перед составлением плана, планировщик ОБЯЗАН:**

1. ✅ Прочитать этот файл (`AGENT_INSTRUCTIONS.md`)
2. ✅ Прочитать список файлов в `Sources/`
3. ✅ Если задача связана с сетью — перечитать раздел "Сетевая архитектура"
4. ✅ Проверить раздел "Известные ошибки" на предмет схожих проблем
5. ✅ В плане указать конкретные файлы, которые будут изменены
6. ✅ Убедиться что план написан на русском языке

**Шаблон плана:**
```
## Анализ проблемы
[Что сломано и почему, со ссылкой на файл]

## Причина
[Конкретная техническая причина]

## Решение
[Конкретные изменения в конкретных файлах]

## Проверка
[Как проверим что работает]
```

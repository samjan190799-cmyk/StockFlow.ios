# StockFlow iOS — Проект

## О проекте
iOS-приложение на Swift/SwiftUI для загрузки фотографий на фотостоки (Shutterstock, Adobe Stock, iStock и др.) с ИИ-анализом метаданных.

- **Bundle ID:** `com.samvel.smartstock.SmartStock`
- **iOS Deployment Target:** 16.0
- **Build Tool:** XcodeGen (`project.yml`)
- **GitHub:** https://github.com/samjan190799-cmyk/StockFlow.ios

---

## Структура проекта

```
Sources/
├── SmartStockApp.swift       — точка входа, AppDelegate, TabBar
├── UploadQueueView.swift     — очередь загрузки, QueueViewModel
├── AIAssistantView.swift     — вкладка ИИ-ассистента
├── AIMetadataView.swift      — экран редактирования метаданных
├── AIManager.swift           — Gemini/OpenAI интеграция
├── StockSettingsView.swift   — настройки фотостоков (FTP логин/пароль)
├── SystemSettingsView.swift  — системные настройки приложения
├── AuthHelper.swift          — вход через Apple/Google
├── FTPClient.swift           — ✅ ИСПРАВЛЕН — загрузка файлов на FTP/FTPS
├── KeychainHelper.swift      — хранение паролей в Keychain
├── DesignSystem.swift        — UI компоненты и цвета
├── Models.swift              — модели данных (PhotoMetadata, StockPlatform)
├── Info.plist
└── Assets.xcassets/
project.yml                   — XcodeGen конфигурация
```

---

## ✅ Исправления (сессия 2026-06-17)

### Проблема
**Ошибка:** `Network.NWError error 53 – Software caused connection abort` при загрузке на Shutterstock.

### Причины (были в оригинале)
1. **`FTPClient.swift`** использовал кастомный `NWProtocolFramer` для FTPS-апгрейда TLS — это нестандартный и нерабочий способ на iOS.
2. Функция `upgradeToTLS()` через `framer.prependApplicationProtocol()` прерывала соединение.
3. Отсутствовал таймаут в `waitForReady()`.
4. В `UploadQueueView.performRealUpload` ломался хост (sftp→ftp замена делалась некорректно).

### Решение
**Переписан `FTPClient.swift`** — теперь использует `URLSession.upload(for:from:)`:
- Нативная поддержка iOS FTP/FTPS через `URLSession`
- Retry-логика: 3 попытки с экспоненциальной задержкой (2с, 4с)
- Таймаут 300 секунд для больших файлов
- Правильное определение схемы (ftp/ftps/sftp) по хосту
- Поддержка TLS-сертификатов через `URLSessionTaskDelegate`

**Исправлен `UploadQueueView.swift`** — убрана ручная замена хоста, FTPClient сам определяет протокол.

---

## Как собрать

1. Установить XcodeGen: `brew install xcodegen`
2. В папке проекта: `xcodegen generate`
3. Открыть `SmartStock.xcodeproj` в Xcode
4. Выбрать свой Team в Signing settings
5. Собрать на устройство

---

## Известные ограничения
- **Adobe Stock / Freepik** — используют SFTP (не FTP). `URLSession` не поддерживает SFTP нативно. Эти стоки показывают предупреждение в UI.
- Для SFTP в будущем нужна библиотека типа NMSSH или LibSSH2.

---

## Состояние работы (продолжить здесь)

- [x] Исправлен FTPClient.swift (URLSession вместо NWProtocolFramer)
- [x] Исправлен UploadQueueView.swift (убрана некорректная замена хоста)
- [ ] Тестирование загрузки на Shutterstock с реальными кредентиалами
- [ ] Возможно добавить прогресс-бар загрузки (через `URLSessionTaskDelegate`)
- [ ] SFTP поддержка (Adobe Stock, Freepik) — требует внешней библиотеки

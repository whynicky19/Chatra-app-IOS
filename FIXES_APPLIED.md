# Chatra — что исправлено

**Дата:** 30 июля 2026 · дополнение к `AUDIT_REPORT.md`

Изменено 32 файла, добавлено 14. Полный список — в конце.

> **Важно:** статический анализ и тесты в моей среде запустить нельзя (нет
> Flutter SDK). Проверял скриптами: баланс скобок во всех 80 Dart-файлах,
> разрешение относительных импортов, наличие импортов для каждого введённого
> символа, отсутствие ссылок на удалённое, валидность всех XML/plist.
> **Обязательно прогоните `flutter analyze` и `flutter test` локально** —
> команды в конце.

---

## Поправка к отчёту: H-2 был ложным срабатыванием

В аудите я написал, что `_saveHistory()` в `class_ai_tab.dart` — пустая
заглушка. **Это неверно.** Мой `sed` при первом чтении обрезал файл ровно на
строке 120 и отрезал тело метода; я принял артефакт инструмента за баг.
Метод реализован полностью и работает.

Что осталось от этого пункта после перепроверки: снимаю снапшот `_msgs`
перед асинхронной записью, чтобы `jsonEncode` не сериализовал список,
изменившийся за время ожидания `SharedPreferences`. Это LOW, а не HIGH.

Приношу извинения — вывод инструмента нужно было перепроверить до включения
в отчёт.

---

## CRITICAL

| # | Статус | Что сделано |
|---|--------|-------------|
| C-1 | ✅ исправлено | `dev_code` подставляется только под `kDebugMode` |
| C-2 | ✅ исправлено | `aps-environment`, capability Push, `UIBackgroundModes` |
| C-3 | ⚠️ клиент готов | UI и API-слой модерации написаны; **нужен бэкенд** |
| C-4 | ⛔ за вами | Нужно сгенерировать keystore — я не могу создать ваш ключ подписи |
| C-5 | ✅ исправлено | Токен только на свой хост + отдельный клиент для CDN |

### C-1 — автоподстановка кода сброса пароля

`forgot_password_screen.dart`, `verify_email_screen.dart`:

```dart
// было
if (devCode.isNotEmpty) _code.text = devCode;

// стало
if (kDebugMode && devCode.isNotEmpty) _code.text = devCode;
```

**Остаётся на бэкенде:** убрать `dev_code` из ответа для всех окружений,
кроме локального. Клиент теперь защищён, но дырку в API стоит закрыть тоже.

### C-2 — push на iOS

`Runner.entitlements` получил `aps-environment`, в `project.pbxproj` добавлена
`SystemCapabilities → com.apple.Push`, в `Info.plist` — `UIBackgroundModes:
remote-notification`. Плюс `PushService` больше не проглатывает ошибку молча:

```dart
if (token == null) {
  logError('PushService.getToken', StateError('FCM token is null'));
  return;
}
```

**Проверьте в Xcode:** Signing & Capabilities → должно быть «Push
Notifications». Пуш нужно тестировать на физическом устройстве через
TestFlight — в симуляторе APNs не работает.

### C-3 — модерация UGC

Написано:

- `api_service.dart` — `reportContent`, `blockUser`, `unblockUser`,
  `getBlockedUsers`, `adminReports`, `adminResolveReport`;
- `lib/providers/moderation_provider.dart` — блок-лист с оптимистичными
  мутациями и откатом, сброс при смене аккаунта;
- `lib/screens/moderation/report_sheet.dart` — шторка жалобы (5 причин +
  комментарий) и меню «пожаловаться / заблокировать»;
- `lib/screens/settings/blocked_users_screen.dart` — список заблокированных
  с разблокировкой, подключён в «Безопасность»;
- меню «…» на постах теперь **у всех**, а не только у учителя (раньше
  пожаловаться было физически невозможно);
- кнопка «Пожаловаться» под каждым ответом ИИ — Apple требует это для
  генеративного контента;
- 4-я вкладка «Жалобы» в админке (строка `no_reports` и пуш `admin_report`
  существовали давно, экрана к ним не было);
- контент заблокированных авторов скрывается локально в ленте постов.

**Блокер:** эндпоинтов на бэкенде нет. Контракт с примерами запросов/ответов
и кодов — в `docs/MODERATION_API.md`. Без него кнопки будут возвращать ошибку,
и ревью App Store это не пройдёт.

### C-4 — подпись Android (требует вашего действия)

Keystore я сгенерировать не могу — это ваш приватный ключ, его нельзя
создавать в чужой среде и передавать через чат. Потеря ключа = потеря
возможности обновлять приложение в Play навсегда.

```bash
keytool -genkey -v -keystore ~/chatra-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias chatra
cp android/key.properties.example android/key.properties
# заполнить storeFile / storePassword / keyAlias / keyPassword
```

Что сделал я: превратил тихое предупреждение в жёсткую ошибку сборки, чтобы
AAB с debug-ключом нельзя было собрать случайно:

```kotlin
if (project.hasProperty("ciRelease")) {
    throw GradleException("android/key.properties не найден — релизная сборка запрещена.")
}
```

Собирать релиз: `./gradlew bundleRelease -PciRelease` или обычный
`flutter build appbundle` (тогда сработает только warning).

### C-5 — утечка токена на внешние хосты

```dart
// api_service.dart — интерцептор
if (_token != null &&
    options.extra['_skipAuth'] != true &&
    _isOwnHost(options)) {          // ← новое
  options.headers['Authorization'] = 'Bearer $_token';
}
```

Добавлен `_plainDio` без интерцепторов и `clientForUrl(url)`, который выбирает
клиент по хосту. Переведены `fetchFileText`, `file_opener.dart` и —
**найдено при верификации** — ещё одна точка скачивания в
`class_detail_screen.dart:344`, которую я пропустил при первом проходе.

---

## HIGH

| # | Статус | Что сделано |
|---|--------|-------------|
| H-1 | ✅ | `initialsFrom()` + 11 тестов на RangeError |
| H-2 | ↩️ отозвано | Ложное срабатывание, см. выше |
| H-3 | ✅ | Валидация имени по Unicode-буквам вместо кириллицы |
| H-4 | ✅ | 4 ключа добавлены + тест, ловящий такие пропуски |
| H-5 | ✅ | `android:label="Chatra"` |
| H-6 | ✅ | 4 зависимости и `RECORD_AUDIO` удалены |
| H-7 | ✅ | Лимиты 25 МБ / 10 файлов / белый список типов |
| H-8 | ✅ | Окно контекста ИИ 20 сообщений + 6 тестов |
| H-9 | ✅ | `reset()` у трёх провайдеров при смене аккаунта |
| H-10 | ✅ | uid фиксируется в `initState` |
| H-11 | ✅ | Privacy Manifest и текст политики приведены к реальности |

**H-3 — важно:** та же кириллица-only проверка нашлась **вторым местом**, в
`settings_screen.dart` (редактирование профиля) — её отловила верификация,
в первоначальном аудите я её пропустил. Исправлены обе.

**H-6** — удалены `record`, `just_audio`, `video_player`,
`permission_handler` (0 использований). `RECORD_AUDIO`,
`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` вырезаны через `tools:node="remove"`
на случай транзитивного подтягивания. Из `Info.plist` убран микрофон, из
Privacy Manifest — `AudioData`, из текста политики (3 языка) — камера и
микрофон, которых в приложении нет. Удалён мёртвый ключ `'camera'`.

**H-7** — новый `lib/utils/upload_limits.dart` с единой обёрткой
`pickUploadFiles()`: фильтр по расширениям в самом пикере, проверка размера и
количества, понятная ошибка. Подключена во всех 6 точках. Параллельный
`Future.wait` заменён на последовательную загрузку (он держал в памяти все
файлы сразу).

---

## MEDIUM и LOW

Исправлены все 23. Ключевое:

- **M-1** `_authRetried` — конец бесконечному циклу refresh → retry → 401.
- **M-2** `_asList()` / `_asMap()` — **37 непроверенных приведений** в
  `api_service.dart` переведены на безопасные хелперы.
- **M-3** Поллинг сети раз в 2 с навсегда → экспоненциальный откат 2→60 с
  плюс остановка в фоне через `WidgetsBindingObserver`.
- **M-4** Снят глобальный `resizeToAvoidBottomInset: false` — клавиатура
  больше не перекрывает поле ввода ИИ; навбар прячется, пока она поднята.
- **M-5** Векторная иконка уведомлений `ic_notification.xml` + акцентный цвет
  (был белый квадрат в статус-баре).
- **M-6** `minSdk 24`, `targetSdk 35`, `compileSdk 35` — зафиксированы явно.
- **M-7** `isMinifyEnabled` + `proguard-rules.pro` с keep-правилами для
  Flutter/Firebase.
- **M-8** `INTERNET` и `ACCESS_NETWORK_STATE` объявлены явно в main-манифесте.
- **M-9** Ссылка на политику конфиденциальности добавлена на экран регистрации.
- **M-10** Диалог загрузки файла больше не «залипает»: навигатор берётся до
  первого `await`.
- **M-11** Неизвестный маршрут возвращает `null` вместо второго `_AuthGate`;
  `s.arguments as int` заменён на проверку типа.
- **M-12** Из `Info.plist` убраны `NSAllowsLocalNetworking` и строка про
  «дев-сервер при разработке».
- **M-13** История ИИ исключена из бэкапов Android (`backup_rules.xml`,
  `data_extraction_rules.xml`).
- **M-14** `clearError()` уведомляет слушателей; ошибка фонового бейджа больше
  не всплывает тостом.
- **L-1** Тема по умолчанию — системная.
- **L-2** `autofillHints` + `AutofillGroup` на всех экранах авторизации.
- **L-4** `async void` → `Future<void>` в обоих `_send`.
- **L-5** Убран `parseServerDate(...)!` из `build`.
- **L-8** `ios/Podfile.lock` больше не игнорируется.
- **L-9** `flutter_lints` 3.0.1 → 6.0.0.

**L-3 — поправка:** я написал, что студенты дёргают админский фолбэк в
`getClassMembers`. Проверил вызовы — метод зовётся **только** из админ-экрана,
так что лишних 403 не было. Сигнатуру всё равно сделал явной
(`isAdmin: false` по умолчанию, `rethrow` вместо молчаливого фолбэка).

---

## Верификация

Что прогнал и с каким результатом:

| Проверка | Результат |
|----------|-----------|
| Баланс скобок/строк, 80 Dart-файлов | без дисбаланса |
| Относительные импорты | 0 битых |
| Импорты для 9 введённых символов | все на месте |
| Ссылки на удалённый код | чисто (после 3 доправок) |
| Ключи локализации RU/KZ/EN | 709 / 709 / 709, расхождений нет |
| Используемые ключи не определены | 0 |
| `TabController(length)` vs вкладки админки | 4 / 4 / 4 |
| XML и plist (8 файлов) | все парсятся |
| `aps-environment`, `UIBackgroundModes` | на месте |
| Privacy Manifest: `AudioData` | удалён |
| Существующие тесты на удалённые API | не затронуты |

**Верификация нашла 3 реальных пропуска**, которые я допустил при правках:
кириллица-only во втором месте, `api.dio.download` в обход безопасного
клиента и осиротевший ключ `name_cyrillic_only`. Все исправлены.

### Что нужно прогнать вам

```bash
flutter pub get          # обязательно: изменён pubspec (удалены 4 пакета)
flutter analyze          # flutter_lints 6.x строже — возможны новые warning'и
flutter test

cd ios && pod install && cd ..

flutter build appbundle --release \
  --dart-define=API_URL=https://<домен> \
  --obfuscate --split-debug-info=build/symbols
```

`flutter_lints` подняли на 6.0.0 — он включает правила, которых не было в
3.0.1. Часть новых замечаний почти наверняка появится в старом коде; это
информация к сведению, а не регресс от правок.

---

## Изменённые файлы

**Dart (23)**

```
lib/main.dart
lib/providers/ai_chats_provider.dart
lib/providers/auth_provider.dart
lib/providers/classes_provider.dart
lib/providers/l10n_provider.dart
lib/providers/theme_provider.dart
lib/screens/admin/admin_screen.dart
lib/screens/ai/widgets/ai_conversation_view.dart
lib/screens/auth/forgot_password_screen.dart
lib/screens/auth/login_screen.dart
lib/screens/auth/register_screen.dart
lib/screens/auth/verify_email_screen.dart
lib/screens/classes/assignment_detail_screen.dart
lib/screens/classes/class_detail_screen.dart
lib/screens/classes/tabs/class_ai_tab.dart
lib/screens/classes/tabs/class_assignments_tab.dart
lib/screens/classes/tabs/class_posts_tab.dart
lib/screens/main_shell.dart
lib/screens/settings/security_settings_screen.dart
lib/screens/settings/settings_screen.dart
lib/services/api_service.dart
lib/services/push_service.dart
lib/utils/file_opener.dart
```

**Конфиги (9)**

```
pubspec.yaml
.gitignore
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/res/values/colors.xml
ios/Runner/Info.plist
ios/Runner/Runner.entitlements
ios/Runner/PrivacyInfo.xcprivacy
ios/Runner.xcodeproj/project.pbxproj
```

**Новые (14)**

```
lib/providers/moderation_provider.dart
lib/screens/moderation/report_sheet.dart
lib/screens/settings/blocked_users_screen.dart
lib/utils/ai_context.dart
lib/utils/initials.dart
lib/utils/upload_limits.dart
test/ai_context_test.dart
test/initials_test.dart
test/l10n_keys_test.dart
android/app/proguard-rules.pro
android/app/src/main/res/drawable/ic_notification.xml
android/app/src/main/res/xml/backup_rules.xml
android/app/src/main/res/xml/data_extraction_rules.xml
docs/MODERATION_API.md
```

---

## Что осталось до подачи

1. **Бэкенд модерации** по `docs/MODERATION_API.md` — блокер App Store.
2. **Keystore** и `android/key.properties` — блокер Google Play.
3. **`dev_code`** убрать из ответов прод-API.
4. **Демо-аккаунт** (student + teacher) в App Store Connect → App Review
   Information, иначе ревьюер застрянет на верификации почты.
5. **Метки приватности**: App Privacy = Email, Name, User ID, User Content,
   Photos, Crash Data — всё «App Functionality», Tracking = No. Play Data
   Safety — те же категории + Crash logs.
6. **E-mail поддержки** для Play — Telegram как единственный канал
   недостаточен.
7. **Проверка на устройствах**: авиарежим на всех экранах, смена аккаунта,
   push на физическом iPhone, клавиатура в ИИ-чате, регистрация с латинским
   именем, удаление аккаунта.

Бэкенд я по-прежнему не смотрел — вы сказали, что дадите путь, но не назвали
его. IDOR, инъекции, rate limiting и реальное удаление данных при
`DELETE /auth/me` остаются непроверенными.

# Chatra — предрелизный аудит (App Store / Google Play)

**Дата:** 30 июля 2026
**Версия:** 1.0.0+1 · Bundle ID `kz.chatra.app`
**Объём:** 19 633 строк Dart (65 файлов) + iOS/Android нативные конфиги
**Режим:** аудит без правок кода (по вашему выбору). Все исправления даны как готовые патчи.

---

## Резюме

Кодовая база **заметно выше среднего**: аккуратный refresh-token flow с дедупликацией,
LRU-кэши с эвикцией, продуманная работа с часовыми поясами, `RepaintBoundary` в горячих
местах, полная локализация (669 ключей × RU/KZ/EN без пропусков), `mounted`-гварды
почти везде (99 штук), Crashlytics с `runZonedGuarded`.

Но **релиз в текущем виде невозможен**. Найдено 5 блокеров:

| # | Блокер | Последствие |
|---|--------|-------------|
| C-1 | Клиент автоподставляет `dev_code` из ответа сервера в поле кода сброса пароля | Захват любого аккаунта, если бэкенд когда-либо вернёт это поле в проде |
| C-2 | `Runner.entitlements` пуст — нет `aps-environment`, нет capability Push в Xcode | Push на iOS не работает вообще в релизной сборке |
| C-3 | Нет UI жалоб / блокировки пользователей при наличии UGC | Отклонение по App Store Guideline 1.2 |
| C-4 | `android/key.properties` отсутствует → release подписывается debug-ключом | Google Play отклонит загрузку AAB |
| C-5 | Bearer-токен уходит на произвольные внешние хосты (`fetchFileText`, `dio.download`) | Утечка access-токена на CDN/сторонний хост |

Итого: **5 CRITICAL, 11 HIGH, 14 MEDIUM, 9 LOW**.

---

# CRITICAL

## C-1. Автоподстановка кода сброса пароля из ответа сервера

**Риск:** CRITICAL (полный захват аккаунта)
**Файлы:** `lib/providers/auth_provider.dart:204–221`, `lib/screens/auth/forgot_password_screen.dart:47–51`, `lib/screens/auth/verify_email_screen.dart:57–60`

**Описание.** Клиент безусловно читает поле `dev_code` из ответа `/auth/forgot-password`
и `/auth/resend-verification` и **вписывает его прямо в поле ввода кода**:

```dart
// forgot_password_screen.dart:47
final devCode = await context.read<AuthProvider>()
    .forgotPassword(_email.text.trim(), orgType: widget.orgType);
if (!mounted) return;
setState(() { _codeSent = true; _busy = false; });
if (devCode.isNotEmpty) _code.text = devCode;   // ← код подставлен автоматически
```

**Причина.** Отладочное удобство (не ждать письма) не отделено от релизной сборки:
нет ни `kDebugMode`, ни проверки окружения. Клиент доверяет тому, что прод-бэкенд
никогда не пришлёт `dev_code`.

**Почему это критично.** Достаточно одного из сценариев — флаг `DEBUG=1` забыт в проде,
падение SMTP с fallback-веткой, откат конфига, staging-домен в `--dart-define` — и любой
человек, знающий чужой e-mail, вводит его, получает автоматически заполненный код и
меняет пароль. Клиент обязан не принимать секрет по каналу, который его не должен нести.

**Способ исправления.** Убрать автоподстановку из релиза целиком:

```dart
// forgot_password_screen.dart
import 'package:flutter/foundation.dart';   // добавить

// ...
if (kDebugMode && devCode.isNotEmpty) _code.text = devCode;
```

```dart
// verify_email_screen.dart:60
if (kDebugMode && res != null && res.devCode.isNotEmpty) _code.text = res.devCode;
```

Отдельно на бэкенде: удалить `dev_code` из схемы ответа для любого окружения,
кроме локального, и покрыть тестом (ответ прод-конфига не содержит ключа).

**Изменённые файлы:** `lib/screens/auth/forgot_password_screen.dart`,
`lib/screens/auth/verify_email_screen.dart` (+ бэкенд: `routers/auth.py`).

---

## C-2. Push-уведомления на iOS не заработают: нет entitlement

**Риск:** CRITICAL (заявленная функция мертва в релизе)
**Файлы:** `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist`

**Описание.** `Runner.entitlements` — пустой словарь:

```xml
<plist version="1.0">
<dict>
</dict>
</plist>
```

В `project.pbxproj` нет ни одного упоминания `aps-environment`, `SystemCapabilities`
или `com.apple.Push` (проверено `grep`). При этом в проекте подключены
`firebase_messaging: ^16.4.3`, полноценный `PushService`, канал уведомлений и
роутинг по типам пушей.

**Причина.** Capability «Push Notifications» не добавлена в Xcode → файл entitlements
создан, но остался пустым.

**Последствие.** `FirebaseMessaging.getToken()` на iOS вернёт `null` или бросит
исключение (оно проглатывается в `PushService.onAuthenticated`, строка 80–82),
устройство не зарегистрируется в APNs. Пуши не придут никогда, и это тихий отказ —
пользователь не увидит ошибки.

**Способ исправления.**

1. Xcode → Runner → Signing & Capabilities → **+ Capability → Push Notifications**.
2. Проверить, что `Runner.entitlements` стал таким:

```xml
<dict>
    <key>aps-environment</key>
    <string>development</string>
</dict>
```

(для App Store сборки Xcode подставит `production` автоматически)

3. Добавить в `ios/Runner/Info.plist` фоновый режим (для доставки data-сообщений):

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

4. В `PushService.onAuthenticated` заменить проглатывание ошибки на `logError(...)`,
   чтобы такой отказ был виден в Crashlytics.

**Изменённые файлы:** `ios/Runner/Runner.entitlements`, `ios/Runner/Info.plist`,
`ios/Runner.xcodeproj/project.pbxproj`, `lib/services/push_service.dart`.

---

## C-3. Нет механизма жалоб и блокировки пользователей при наличии UGC

**Риск:** CRITICAL (гарантированное отклонение Apple)
**Файлы:** весь `lib/screens/classes/`, `lib/services/api_service.dart`, `lib/providers/l10n_provider.dart`

**Описание.** Приложение содержит пользовательский контент: посты в классах, лекции,
файлы, сдачи заданий, комментарии-фидбэк преподавателя, AI-чат. Пользователи видят
контент друг друга.

При этом:

* в `api_service.dart` **нет ни одного эндпоинта жалобы** (`/reports`, `/complaints`, `/moderation` — отсутствуют);
* по всему `lib/screens/` **нет ни одной кнопки «Пожаловаться» или «Заблокировать»**;
* ключ локализации `'no_reports'` («Жалоб нет») определён во всех трёх языках,
  но **не используется ни в одном экране** — заготовка админской очереди модерации
  так и не была подключена;
* `PushService._routeByType` обрабатывает тип `'admin_report'` и переключает на
  вкладку админа — то есть бэкенд-часть жалоб существует, а клиентская нет.

**Причина.** Функциональность модерации спроектирована (пуш, админ-вкладка, строки),
но UI подачи жалобы и блокировки не реализован.

**Требование Apple.** Guideline 1.2 (User-Generated Content) требует одновременно:
1. фильтрацию недопустимого контента,
2. **механизм подачи жалобы на контент** с реакцией,
3. **возможность заблокировать пользователя**,
4. контактные данные для обращений.

Также App Review Guideline 1.2 в редакции для генеративного ИИ требует репорта на
ответы модели. Google Play предъявляет то же в Policy «User Generated Content».

**Способ исправления.** Минимальный объём, который проходит ревью:

1. Бэкенд: `POST /reports` (`{target_type, target_id, reason, comment}`),
   `POST /users/{id}/block`, `DELETE /users/{id}/block`, `GET /me/blocked`.
2. Клиент: в `api_service.dart` добавить

```dart
Future<void> reportContent({
  required String targetType,   // 'post' | 'assignment' | 'submission' | 'ai_message' | 'user'
  required int targetId,
  required String reason,
  String? comment,
}) async {
  await _dio.post('/reports', data: {
    'target_type': targetType,
    'target_id': targetId,
    'reason': reason,
    if (comment != null) 'comment': comment,
  });
}

Future<void> blockUser(int userId) async => _dio.post('/users/$userId/block');
Future<void> unblockUser(int userId) async => _dio.delete('/users/$userId/block');
Future<List<dynamic>> blockedUsers() async {
  final r = await _dio.get('/me/blocked');
  return r.data is List ? r.data : [];
}
```

3. UI: long-press / «…» на посте, лекции, сдаче и на ответе ИИ → шторка с причинами
   («Спам», «Оскорбление», «Неприемлемый контент», «Другое»). В профиле автора —
   «Заблокировать пользователя». В Настройках — экран «Заблокированные».
4. Клиентская фильтрация: скрывать контент авторов из `blockedUsers()`.
5. В админ-вкладке подключить очередь жалоб (строка `no_reports` уже готова).
6. Реакция на жалобу — в течение 24 часов (Apple явно требует SLA).

**Изменённые файлы:** `lib/services/api_service.dart`, новые
`lib/screens/moderation/report_sheet.dart`, `lib/screens/settings/blocked_users_screen.dart`,
`lib/screens/admin/admin_screen.dart`, `lib/screens/classes/tabs/class_posts_tab.dart`,
`lib/screens/ai/widgets/ai_conversation_view.dart`.

---

## C-4. Release-сборка Android подписывается debug-ключом

**Риск:** CRITICAL (загрузка в Play невозможна)
**Файлы:** `android/app/build.gradle.kts`, `android/key.properties` (отсутствует)

**Описание.** Логика подписи корректна и честно предупреждает, но файла нет:

```kotlin
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null
// ...
release {
    signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release")
    else {
        logger.warn("⚠️  android/key.properties не найден — release подписан DEBUG-ключом...")
        signingConfigs.getByName("debug")
    }
}
```

Проверка: `ls android/key.properties` → файла нет, `*.jks` в репозитории нет.

**Причина.** Релизный keystore ещё не сгенерирован (или не разложен на машине сборки).

**Последствие.** `flutter build appbundle --release` соберётся молча (только warning
в логе) и создаст AAB, подписанный debug-сертификатом. Play Console отклонит его
с ошибкой «You uploaded an APK/AAB that was signed in debug mode».

**Способ исправления.**

```bash
keytool -genkey -v -keystore ~/chatra-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias chatra
```

`android/key.properties` (уже в `.gitignore`):

```properties
storePassword=<...>
keyPassword=<...>
keyAlias=chatra
storeFile=/Users/whynicky/chatra-release.jks
```

Дополнительно — превратить warning в жёсткую ошибку для CI, чтобы такой AAB
физически нельзя было собрать:

```kotlin
release {
    if (!hasReleaseKeystore) {
        if (project.hasProperty("ciRelease")) {
            throw GradleException("key.properties отсутствует — release-сборка запрещена")
        }
        logger.warn("⚠️  ...")
    }
    signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release")
                    else signingConfigs.getByName("debug")
}
```

Ключ и пароли — в 1Password/секреты CI, `.jks` **никогда** в git.

**Изменённые файлы:** `android/key.properties` (создать), `android/app/build.gradle.kts`.

---

## C-5. Access-токен утекает на произвольные внешние хосты

**Риск:** CRITICAL (компрометация сессии)
**Файлы:** `lib/services/api_service.dart:60–66, 720–728`, `lib/utils/file_opener.dart:45–47`

**Описание.** Интерцептор добавляет `Authorization: Bearer` **ко всем** запросам
через инстанс `_dio`, независимо от хоста:

```dart
onRequest: (options, handler) {
  if (_token != null && options.extra['_skipAuth'] != true) {
    options.headers['Authorization'] = 'Bearer $_token';
  }
  return handler.next(options);
},
```

При этом два метода принимают **абсолютный URL произвольного происхождения**:

```dart
// api_service.dart:720 — url приходит из ответа сервера / текста ИИ
Future<String> fetchFileText(String url) async {
  final response = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain, ...));
```

```dart
// file_opener.dart:45 — cleanUrl из поля файла поста
await api.dio.download(cleanUrl, filePath, options: Options(receiveTimeout: ...));
```

По комментарию в `api_service.dart:730–738` файлы хранятся в **R2** — то есть URL
указывает на внешний домен Cloudflare, а не на ваш API.

**Причина.** Интерцептор авторизации привязан к Dio-инстансу, а не к базовому хосту.

**Последствие.** Bearer-токен уходит в заголовке на CDN. Если URL когда-нибудь придёт
из недоверенного источника (текст ответа ИИ, поле файла, отредактированное чужим
преподавателем, MITM на подписи), токен попадает к третьей стороне вместе с полным
доступом к аккаунту. R2 логирует заголовки запросов.

**Способ исправления.** Ограничить добавление токена своим хостом:

```dart
// api_service.dart
late final Uri _apiOrigin = Uri.parse(baseUrl);

bool _isOwnHost(RequestOptions o) {
  final u = o.uri;                       // Dio уже склеил base + path
  return u.host.isEmpty || u.host == _apiOrigin.host;
}

// в интерцепторе:
onRequest: (options, handler) {
  if (_token != null &&
      options.extra['_skipAuth'] != true &&
      _isOwnHost(options)) {
    options.headers['Authorization'] = 'Bearer $_token';
  }
  return handler.next(options);
},
```

Для скачивания внешних файлов завести отдельный «чистый» Dio без интерцепторов:

```dart
final Dio _plainDio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 5)));
Dio get downloadClient => _plainDio;
```

и в `file_opener.dart` использовать `api.downloadClient.download(...)` для хостов,
не совпадающих с API. То же — для `fetchFileText`.

**Изменённые файлы:** `lib/services/api_service.dart`, `lib/utils/file_opener.dart`.

---

# HIGH

## H-1. `RangeError` при формировании инициалов

**Риск:** HIGH (краш на реальных данных)
**Файлы:** `lib/providers/auth_provider.dart:33–40`, `lib/screens/classes/tabs/class_assignments_tab.dart:375, 686`

```dart
// auth_provider.dart:33
String get initials {
  if (fullName.isNotEmpty) {
    final parts = fullName.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName[0].toUpperCase();
  }
  ...
}
```

```dart
// class_assignments_tab.dart:375
final initials = name.length >= 2
    ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase()
    : name[0].toUpperCase();
```

**Причина.** `split(' ')` на строке с двойным пробелом, ведущим или хвостовым пробелом
даёт пустые элементы. `"Иван  Петров".split(' ')` → `['Иван', '', 'Петров']`, тогда
`parts[1][0]` → `RangeError (index): Invalid value: Valid value range is empty: 0`.
То же для `"Иван Петров ".split(' ').last` → `''` → `[0]` падает.

Поле ФИО при регистрации проходит `.trim()`, но **двойные пробелы внутри не режутся**,
а имена приходят и из админки (`adminCreateUser`), и с веб-версии, и из старых записей БД.
Инициалы рисуются в `build()` — это красный экран, а не пойманное исключение.

**Исправление.** Единый безопасный хелпер, один на всё приложение:

```dart
// lib/utils/initials.dart  (новый файл)
String initialsFrom(String? fullName, {String? email}) {
  final parts = (fullName ?? '')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.length == 1) return parts[0][0].toUpperCase();
  final e = email ?? '';
  return e.isNotEmpty ? e[0].toUpperCase() : '?';
}
```

и заменить оба места на `initialsFrom(name)` / `initialsFrom(fullName, email: email)`.

**Изменённые файлы:** новый `lib/utils/initials.dart`, `lib/providers/auth_provider.dart`,
`lib/screens/classes/tabs/class_assignments_tab.dart`.

---

## H-2. `_saveHistory()` в классном AI-чате — пустая заглушка

**Риск:** HIGH (нерабочая функция + мёртвый код)
**Файл:** `lib/screens/classes/tabs/class_ai_tab.dart:147–150`

```dart
void _saveHistory() {
  SharedPreferences.getInstance().then((prefs) {
  });
}
```

**Причина.** Тело метода было удалено (вероятно при рефакторинге на серверную историю),
но вызовы остались — метод дёргается **6 раз** (`_send`, ветка ошибки, `_syncFromServer`).

**Последствие.** Локальный кэш истории класcного ИИ никогда не пишется. Поле
`_historyKey` (строка 44) и метод `_loadLocal()` (строки 84–95) читают ключ, которого
не существует → офлайн-история класса всегда пустая, а ветка «импортировать локальное
в сервер» (`_syncFromServer`, строки 103–107) — недостижима. Плюс лишний вызов
`SharedPreferences.getInstance()` на каждое сообщение.

**Исправление** — либо дописать реализацию по образцу `ai_conversation_view.dart:143`:

```dart
void _saveHistory() {
  final key = _historyKey;
  final snapshot = List<Map<String, String>>.from(_msgs);
  SharedPreferences.getInstance().then((prefs) {
    try {
      prefs.setString(key, jsonEncode(snapshot));
    } catch (_) {}
  }).catchError((_) {});
}
```

либо, если локальный кэш класса сознательно упразднён, удалить `_saveHistory()`,
`_loadLocal()`, `_historyKey` и импорт-ветку целиком.

**Изменённые файлы:** `lib/screens/classes/tabs/class_ai_tab.dart`.

---

## H-3. Кириллица-only валидация имени блокирует ревьюера App Store

**Риск:** HIGH (отклонение Guideline 2.1)
**Файл:** `lib/screens/auth/register_screen.dart:218–232`

```dart
bool get _nameIsCyrillic {
  final n = _name.text.trim();
  if (n.isEmpty) return true;
  return RegExp(r'^[а-яА-ЯёЁәӘғҒқҚңҢөӨұҰүҮһҺіІ\s\-]+$').hasMatch(n);
}
```

Регистрация не пропускается, если ФИО не полностью кириллическое.

**Причина.** Допущение, что все пользователи — из кириллического региона.

**Последствие.** Ревьюер Apple (US) вводит «John Smith» → красная плашка
«name_cyrillic_only» и заблокированная кнопка. Ревьюер не может создать аккаунт и
отклоняет по 2.1 «Unable to complete registration». То же — казахская латиница,
которая официально вводится в Казахстане.

**Исправление.** Валидировать не алфавит, а осмысленность:

```dart
bool get _nameIsValid {
  final n = _name.text.trim();
  if (n.isEmpty) return true;
  // Любые буквы Unicode, пробел, дефис, апостроф. Без цифр и спецсимволов.
  return RegExp(r"^[\p{L}\p{M}\s\-']+$", unicode: true).hasMatch(n);
}
```

Обязательно **приложить к сборке демо-аккаунт** (App Store Connect → App Review
Information), иначе ревьюер всё равно застрянет на верификации e-mail.

**Изменённые файлы:** `lib/screens/auth/register_screen.dart`, `lib/providers/l10n_provider.dart`
(переформулировать `name_cyrillic_only`).

---

## H-4. Четыре ключа локализации не определены — в админке видны сырые строки

**Риск:** HIGH (видимо сломанный UI, «placeholder content»)
**Файлы:** `lib/providers/l10n_provider.dart`, `lib/screens/admin/admin_screen.dart:379, 1174, 1211, 1217, 1218, 1220`

**Описание.** Проверено скриптом: из 468 используемых ключей 4 отсутствуют во всех
трёх языках — `block`, `unblock`, `blocked_short`, `block_user_msg`.

`L10n.t()` при промахе возвращает сам ключ:

```dart
String t(String key) => (_strings[_lang] ?? _strings['RU']!)[key] ?? key;
```

**Последствие.** В админ-панели кнопка подписана буквально «block», бейдж —
«blocked_short», а диалог подтверждения — «block?» с текстом «block_user_msg».
Это ровно тот тип артефакта, который Apple классифицирует как незавершённое
приложение (Guideline 2.1). Иронично, что ломается именно экран модерации.

**Исправление.** Добавить в каждый языковой блок `l10n_provider.dart`:

```dart
// RU
'block': 'Заблокировать',
'unblock': 'Разблокировать',
'blocked_short': 'Заблокирован',
'block_user_msg': 'Пользователь не сможет войти в приложение. Действие обратимо.',

// KZ
'block': 'Бұғаттау',
'unblock': 'Бұғаттан шығару',
'blocked_short': 'Бұғатталған',
'block_user_msg': 'Пайдаланушы қолданбаға кіре алмайды. Әрекетті кері қайтаруға болады.',

// EN
'block': 'Block',
'unblock': 'Unblock',
'blocked_short': 'Blocked',
'block_user_msg': 'The user will not be able to sign in. This action can be undone.',
```

**Профилактика.** Добавить unit-тест, который падает при промахе ключа:

```dart
// test/l10n_keys_test.dart
test('все используемые ключи определены', () {
  final code = Directory('lib').listSync(recursive: true)
      .whereType<File>().where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('l10n_provider'))
      .map((f) => f.readAsStringSync()).join('\n');
  final used = RegExp(r"\.t\('([a-z0-9_]+)'\)")
      .allMatches(code).map((m) => m.group(1)!).toSet();
  final l = L10n();
  for (final lang in ['RU', 'KZ', 'EN']) {
    l.setLang(lang);
    for (final k in used) {
      expect(l.t(k), isNot(k), reason: '$lang: нет ключа "$k"');
    }
  }
});
```

**Изменённые файлы:** `lib/providers/l10n_provider.dart`, новый `test/l10n_keys_test.dart`.

---

## H-5. Название приложения на Android — «chatra_app»

**Риск:** HIGH (видимый дефект бренда)
**Файл:** `android/app/src/main/AndroidManifest.xml:6`

```xml
<application
    android:label="chatra_app"
```

**Причина.** Осталось значение из шаблона `flutter create` (имя пакета из `pubspec.yaml`).
На iOS это исправлено (`CFBundleDisplayName = Chatra`), на Android — нет.

**Последствие.** Под иконкой на домашнем экране, в списке приложений, в настройках
и в диалогах разрешений будет «chatra_app».

**Исправление.**

```xml
<application
    android:label="Chatra"
```

**Изменённые файлы:** `android/app/src/main/AndroidManifest.xml`.

---

## H-6. Разрешение `RECORD_AUDIO` при полностью отсутствующем использовании микрофона

**Риск:** HIGH (проверка Play + отклонение Apple по purpose string)
**Файлы:** `android/app/src/main/AndroidManifest.xml:2`, `ios/Runner/Info.plist`, `ios/Runner/PrivacyInfo.xcprivacy`, `pubspec.yaml`

**Описание.** Проверено по всему `lib/`: `record`, `just_audio`, `video_player`,
`permission_handler` — **0 использований**. Микрофон нигде не запрашивается.
При этом:

* `AndroidManifest.xml` объявляет `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`;
* `Info.plist` содержит `NSMicrophoneUsageDescription` — «Доступ к микрофону для голосовых сообщений и **записи образца голоса для AI-аватара**»;
* `PrivacyInfo.xcprivacy` декларирует сбор `NSPrivacyCollectedDataTypeAudioData` — «образец голоса для AI-аватара».

«AI-аватар» и голосовые сообщения в коде отсутствуют.

**Причина.** Функциональность была запланирована и отменена, а конфиги и зависимости
не откатили.

**Последствие.**
- **Google Play**: карточка приложения показывает «Микрофон» в списке разрешений;
  Play Console требует обоснование неиспользуемого чувствительного разрешения,
  Data Safety-декларация расходится с фактическим поведением.
- **Apple**: purpose string и Privacy Manifest описывают несуществующую функцию.
  Ревью 5.1.1 отклоняет purpose strings, не соответствующие реальному поведению;
  метка App Privacy будет заведомо неверной.
- Размер бинарника: 4 неиспользуемых нативных плагина.

**Исправление.**

1. `pubspec.yaml` — удалить `record`, `just_audio`, `video_player`, `permission_handler`, затем `flutter pub get`.
2. `AndroidManifest.xml` — убрать `RECORD_AUDIO`. Если разрешение подтягивается транзитивно, заблокировать явно:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove"/>
```

3. `Info.plist` — удалить `NSMicrophoneUsageDescription`.
4. `PrivacyInfo.xcprivacy` — удалить блок `NSPrivacyCollectedDataTypeAudioData`.
5. `l10n_provider.dart` — из текста политики (`pp_collect_body`, все 3 языка) убрать упоминание микрофона и записи аудио.
6. Проверить итог: `flutter build apk --release` → `aapt dump permissions build/app/outputs/flutter-apk/app-release.apk`.

**Изменённые файлы:** `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`,
`ios/Runner/Info.plist`, `ios/Runner/PrivacyInfo.xcprivacy`, `lib/providers/l10n_provider.dart`.

---

## H-7. Нет ограничения размера загружаемых файлов

**Риск:** HIGH (OOM, гарантированные таймауты, нагрузка на бэкенд)
**Файлы:** `lib/screens/classes/class_detail_screen.dart:581, 799, 922, 956, 1190`, `lib/screens/classes/assignment_detail_screen.dart:575`, `lib/services/api_service.dart:608–622`

**Описание.** По всей кодовой базе нет ни одной проверки размера файла (проверено
grep по `maxFileSize`, `1024 * 1024`, `lengthSync`). Везде:

```dart
final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
```

и затем **параллельная** отправка всех выбранных файлов:

```dart
final results = await Future.wait(
    validFiles.map((pf) => api.uploadFile(pf.path!, pf.name)), eagerError: true);
```

**Причина.** `FileType.any` + `allowMultiple` + отсутствие валидации + `Future.wait`.

**Последствие.**
- Студент прикрепляет видео с телефона (1–4 ГБ) → `sendTimeout` 2 минуты
  гарантированно истекает на мобильной сети, публикация падает с «upload_failed»
  без объяснения причины.
- Несколько крупных файлов одновременно через `Future.wait` — параллельные потоки
  multipart, пиковое потребление памяти кратно размеру, реальный риск OOM-kill
  на бюджетных Android.
- `eagerError: true` отменяет ожидание, но **не отменяет уже идущие запросы** —
  трафик продолжает литься.

**Исправление.** Валидация до отправки + последовательная загрузка:

```dart
// lib/utils/upload_limits.dart  (новый файл)
import 'dart:io';
import 'package:file_picker/file_picker.dart';

const int kMaxUploadBytes = 25 * 1024 * 1024;   // 25 МБ — согласовать с бэкендом
const int kMaxFilesPerPost = 10;

const kAllowedExtensions = <String>[
  'pdf','doc','docx','ppt','pptx','xls','xlsx','txt','md','rtf','csv',
  'png','jpg','jpeg','webp','heic','gif','zip',
];

/// null — всё в порядке; иначе ключ локализации ошибки.
String? validateUploads(List<PlatformFile> files) {
  if (files.length > kMaxFilesPerPost) return 'too_many_files';
  for (final f in files) {
    if (f.size > kMaxUploadBytes) return 'file_too_large';
    final ext = f.extension?.toLowerCase() ?? '';
    if (!kAllowedExtensions.contains(ext)) return 'file_type_not_allowed';
  }
  return null;
}
```

В пикере:

```dart
final result = await FilePicker.platform.pickFiles(
  allowMultiple: true,
  type: FileType.custom,
  allowedExtensions: kAllowedExtensions,
);
if (result != null) {
  final err = validateUploads(result.files);
  if (err != null) { showToast(context, l.t(err), error: true); return; }
  setS(() => lectureFiles.addAll(result.files));
}
```

Загрузку сделать последовательной с прогрессом (заменить `Future.wait`):

```dart
final fileUrls = <String>[];
for (var i = 0; i < validFiles.length; i++) {
  setS(() => uploadProgress = '${i + 1}/${validFiles.length}');
  final res = await api.uploadFile(validFiles[i].path!, validFiles[i].name);
  final url = res['url'] ?? res['file_url'] ?? res['path'];
  if (url == null || url.toString().isEmpty) throw Exception('upload_failed');
  fileUrls.add('$url#${Uri.encodeComponent(validFiles[i].name)}');
}
```

Добавить ключи `file_too_large`, `too_many_files`, `file_type_not_allowed` в 3 языка.
Лимит на бэкенде должен совпадать (проверка на клиенте — UX, не безопасность).

**Изменённые файлы:** новый `lib/utils/upload_limits.dart`,
`lib/screens/classes/class_detail_screen.dart`, `lib/screens/classes/assignment_detail_screen.dart`,
`lib/providers/l10n_provider.dart`.

---

## H-8. История ИИ отправляется целиком на каждый запрос — неограниченный рост

**Риск:** HIGH (стоимость, отказы, деградация)
**Файлы:** `lib/screens/ai/widgets/ai_conversation_view.dart:248–257`, `lib/screens/classes/tabs/class_ai_tab.dart:180–197`

```dart
final apiMsgs = <Map<String, dynamic>>[
  {'role': 'system', 'content': '...'},
  ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),   // ВСЯ история
];
final data = await api.aiChat(apiMsgs, threadId: threadId);
```

В классном чате к этому добавляется `lectureContext` (до 4000+5000 символов на файл,
см. `class_detail_screen.dart:186, 197`) и все `lectureImageUrls` как vision-вложения.

**Причина.** Нет окна контекста — ни по числу сообщений, ни по токенам.

**Последствие.** После ~40–60 сообщений запрос упирается в лимит контекста модели →
провайдер возвращает 400, клиент показывает generic «connection_error». Стоимость
токенов растёт квадратично по длине диалога. Тело POST разрастается до сотен КБ,
на слабой сети `sendTimeout` 30 секунд начинает истекать.

**Исправление.** Скользящее окно + резюме:

```dart
/// Последние N сообщений; system-промпт всегда сохраняется целиком.
const int _kContextWindow = 20;

List<Map<String, dynamic>> _windowed(List<Map<String, String>> msgs) {
  final tail = msgs.length <= _kContextWindow
      ? msgs
      : msgs.sublist(msgs.length - _kContextWindow);
  return tail.map((m) => {'role': m['role']!, 'content': m['text']!}).toList();
}
```

и использовать `..._windowed(_msgs)` вместо `..._msgs.map(...)`.

Правильнее — перенести сборку контекста на бэкенд: `thread_id` уже передаётся,
сервер хранит историю (`/ai/history`), значит клиенту достаточно слать **только новое
сообщение**. Это убирает дублирование, экономит трафик и закрывает проблему на корню.

Также заменить `e.toString().contains('503')` (`ai_conversation_view.dart:277`) на
разбор `DioException.type` — строковое сопоставление ломается при смене формулировки.

**Изменённые файлы:** `lib/screens/ai/widgets/ai_conversation_view.dart`,
`lib/screens/classes/tabs/class_ai_tab.dart`, `lib/services/api_service.dart`.

---

## H-9. Состояние провайдеров не очищается при смене аккаунта

**Риск:** HIGH (утечка данных между пользователями)
**Файлы:** `lib/providers/classes_provider.dart`, `lib/providers/ai_chats_provider.dart`, `lib/providers/auth_provider.dart:145–152`

**Описание.** `_performLogout()` обнуляет только `AuthProvider._user`:

```dart
Future<void> _performLogout({String? reason}) async {
  await onLogout?.call();
  if (reason == null) await api.logoutServer();
  await api.clearToken();
  _user = null;
  _sessionEndReason = reason;
  notifyListeners();
}
```

`ClassesProvider.posts`, `_cachedAllClasses`, `joinedClassIds`, `archivedClassIds`,
`notifBadge`, а также `AiChatsProvider.threads` **сохраняют данные предыдущего
пользователя** — они живут всё время работы процесса (созданы в `main()`).

**Причина.** Провайдеры не подписаны на событие выхода.

**Последствие.** Сценарий «выйти → войти другим аккаунтом» (обязательный кейс при
ревью, если у вас учитель + студент): между входом и завершением `load()` на главном
экране отрисовываются **классы и посты предыдущего пользователя**, бейдж уведомлений —
чужой, список ИИ-тредов — чужой. На медленной сети это секунды видимых чужих данных.
Если `load()` упадёт (офлайн) — чужие данные останутся на экране.

**Исправление.** Добавить в каждый провайдер `reset()`:

```dart
// classes_provider.dart
void reset() {
  posts = [];
  _cachedAllClasses = [];
  joinedClassIds = {};
  archivedClassIds = {};
  notifBadge.value = 0;
  loading = true;
  errorMessage = null;
  notifyListeners();
}
```

```dart
// ai_chats_provider.dart
void reset() {
  threads = [];
  loading = false;
  errorMessage = null;
  _legacyCleaned = false;
  notifyListeners();
}
```

и вызвать их из `main.dart` при выходе:

```dart
// main.dart, после создания провайдеров
auth.addListener(() {
  if (auth.userId != lastUid) {
    lastUid = auth.userId;
    CrashReporting.setUser(auth.userId);
    classes.reset();
    aiChats.reset();
  }
});
```

Дополнительно: локальные кэши в `SharedPreferences` уже разделены по `uid`
(`joined_classes_$uid`, `ai_chat_history_v2_${uid}_$threadId`) — это сделано правильно.

**Изменённые файлы:** `lib/providers/classes_provider.dart`,
`lib/providers/ai_chats_provider.dart`, `lib/main.dart`.

---

## H-10. Использование `BuildContext` после `await` в кэше истории ИИ

**Риск:** HIGH (исключение при закрытии экрана)
**Файл:** `lib/screens/ai/widgets/ai_conversation_view.dart:64–67, 90–102, 143–151`

```dart
String _historyKey(int threadId) {
  final uid = context.read<AuthProvider>().userId;      // ← нужен живой context
  return 'ai_chat_history_v2_${uid ?? 'anon'}_$threadId';
}

Future<List<Map<String, String>>> _loadLocal(int threadId) async {
  final prefs = await SharedPreferences.getInstance();  // ← async gap
  final raw = prefs.getString(_historyKey(threadId));   // ← context после gap
  ...
}

void _saveHistory() {
  final threadId = _threadId;
  if (threadId == null) return;
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString(_historyKey(threadId), jsonEncode(_msgs));  // ← context в callback
  });
}
```

**Причина.** Ключ вычисляется лениво, уже после асинхронного разрыва, вместо того
чтобы быть зафиксированным один раз в `initState`.

**Последствие.** Если пользователь закрывает чат в момент записи (типично: отправил
сообщение и сразу свайпнул назад), `context.read` на деактивированном виджете бросает
`FlutterError: Looking up a deactivated widget's ancestor is unsafe`. Внутри `.then()`
это неперехваченная ошибка в зоне → отчёт в Crashlytics, потерянная история.

**Исправление.** Зафиксировать uid один раз, как это уже сделано в `class_ai_tab.dart:53`:

```dart
late final String _uidPart;

@override
void initState() {
  super.initState();
  _uidPart = context.read<AuthProvider>().userId?.toString() ?? 'anon';
  _threadId = widget.threadId;
  _listVisible = _threadId == null;
  if (_threadId != null) _restoreHistory(_threadId!);
  _loadQuota();
}

String _historyKey(int threadId) => 'ai_chat_history_v2_${_uidPart}_$threadId';
```

Плюс снять снапшот `_msgs` перед асинхронной записью, иначе список может измениться
во время `jsonEncode`:

```dart
void _saveHistory() {
  final threadId = _threadId;
  if (threadId == null) return;
  final key = _historyKey(threadId);
  final snapshot = List<Map<String, String>>.from(_msgs);
  SharedPreferences.getInstance()
      .then((p) => p.setString(key, jsonEncode(snapshot)))
      .catchError((_) => false);
}
```

**Изменённые файлы:** `lib/screens/ai/widgets/ai_conversation_view.dart`.

---

## H-11. Приватность: Privacy Manifest и политика описывают несобираемые данные

**Риск:** HIGH (несоответствие метки App Privacy)
**Файлы:** `ios/Runner/PrivacyInfo.xcprivacy`, `lib/providers/l10n_provider.dart` (`pp_collect_body` ×3)

**Описание.** Помимо аудио (см. H-6), политика конфиденциальности утверждает:

> «Доступ к **камере**, фотогалерее и микрофону запрашивается только в момент,
> когда вы прикрепляете фото или файл, либо записываете аудио»

Фактически используется **только** `ImageSource.gallery`
(`home_screen.dart:751`, `class_detail_screen.dart:1480`). Камера не вызывается,
`NSCameraUsageDescription` в `Info.plist` отсутствует — то есть вызов камеры
привёл бы к немедленному падению iOS.

**Причина.** Тексты политики писались под планируемый, а не реализованный набор функций.

**Последствие.** Метка App Privacy в App Store Connect, Privacy Manifest, текст
политики и фактическое поведение расходятся втроём. Apple сверяет манифест с
реальными API; расхождения — повод для отклонения и для претензий регуляторов
(GDPR — принцип точности информирования).

**Исправление.**

1. `PrivacyInfo.xcprivacy` — удалить блок `NSPrivacyCollectedDataTypeAudioData`.
2. Добавить недостающие Required Reason API (для `path_provider` и плагинов кэша):

```xml
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>E174.1</string></array>
</dict>
```

3. `pp_collect_body` (RU/KZ/EN) — переписать: «Доступ к фотогалерее запрашивается
   только в момент, когда вы прикрепляете изображение или файл». Убрать камеру
   и микрофон.
4. Метку App Privacy в App Store Connect привести в точное соответствие:
   Email, Name, User ID, User Content, Photos — всё «App Functionality», без Tracking.
5. Google Play Data Safety заполнить теми же категориями + «Crash logs / Diagnostics»
   (Crashlytics), отметить шифрование при передаче и наличие удаления аккаунта.

**Изменённые файлы:** `ios/Runner/PrivacyInfo.xcprivacy`, `lib/providers/l10n_provider.dart`.

---

# MEDIUM

## M-1. Возможен бесконечный цикл обновления токена

**Файлы:** `lib/services/api_service.dart:67–89`

Повтор запроса после успешного refresh не помечается:

```dart
if (status == 401 && error.requestOptions.path != '/auth/refresh') {
  final newAccess = await _refreshAccessToken();
  if (newAccess != null) {
    final opts = error.requestOptions;
    opts.headers['Authorization'] = 'Bearer $newAccess';
    final response = await _dio.fetch(opts);   // ← если снова 401, цикл повторится
```

**Причина.** Нет флага «уже пробовали обновиться для этого запроса».
**Последствие.** Сервер, отдающий 401 при валидном токене (рассинхрон часов,
отозванный ключ подписи), уводит клиент в бесконечный цикл refresh → retry → 401,
с сетевым штормом и разряженной батареей.

**Исправление:**

```dart
if (status == 401 &&
    error.requestOptions.path != '/auth/refresh' &&
    error.requestOptions.extra['_authRetried'] != true) {
  final newAccess = await _refreshAccessToken();
  if (newAccess != null) {
    final opts = error.requestOptions;
    opts.extra['_authRetried'] = true;      // ← ключевая строка
    opts.headers['Authorization'] = 'Bearer $newAccess';
    ...
```

---

## M-2. Непроверенные приведения `response.data as List` — краш при нестандартном ответе

**Файлы:** `lib/services/api_service.dart:329, 334, 484, 490, 523, 574, 594, 627, 640, 678`

```dart
Future<List<dynamic>> getClasses() async {
  final response = await _dio.get('/classes/');
  return response.data;                      // implicit cast
}

Future<List<dynamic>> getAiHistory(...) async {
  ...
  return response.data as List<dynamic>;     // explicit cast
}
```

**Причина.** Часть методов защищена (`response.data is List ? ... : []` — см. строки
368, 407, 418), часть — нет. Единого правила нет.

**Последствие.** Прокси/ngrok/Cloudflare при ошибке отдают HTML или пустое тело →
`type 'String' is not a subtype of type 'List<dynamic>'`. В `ClassesProvider.load()`
это поймано, но, например, `getAiThreads()` (строка 523) вызывается из
`AiChatsProvider.load()` внутри try — а `getSubmissions()` в
`class_assignments_tab.dart:346` — нет.

**Исправление.** Единый хелпер и применить его ко всем «списочным» методам:

```dart
List<dynamic> _asList(dynamic data) {
  if (data is List) return data;
  if (data is Map && data['items'] is List) return data['items'] as List;
  return const [];
}

Future<List<dynamic>> getClasses() async => _asList((await _dio.get('/classes/')).data);
```

---

## M-3. `Timer.periodic` каждые 2 секунды в офлайне, без реакции на сворачивание

**Файл:** `lib/screens/main_shell.dart:86–91`

```dart
void _startRecheck() {
  _recheckTimer?.cancel();
  _recheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
    Connectivity().checkConnectivity().then(_applyConnectivity);
  });
}
```

**Причина.** Нет ни экспоненциального отката, ни `WidgetsBindingObserver`.
`connectivity_plus` уже даёт поток `onConnectivityChanged` — поллинг избыточен.

**Последствие.** В офлайне таймер тикает бесконечно; каждый тик через
`_applyConnectivity` заводит ещё и `_offlineDebounce` на 3 секунды, который сразу
отменяется следующим тиком. Два таймера крутятся при свёрнутом приложении —
заметный расход батареи; iOS может пометить приложение как «Background Activity».

**Исправление:** убрать поллинг (поток достаточен) либо добавить откат и остановку в фоне:

```dart
class _MainShellState extends State<MainShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _recheckAttempt = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _recheckTimer?.cancel();
      _recheckTimer = null;
    } else if (state == AppLifecycleState.resumed && !_isOnline) {
      _startRecheck();
    }
  }

  void _startRecheck() {
    _recheckTimer?.cancel();
    final delay = Duration(seconds: (2 << _recheckAttempt).clamp(2, 60));
    _recheckTimer = Timer(delay, () async {
      _recheckAttempt++;
      final r = await Connectivity().checkConnectivity();
      _applyConnectivity(r);
      if (mounted && !_isOnline) _startRecheck();
    });
  }
```

не забыв `WidgetsBinding.instance.addObserver(this)` в `initState` и
`removeObserver` в `dispose`, а также сброс `_recheckAttempt = 0` при возврате онлайна.

---

## M-4. `resizeToAvoidBottomInset: false` — клавиатура перекрывает поле ввода ИИ

**Файлы:** `lib/screens/main_shell.dart:133`, `lib/screens/ai/widgets/ai_conversation_view.dart:352`

Шелл отключает подстройку под клавиатуру, а `_AiInputBar` — обычный `Container`
в конце `Column`. При открытии клавиатуры поле ввода уезжает под неё.

**Причина.** `resizeToAvoidBottomInset: false` нужен, чтобы плавающий нижний навбар
не прыгал, но он глобально отключает поведение для всех вкладок.

**Последствие.** Пользователь не видит, что печатает, в главном ИИ-чате и в классном.
Классическая претензия ревьюера («UI elements obscured»).

**Исправление.** Не отключать глобально, а компенсировать в самом навбаре:

```dart
// main_shell.dart — вернуть значение по умолчанию
return Scaffold(
  // resizeToAvoidBottomInset: false,   ← убрать
```

и скрывать навбар при поднятой клавиатуре:

```dart
final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
// ...
if (!keyboardUp) Positioned(left: 16, right: 16, bottom: 16, child: /* навбар */),
```

Проверить регрессии на всех вкладках (Классы, Настройки, Админ).

---

## M-5. Push: нет иконки уведомления для Android, пустой фоновый обработчик

**Файлы:** `android/app/src/main/AndroidManifest.xml`, `lib/services/push_service.dart:9–11`

Не задан `com.google.firebase.messaging.default_notification_icon` — Android 5+
рисует иконку приложения как силуэт, получается **белый квадрат** в статус-баре.

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
}
```

Фоновый обработчик пуст: data-only сообщения при убитом приложении не покажут ничего.

**Исправление.** Добавить монохромную иконку `android/app/src/main/res/drawable/ic_notification.png`
(белый глиф на прозрачном фоне) и в манифест:

```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_icon"
    android:resource="@drawable/ic_notification" />
<meta-data
    android:name="com.google.firebase.messaging.default_notification_color"
    android:resource="@color/notification_color" />
```

Если сервер шлёт только `notification`-payload, пустой обработчик допустим —
тогда добавить поясняющий комментарий. Если data-only — реализовать показ через
`flutter_local_notifications` внутри обработчика.

---

## M-6. `targetSdkVersion` не зафиксирован явно

**Файл:** `android/app/build.gradle.kts:41–43`

```kotlin
minSdk = flutter.minSdkVersion
targetSdk = flutter.targetSdkVersion
```

**Причина.** Значения берутся из установленной версии Flutter SDK.

**Последствие.** Google Play с 31 августа 2025 требует `targetSdk >= 35`. При сборке
на машине с более старым Flutter (или после отката версии SDK) получится AAB с
устаревшим target — отклонение при загрузке, причём воспроизводимость сборки
зависит от окружения разработчика.

**Исправление:**

```kotlin
minSdk = 24          // требование firebase_messaging 16.x
targetSdk = 35       // актуальное требование Play на дату релиза
compileSdk = 35
```

Проверить: `./gradlew :app:dependencies` и итоговый merged manifest в
`build/app/outputs/logs/manifest-merger-release-report.txt`.

---

## M-7. Release-сборка Android без minify и обфускации

**Файл:** `android/app/build.gradle.kts:57–68`

В блоке `release` нет `isMinifyEnabled` / `isShrinkResources` / ProGuard-правил.

**Последствие.** AAB заметно крупнее необходимого; Kotlin/Java-часть не обфусцирована.
Dart-код в release AOT-компилируется, но символы остаются читаемыми без `--obfuscate`.

**Исправление:**

```kotlin
release {
    isMinifyEnabled = true
    isShrinkResources = true
    proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro"
    )
    signingConfig = ...
}
```

`android/app/proguard-rules.pro`:

```proguard
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn io.flutter.embedding.**
```

Сборка с обфускацией Dart и сохранением символов для Crashlytics:

```bash
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_URL=https://api.chatra.kz
```

Символы из `build/symbols` загрузить в Crashlytics, иначе стек-трейсы будут нечитаемы.

---

## M-8. `INTERNET` объявлен только в debug-манифесте

**Файлы:** `android/app/src/main/AndroidManifest.xml`, `android/app/src/debug/AndroidManifest.xml`

`android.permission.INTERNET` присутствует только в debug-варианте (шаблон Flutter).
В release разрешение подтягивается транзитивно из манифестов Firebase — работает,
но зависит от набора зависимостей.

**Исправление.** Объявить явно в `main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

(второе нужно `connectivity_plus`).

---

## M-9. Ссылка на политику конфиденциальности отсутствует на экране регистрации

**Файл:** `lib/screens/auth/register_screen.dart:437–449`

Чекбокс согласия ведёт только на `TermsScreen`. `PrivacyPolicyScreen` доступен лишь
из Настроек — то есть **после** входа, тогда как согласие даётся до.

**Последствие.** Apple 5.1.1(i) и GDPR требуют доступности политики в момент сбора
данных. Частая причина отклонения.

**Исправление:**

```dart
Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
  GestureDetector(
    onTap: () => setState(() => _agreedTerms = !_agreedTerms),
    child: Text('${l.t('terms_agree')} ',
      style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500)),
  ),
  GestureDetector(
    onTap: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
    child: Text(l.t('tos_title'),
      style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w700)),
  ),
  const Text(' · ', style: TextStyle(fontSize: 13, color: C.text4)),
  GestureDetector(
    onTap: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
    child: Text(l.t('pp_title'),
      style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w700)),
  ),
])),
```

---

## M-10. Диалог загрузки файла может «залипнуть»

**Файл:** `lib/utils/file_opener.dart:44–54`

```dart
if (!await file.exists()) {
  await api.dio.download(cleanUrl, filePath, options: ...);
}
if (!context.mounted) return;    // ← ранний выход ДО закрытия диалога
closeDialog();
```

**Причина.** Проверка `context.mounted` стоит перед `closeDialog()`.

**Последствие.** Если экран закрыли во время скачивания, модальный
`showCupertinoDialog` со спиннером остаётся в стеке навигатора — пользователь видит
зависший индикатор без возможности его закрыть (`barrierDismissible: false`).

**Исправление.** Использовать `rootNavigator` и закрывать по сохранённой ссылке:

```dart
Future<void> openRemoteFile(BuildContext context, ApiService api, String url, String name) async {
  final cleanUrl = url.split('#').first;
  final nav = Navigator.of(context, rootNavigator: true);
  var dialogClosed = false;
  void closeDialog() {
    if (dialogClosed) return;
    dialogClosed = true;
    if (nav.canPop()) nav.pop();
  }

  showCupertinoDialog(context: context, barrierDismissible: false, builder: (_) => ...);

  try {
    ...
    closeDialog();                 // ← закрыть безусловно
    if (!context.mounted) return;  // ← только потом проверять context
    final result = await OpenFile.open(filePath);
    ...
  } on DioException catch (e) {
    closeDialog();
    if (!context.mounted) return;
    ...
  } catch (_) {
    closeDialog();
    if (!context.mounted) return;
    ...
  }
}
```

---

## M-11. `onGenerateRoute` при неизвестном маршруте возвращает `_AuthGate`

**Файл:** `lib/main.dart:182–188`

```dart
onGenerateRoute: (s) {
  switch (s.name) {
    case '/class': return MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: s.arguments as int));
    case '/archive': return MaterialPageRoute(builder: (_) => const ArchiveScreen());
    default: return MaterialPageRoute(builder: (_) => const _AuthGate());
  }
}
```

Две проблемы:
1. `s.arguments as int` — если push придёт с `class_id` в неожиданном формате, будет
   `_TypeError` при построении маршрута (`_routeByType` уже парсит через `int.tryParse`,
   но контракт хрупкий).
2. Неизвестный маршрут кладёт **второй экземпляр `_AuthGate`** поверх существующего —
   получается вложенный сплэш/шелл вместо ошибки. Отладить такое почти невозможно.

**Исправление:**

```dart
onGenerateRoute: (s) {
  switch (s.name) {
    case '/class':
      final id = s.arguments;
      if (id is! int) return null;
      return MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: id));
    case '/archive':
      return MaterialPageRoute(builder: (_) => const ArchiveScreen());
    default:
      return null;   // Flutter корректно отработает неизвестный маршрут
  }
},
```

---

## M-12. `NSLocalNetworkUsageDescription` описывает дев-сервер

**Файл:** `ios/Runner/Info.plist`

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>NSLocalNetworkUsageDescription</key>
<string>Доступ к локальной сети нужен для подключения к дев-серверу при разработке</string>
```

**Причина.** Дев-послабление осталось в релизном plist.

**Последствие.** Ревьюер видит системный запрос «Chatra хочет найти устройства в
локальной сети» с текстом про «дев-сервер при разработке» — прямой признак
неготовой сборки. Само послабление в релизе не нужно: продовый API идёт по HTTPS.

Хорошо: `NSAllowsArbitraryLoads` **отсутствует** — это правильно, ATS не ослаблен.

**Исправление.** Для релиза удалить оба ключа (или вынести в отдельный
`Info-Debug.plist` по конфигурации сборки).

---

## M-13. Хранение истории ИИ в `SharedPreferences` в открытом виде

**Файлы:** `lib/screens/ai/widgets/ai_conversation_view.dart:143–151`, `lib/screens/classes/tabs/class_ai_tab.dart`

Переписка с ИИ (учебные вопросы, тексты заданий, иногда персональные данные)
пишется в `SharedPreferences` без шифрования. На Android это `xml` в приватной
директории, на iOS — `plist`; на рутованном/джейлбрейкнутом устройстве и в
незашифрованном бэкапе читается как обычный текст.

Токены при этом хранятся правильно — `flutter_secure_storage` с
`encryptedSharedPreferences: true` и `KeychainAccessibility.first_unlock`.

**Исправление.** Либо отказаться от локального кэша (история всё равно синхронизируется
с сервером — см. `_syncFromServer`), либо исключить файл из бэкапов:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application android:fullBackupContent="@xml/backup_rules" ...>
```

```xml
<!-- res/xml/backup_rules.xml -->
<full-backup-content>
    <exclude domain="sharedpref" path="FlutterSharedPreferences.xml"/>
</full-backup-content>
```

Также очищать кэш истории при удалении аккаунта и при выходе.

---

## M-14. Ошибки провайдеров устанавливаются, но не всегда доходят до UI

**Файлы:** `lib/providers/classes_provider.dart:25–27`, `lib/providers/ai_chats_provider.dart:22–24`

```dart
void clearError() {
  errorMessage = null;      // ← без notifyListeners()
}
```

**Причина.** Сброс ошибки не уведомляет слушателей.

**Последствие.** После показа тоста ошибка остаётся в состоянии до следующего
`notifyListeners()` из другого источника — возможен повторный показ того же тоста
при неродственной перерисовке. Обратный эффект: `loadNotifBadge` (строка 224) пишет
`errorMessage = 'err_load_notifications'` для фоновой операции, о которой пользователю
знать не нужно, и это может всплыть тостом поверх экрана.

**Исправление:**

```dart
void clearError() {
  if (errorMessage == null) return;
  errorMessage = null;
  notifyListeners();
}
```

и не выставлять `errorMessage` для чисто фоновых задач (бейдж уведомлений) —
достаточно `logError`.

---

# LOW

## L-1. Тема по умолчанию не следует системной
`lib/providers/theme_provider.dart:5` — `ThemeMode.light` при первом запуске.
Пользователь с системной тёмной темой получает белую вспышку.
**Исправление:** при отсутствии сохранённого значения использовать `ThemeMode.system`.

## L-2. Отсутствуют `autofillHints` в полях авторизации
`login_screen.dart:107, 122`, `register_screen.dart:355, 369`, `forgot_password_screen.dart`.
Менеджеры паролей и автозаполнение iOS/Android не срабатывают.
**Исправление:** `autofillHints: const [AutofillHints.email]` / `[AutofillHints.password]`
/ `[AutofillHints.newPassword]`, обернуть форму в `AutofillGroup`, добавить
`textInputAction: TextInputAction.next/done`.

## L-3. Лишний запрос к `/admin/...` для студентов
`api_service.dart:348–356` — `getClassMembers` при ошибке основного эндпоинта всегда
пробует админский, который студенту вернёт 403. Лишний round-trip + шум в логах
и в Crashlytics. **Исправление:** пробовать fallback только при `isAdmin`.

## L-4. `void _send() async` вместо `Future<void>`
`ai_conversation_view.dart:226`, `class_ai_tab.dart:152`. Исключения из `async void`
не всплывают к вызывающему коду и попадают только в зону.
**Исправление:** сменить сигнатуру на `Future<void>` (для `onTap` подойдёт `() => _send()`).

## L-5. `parseServerDate(...)!` — force unwrap
`class_assignments_tab.dart:154`. Сейчас безопасно (фильтр выше уже отбросил
непарсящиеся даты), но связь неявная и легко ломается при рефакторинге.
**Исправление:** `final dl = parseServerDate(next['deadline']); if (dl == null) return const SizedBox.shrink();`

## L-6. `pf.path!` без проверки
`class_detail_screen.dart:587, 1278`, `assignment_detail_screen.dart:189` — в отличие
от строк 836/1038, где есть `where((pf) => pf.path != null)`.
**Исправление:** привести к единому фильтру во всех точках.

## L-7. Мутация состояния внутри `build()`
`main_shell.dart:130` — `if (_idx >= screens.length) _idx = 0;`. Работает, но нарушает
контракт `build` как чистой функции. **Исправление:** перенести коррекцию в
`didChangeDependencies` либо использовать локальную переменную
`final idx = _idx >= screens.length ? 0 : _idx;`.

## L-8. `Podfile.lock` в `.gitignore`
`.gitignore:57` — `ios/Podfile.lock` исключён. Версии CocoaPods не фиксируются,
сборки на разных машинах и в CI могут разъезжаться.
**Исправление:** удалить строку и закоммитить `Podfile.lock`.

## L-9. Устаревший `flutter_lints: ^3.0.1`
При Dart SDK `>=3.12.0`. Актуальные правила (в т.ч. усиленные проверки
`use_build_context_synchronously`, которые поймали бы H-10) не подключены.
**Исправление:** `flutter_lints: ^6.0.0`, затем `flutter analyze` и разбор новых предупреждений.

---

# Что осталось непроверенным

1. **Backend.** Вы указали, что доступ есть, но путь пока не назван. Не проверены:
   SQL-инъекции, авторизация на уровне эндпоинтов (IDOR: может ли студент запросить
   `/submissions/{чужой_id}`), rate limiting, валидация загрузок на сервере,
   срок жизни и ротация refresh-токенов, реальное удаление данных при
   `DELETE /auth/me`, утечка `dev_code` (см. C-1). **Дайте путь — доаудирую.**

2. **Статический анализ.** В песочнице нет Flutter SDK, `flutter analyze` и тесты
   не запускались. Прогоните локально:

```bash
flutter analyze
flutter test
flutter build apk --release --dart-define=API_URL=https://api.chatra.kz
```

3. **Прогон на устройствах.** Не выполнялся: медленная сеть (Network Link Conditioner),
   тесты на планшете, VoiceOver/TalkBack, тёмная тема на всех экранах,
   поведение при отзыве токена в фоне.

---

# Чек-лист перед подачей

**Блокеры (без них подавать нельзя)**

- [ ] C-1 — убрать автоподстановку `dev_code` (клиент + бэкенд)
- [ ] C-2 — capability Push Notifications в Xcode, непустой `Runner.entitlements`
- [ ] C-3 — жалобы + блокировка пользователей + очередь модерации
- [ ] C-4 — создать `key.properties`, собрать AAB релизным ключом
- [ ] C-5 — токен только на собственный хост, отдельный Dio для скачивания

**Обязательно до подачи**

- [ ] H-1 — безопасные инициалы (`initialsFrom`)
- [ ] H-2 — реализовать или удалить `_saveHistory()` в классном чате
- [ ] H-3 — снять кириллица-only валидацию, приложить демо-аккаунт
- [ ] H-4 — добавить 4 недостающих ключа локализации + тест
- [ ] H-5 — `android:label="Chatra"`
- [ ] H-6 — убрать `RECORD_AUDIO`, 4 неиспользуемые зависимости, аудио из манифеста приватности
- [ ] H-7 — лимиты на размер/тип/количество файлов, последовательная загрузка
- [ ] H-8 — окно контекста ИИ
- [ ] H-9 — `reset()` провайдеров при смене аккаунта
- [ ] H-10 — зафиксировать uid для ключа истории
- [ ] H-11 — привести манифест приватности и текст политики к реальности

**Метаданные сторов**

- [ ] App Store Connect: App Privacy = Email, Name, User ID, User Content, Photos —
      всё «App Functionality», Tracking = No
- [ ] App Store Connect: демо-аккаунт (student + teacher) в App Review Information
- [ ] App Store Connect: support URL и privacy policy URL — публичные и рабочие
- [ ] Возрастной рейтинг: указать наличие UGC и генеративного ИИ без фильтрации
- [ ] Play Console: Data Safety = те же категории + Crash logs, шифрование при передаче,
      «Пользователь может запросить удаление данных» = да
- [ ] Play Console: e-mail поддержки (Telegram как единственный канал недостаточен)
- [ ] Play Console: форма Advertising ID — не используется
- [ ] Сборка: `--obfuscate --split-debug-info`, символы загружены в Crashlytics

**Ручная проверка перед сдачей**

- [ ] Регистрация с латинским именем (John Smith) проходит до конца
- [ ] Выход → вход другим аккаунтом: чужих классов/тредов/бейджей на экране нет
- [ ] Авиарежим: все экраны показывают ошибку, ни один не падает и не зависает
- [ ] Push приходит на физический iPhone из TestFlight-сборки
- [ ] Клавиатура не перекрывает поле ввода ИИ
- [ ] Удаление аккаунта работает и выбрасывает на экран входа
- [ ] Все ссылки в Настройках открываются, ни одна кнопка не «пустая»

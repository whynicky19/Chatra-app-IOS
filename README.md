# Chatra — Education Platform

## Что было поправлено по сравнению с твоей версией

1. **`lib/main.dart`** — теперь baseUrl автоматически выбирается по платформе:
   - iOS-симулятор / macOS → `http://127.0.0.1:8000`
   - Android-эмулятор → `http://10.0.2.2:8000`
   - Реальное устройство → можно переопределить через `--dart-define=API_URL=http://192.168.x.x:8000`

2. **`ios/Runner/Info.plist`** — добавлены:
   - `NSAppTransportSecurity` с исключением для `localhost` и `127.0.0.1` (иначе iOS блокирует HTTP-запросы по умолчанию)
   - `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (нужны для `image_picker`)

3. **`ios/Podfile`** — восстановлены стандартные Flutter-хелперы (`flutter_ios_podfile_setup`, `flutter_install_all_ios_pods`). У тебя был сильно урезанный.

4. **Splash-экран** — переписан так, что текст «Chatra» и логотип видны **сразу** при запуске. В старой версии первые ~400мс всё было с `opacity: 0` на тёмном фоне `#0A1214` — это и могло выглядеть как «чёрный экран». Также добавлен `errorBuilder` на случай, если ассет логотипа не подгрузится.

5. **Почищены билд-артефакты** — удалены `build/`, `.dart_tool/`, `ios/Pods/`, `ios/Flutter/ephemeral/`, `ios/Flutter/Generated.xcconfig`, `GeneratedPluginRegistrant.*`. Они пересоздадутся при первом `flutter pub get`. У тебя в этих файлах были захардкожены пути `/Users/whynicky/...`, и если они стухли — это ломает сборку.

## Как запустить на iOS-симуляторе

```bash
cd chatra-app
flutter pub get
cd ios && pod install && cd ..
flutter run -d "iPhone"
```

Если поймаешь `PathExistsException` про `sqflite_darwin-2.4.2` (известный баг SPM):

```bash
rm -rf ios/Flutter/ephemeral ios/Pods ios/Podfile.lock .dart_tool build
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

## Если после всего этого экран всё ещё чёрный

Скинь мне:
- вывод `flutter doctor -v`
- логи из `flutter run` за первые ~10 секунд после запуска (там должны быть конкретные ошибки)
- скрин того, что видишь на симуляторе

Без логов вслепую угадывать дальше я не буду — слишком много возможных причин на стеке Flutter 3.44 + Xcode 26 + iOS 26.

## Бэкенд

Перед запуском приложения убедись, что бэк крутится на `127.0.0.1:8000` на том же маке:

```bash
curl http://127.0.0.1:8000/docs
```

Должна открыться swagger FastAPI.

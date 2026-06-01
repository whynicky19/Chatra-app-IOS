# Chatra Mobile App

Flutter-приложение для образовательной платформы



## Быстрый старт

### 1. Клонировать и установить зависимости

```bash
git clone https://github.com/whynicky19/chatra-app.git
cd chatra-app
flutter pub get
```

### 2. Указать URL бэкенда

В `lib/main.dart`:

```dart
final apiService = ApiService(baseUrl: 'http://YOUR_SERVER_IP:8000');
```

| Среда | URL |
|-------|-----|
| Android эмулятор | `http://10.0.2.2:8000` |
| iOS симулятор | `http://localhost:8000` |
| Реальное устройство (Wi-Fi) | `http://192.168.X.X:8000` |
| Продакшн | `https://your-domain.com` |


### 3. Запустить

```bash
flutter run
```


## Структура проекта

```
lib/
├── main.dart
├── theme/
│   └── app_theme.dart        # Цвета и тема
├── services/
│   └── api_service.dart      # HTTP-клиент
├── providers/
│   └── auth_provider.dart    # Состояние авторизации
└── screens/
    ├── main_shell.dart        # Bottom navigation
    ├── auth/                  # Вход / регистрация
    ├── home/                  # Каталог классов
    ├── classes/               # Детали класса + AI чат
    ├── chats/                 # Чаты
    ├── ai/                    # AI ассистент
    └── settings/              # Настройки
```



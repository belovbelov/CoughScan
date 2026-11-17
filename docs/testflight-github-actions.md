# Загрузка в TestFlight через GitHub Actions (без Xcode)

Workflow [`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) запускается на облачном Mac GitHub (образ `xcode-27`, Xcode 27.1, iOS 27 SDK). Он прогоняет регрессионные проверки, собирает архив, подписывает его и загружает сборку в App Store Connect. Xcode на своём компьютере для этого не нужен.

Настройка делается один раз и занимает около 30 минут. Дальше каждая сборка запускается одной кнопкой.

## 0. Что понадобится

- Платный аккаунт **Apple Developer Program**. Сертификат и профиль может создать роль Account Holder или Admin.
- Приложение в **App Store Connect** (My Apps → «+» → New App) с тем же Bundle ID, что и в профиле из шага 2.
- Права на **Settings** репозитория на GitHub (для секретов).
- Минуты GitHub Actions. В приватных репозиториях минуты macOS расходуются в 10 раз быстрее обычных, одна сборка идёт примерно 10–20 минут. Остаток лимита виден в Settings → Billing.

Команды ниже выполняются в Терминале из корня репозитория. Все ключи складываются в `~/CoughScan-signing`, вне репозитория.

## 1. Сертификат Apple Distribution

> Если на Mac, где раньше собирали приложение, уже есть сертификат Apple Distribution, его можно экспортировать из «Связки ключей» в `.p12` и пропустить этот шаг. Тогда на шаге 4 передайте путь к `.p12` третьим аргументом.

```bash
scripts/testflight-signing.sh csr
```

Затем на [developer.apple.com](https://developer.apple.com/account/resources/certificates/list): **Certificates → «+» → Apple Distribution → Continue**, загрузите `~/CoughScan-signing/distribution.csr` и скачайте `.cer`.

```bash
scripts/testflight-signing.sh p12 ~/Downloads/distribution.cer
```

У команды может быть не больше трёх сертификатов Apple Distribution. Если лимит исчерпан, отзовите ненужный: опубликованные приложения от этого не пострадают, но подпись на компьютерах, где этот сертификат используется, перестанет работать.

## 2. App ID и профиль App Store Connect

1. **Identifiers → «+» → App IDs → App**, тип Bundle ID — **Explicit**: `sunshine.CoughScan`. Если такой App ID уже есть, пропустите. Если он занят другой командой, возьмите свой, например `com.<вы>.coughscan`: workflow сам подставит Bundle ID из профиля.
2. **Profiles → «+» → Distribution → App Store Connect** → выберите App ID → отметьте сертификат из шага 1 → назовите профиль, например `CoughScan` → **Download**.

## 3. Ключ App Store Connect API

[App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) → **Users and Access → Integrations → App Store Connect API → Team Keys → «+»**:

- Name: `GitHub Actions`, Access: **App Manager** → Generate.
- Скачайте `AuthKey_XXXXXXXXXX.p8`. **Скачать его можно только один раз.**
- Скопируйте **Issuer ID** — он показан над таблицей ключей.

## 4. Секреты GitHub

```bash
scripts/testflight-signing.sh secrets ~/Downloads/CoughScan.mobileprovision ~/Downloads/AuthKey_XXXXXXXXXX.p8
```

Скрипт проверит, что профиль подходит для App Store, а сертификат из `.p12` входит в профиль. Затем он разложит значения по файлам в `~/CoughScan-signing/github-secrets`.

Добавьте секреты в **репозиторий → Settings → Secrets and variables → Actions → New repository secret**. Значение каждого берётся из одноимённого файла: например, `pbcopy < ~/CoughScan-signing/github-secrets/ASC_KEY_ID.txt` копирует его в буфер обмена.

| Секрет | Что это |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | сертификат с закрытым ключом |
| `IOS_DIST_CERT_PASSWORD` | пароль от `.p12` |
| `IOS_PROVISION_PROFILE_BASE64` | профиль App Store Connect |
| `ASC_KEY_ID` | Key ID ключа API |
| `ASC_KEY_P8_BASE64` | файл ключа API |
| `ASC_ISSUER_ID` | Issuer ID (вводится вручную, из шага 3) |

После этого папку `~/CoughScan-signing/github-secrets` можно удалить. Сам `~/CoughScan-signing` лучше сохранить в надёжном месте: он понадобится, когда через год придётся продлевать профиль.

## 5. Запуск сборки

Workflow должен оказаться на GitHub: отправьте ветку и слейте её в `main`.

- **Кнопкой:** вкладка **Actions → TestFlight → Run workflow**. Кнопка появляется, только когда файл workflow есть в ветке по умолчанию (`main`). В поле можно указать номер сборки; если оставить его пустым, номер будет равен 100 + номер запуска.
- **Тегом** (работает из любой ветки):

  ```bash
  git tag testflight-1.0-101
  ```

  ```bash
  git push origin testflight-1.0-101
  ```

Когда запуск завершится успешно, сборка через 10–30 минут появится в **App Store Connect → TestFlight**. При первой сборке App Store Connect может спросить про шифрование (Export Compliance). Внутренние тестировщики получают сборку сразу, внешним нужна проверка Beta App Review.

## Если что-то пошло не так

Логи `archive.log` и `export.log` прикрепляются к каждому запуску (страница запуска → Artifacts).

| Сообщение | Что сделать |
|---|---|
| `Не задан секрет …` | Добавьте секрет с точно таким именем (шаг 4). |
| `Профиль … привязан к устройствам` | Скачан профиль Development/Ad Hoc. Создайте профиль типа **App Store Connect**. |
| `doesn't include signing certificate` / `No profile … matching` | В профиле не отмечен сертификат из `.p12`. Отредактируйте профиль, скачайте его заново и повторите шаг 4. |
| `The bundle version must be higher …` | Запустите с бо́льшим номером сборки (поле в Run workflow). |
| `No suitable application records were found` | В App Store Connect нет приложения с этим Bundle ID — создайте его. |
| `Authentication failed` / `401` при загрузке | Проверьте `ASC_KEY_ID`, `ASC_ISSUER_ID` и что ключ API не отозван. |
| Задача долго стоит в очереди на `xcode-27` | Образ GitHub помечен как preview, очередь возможна. Подождите или посмотрите статус в [actions/runner-images](https://github.com/actions/runner-images). |
| Сертификат или профиль истёк | Профиль действует год. Создайте новый (шаг 2) и обновите `IOS_PROVISION_PROFILE_BASE64`. |

## Безопасность

- Файлы из `~/CoughScan-signing` нельзя коммитить и пересылать. На всякий случай `.gitignore` репозитория исключает `*.p12`, `*.p8`, `*.mobileprovision`, `*.cer`, `*.csr` и `*.key`.
- Секреты GitHub хранятся в зашифрованном виде и маскируются в логах. Workflow не запускается для pull request'ов, поэтому код из чужих форков секретов не получит.
- Если ключ мог утечь, отзовите ключ API в App Store Connect и сертификат на developer.apple.com, затем выпустите новые.

# Startup Studio Tycoon — Setup Guide for Windows

Руководство предполагает Windows 11, VS Code и Codex. Команды выполняются в PowerShell.

## 1. Стек

| Инструмент | Статус | Назначение |
|---|---|---|
| Roblox Studio | Обязательно | сцена, Play, publish, profiler |
| Git | Обязательно | история и rollback |
| GitHub | Желательно | remote repo и CI |
| Rokit | Обязательно | версии Roblox tooling |
| Rojo | Обязательно | файловый проект и live sync |
| StyLua | Обязательно | форматирование |
| Selene | Обязательно | lint |
| Luau Language Server | Обязательно | типы и диагностика |
| Wally | По необходимости | Luau packages |
| Roblox Studio MCP | Очень желательно | доступ Codex к Studio |
| GitHub Actions | Желательно | проверки |
| Test runner | Желательно | unit/integration |

## 2. Roblox Studio

1. Скачать Studio с официального Roblox Creator.
2. Установить и войти.
3. Создать тестовый Baseplate.
4. Открыть Explorer, Properties и Output.
5. Проверить Play.

Создать отдельный test experience для DataStore/monetization. Не тестировать случайно на production.

## 3. Git

```powershell
winget install --id Git.Git -e --source winget
git --version
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
git config --global init.defaultBranch main
```

## 4. GitHub

1. Создать приватный `StartupStudioTycoon`.
2. Локально:

```powershell
git init
git add .
git commit -m "chore: initialize project documentation"
git remote add origin <URL>
git push -u origin main
```

Включить branch protection, required status checks и запрет force-push в `main`.

## 5. Rokit

1. Скачать актуальный Windows binary/installer из официального репозитория Rokit.
2. Добавить executable в PATH.
3. Перезапустить терминал.

```powershell
rokit --version
rokit init
```

Если команда не найдена: проверить PATH, открыть новый терминал, проверить блокировку Defender.

## 6. Tooling через Rokit

```powershell
rokit add rojo-rbx/rojo
rokit add JohnnyMorganz/StyLua
rokit add Kampfkarren/selene
rokit add UpliftGames/wally
rokit install
```

Проверка:

```powershell
rojo --version
stylua --version
selene --version
wally --version
```

Если имя пакета изменилось, найти актуальное в официальной документации Rokit и зафиксировать версию в `rokit.toml`.

## 7. Rojo Studio plugin

```powershell
rojo plugin install
rojo serve
```

Перезапустить Studio, открыть Rojo plugin и подключиться к localhost.

Ошибки:

- version mismatch — обновить CLI/plugin;
- connection refused — проверить server, port и firewall;
- wrong tree — проверить `default.project.json`.

## 8. Проект

```powershell
mkdir StartupStudioTycoon
cd StartupStudioTycoon
rojo init
rojo build -o build/StartupStudioTycoon.rbxl
```

Открыть `.rbxl` в Studio.

## 9. VS Code extensions

Установить:

- Codex;
- Rojo;
- Luau Language Server;
- Selene;
- GitLens — опционально;
- Error Lens — опционально;
- EditorConfig — опционально.

Sourcemap:

```powershell
rojo sourcemap default.project.json --output sourcemap.json
rojo sourcemap default.project.json --output sourcemap.json --watch
```

## 10. StyLua

`stylua.toml`:

```toml
column_width = 120
line_endings = "Windows"
indent_type = "Tabs"
indent_width = 4
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
collapse_simple_statement = "Never"
```

Команды:

```powershell
stylua src tests
stylua --check src tests
```

## 11. Selene

`selene.toml`:

```toml
std = "roblox"
```

```powershell
selene src tests
```

Не отключать правило только ради зелёного CI.

## 12. Wally

Не создавать пустой manifest только ради наличия файла. `wally.toml`, lockfile и package tree добавляются вместе с первой реально необходимой, обоснованной и проверенной зависимостью. Для Stage 1 достаточно закрепить и проверить Wally через Rokit.

```powershell
wally init
wally install
```

Использовать только нужные зависимости, фиксировать версии и просматривать исходный код.

## 13. Roblox Studio MCP

Если функция доступна:

1. обновить Studio;
2. открыть Assistant/MCP settings;
3. включить MCP server;
4. выбрать quick connect для Codex CLI или скопировать конфигурацию;
5. проверить connected servers в Codex;
6. попросить прочитать структуру тестового DataModel.

Если MCP недоступен, использовать Rojo и ручные проверки.

## 14. Тесты

Минимум тестировать:

- calculators;
- migrations;
- config validation;
- idempotency;
- quest progress.

Команда тестов фиксируется в `AGENTS.md`.

## 15. GitHub Actions

Workflow должен:

1. checkout;
2. установить Rokit;
3. `rokit install`;
4. format check;
5. Selene;
6. tests;
7. `rojo build`.

Production publish на первом релизе выполнять вручную после QA.

## 16. Studio plugins

Обязательно: Rojo.

Желательно: Luau Language Server Companion, если нужен LSP. Остальные плагины устанавливать только от доверенных авторов.

## 17. Проверка окружения

```powershell
git --version
rokit --version
rojo --version
stylua --version
selene --version
wally --version
rojo build -o build/StartupStudioTycoon.rbxl
stylua --check src tests
selene src tests
pwsh -NoProfile -File scripts/Test-Stage1.ps1
pwsh -NoProfile -File scripts/Test-Stage2.ps1
rojo build test.project.json -o build/StartupStudioTycoonStage2Tests.rbxl
```

Затем `rojo serve`, подключение Studio и Play. Runtime-тесты из `test.project.json` требуют отдельного ручного запуска Studio и не выполняются GitHub Actions на `ubuntu-latest`.

```powershell
git add .
git commit -m "chore: configure Roblox development toolchain"
git tag toolchain-ready
git push
git push --tags
```

## 18. Aftman

Aftman часто встречается в старых проектах. Для нового проекта выбрать один version manager. Не смешивать Aftman и Rokit без необходимости.

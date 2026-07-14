# Startup Studio Tycoon — комплект разработки через Codex

Этот комплект предназначен для поэтапной разработки production-ready Roblox-игры **Startup Studio Tycoon** через Codex, Roblox Studio и Rojo.

## Состав комплекта

1. `01_GAME_DESIGN.md` — продуктовая концепция и состав launch-ready v1.
2. `02_ROADMAP.md` — порядок разработки и зависимости между этапами.
3. `03_DEVELOPMENT_GUIDE.md` — архитектура, правила кода, безопасность, сохранения, UI, экономика и тестирование.
4. `04_STAGE_CHECKLIST.md` — критерии приёмки после каждого этапа.
5. `05_MANUAL_QA_GUIDE.md` — ручная проверка результатов Codex в Roblox Studio.
6. `06_SETUP_GUIDE.md` — установка и настройка необходимого ПО.
7. `07_CODEX_WORKFLOW.md` — работа с Codex, `AGENTS.md`, skills, MCP и контекстом.
8. `08_DEVELOPMENT_PROCESS.md` — ежедневный процесс разработки, Git workflow и выпуск релиза.
9. `09_PROMPT_FOR_CODEX.md` — основной промпт, который запускает разработку.
10. `AGENTS.md` — постоянные правила репозитория для Codex.
11. `PROMPTS.md` — короткие рабочие промпты на типовые задачи.
12. `.agents/skills/*/SKILL.md` — проектные skills для Codex.
13. `10_SOURCES_AND_REFERENCES.md` — основные ссылки из исходного исследования.

## Порядок использования

1. Установить инструменты по `06_SETUP_GUIDE.md`.
2. Создать пустой Git-репозиторий.
3. Скопировать этот комплект в корень репозитория.
4. Открыть репозиторий в VS Code/Codex.
5. Проверить `AGENTS.md`.
6. Перед каждым этапом читать соответствующий раздел `02_ROADMAP.md`.
7. Передавать Codex мастер-промпт из `09_PROMPT_FOR_CODEX.md`.
8. Для реализации этапа вызывать `$phase-implementer`.
9. После реализации запускать `$luau-strict-review` и `$studio-sync-and-verify`.
10. Проверять этап по `04_STAGE_CHECKLIST.md` и `05_MANUAL_QA_GUIDE.md`.
11. Коммитить только полностью принятый этап.
12. Не переходить дальше при blocker/critical дефектах.

## Главное правило

Codex не получает задачу «сделай всю игру целиком». Он работает как инженер по одному этапу, с фиксированным scope, критериями готовности, автоматическими проверками и ручной приёмкой в Studio.

## Ожидаемая структура репозитория

```text
StartupStudioTycoon/
├─ .agents/
│  └─ skills/
├─ .github/
│  └─ workflows/
├─ docs/
├─ src/
│  ├─ ReplicatedStorage/
│  ├─ ServerScriptService/
│  ├─ ServerStorage/
│  ├─ StarterPlayer/
│  ├─ StarterGui/
│  └─ Workspace/
├─ tests/
├─ AGENTS.md
├─ default.project.json
├─ rokit.toml
├─ wally.toml
├─ selene.toml
├─ stylua.toml
└─ README.md
```

## Definition of Done проекта

Launch-ready v1 считается готовой только когда:

- основной цикл работает от первого входа до престижа;
- сохранения устойчивы к выходу, повторному входу и миграции;
- экономика не имеет soft-lock, runaway inflation и очевидных exploit-циклов;
- покупки обрабатываются сервером и идемпотентны;
- интерфейс работает на ПК, мобильных устройствах и геймпаде;
- onboarding приводит нового игрока к первому релизу;
- состояния игроков изолированы между plot-ами;
- сервер не доверяет значениям клиента;
- нет blocker/critical ошибок в консоли;
- выполнены performance-профилирование и длительный тест;
- готовы аналитика, LiveOps-конфиги, версионирование и rollback-план.

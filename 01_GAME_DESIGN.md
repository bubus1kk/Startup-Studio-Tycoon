# Startup Studio Tycoon — Game Design Specification

## 1. Позиционирование

**Жанр:** Simulation → Tycoon с idle/incremental-прогрессией, менеджментом команды, социальным showroom-слоем и LiveOps.

**Фантазия игрока:** начать с гаражного стартапа и вырастить международную software-компанию с несколькими продуктами, офисами, сотрудниками, инвесторами и престижем.

**Ключевое отличие от обычного dropper-tycoon:** деньги создаются не конвейером, а системой разработки продуктов. Состав команды, качество, баги, маркетинг, технический долг и рыночный спрос влияют на результат релиза.

## 2. Core loop

1. Игрок выбирает идею продукта.
2. Назначает сотрудников и рабочие места.
3. Команда производит очки разработки, дизайна, QA и маркетинга.
4. Игрок принимает промежуточные решения: ускорить релиз, исправить баги, повысить качество, провести кампанию.
5. Продукт выпускается.
6. Сервер рассчитывает рейтинг, аудиторию и доход.
7. Доход инвестируется в офис, найм, оборудование, исследования и новые категории.
8. Портфель продуктов создаёт пассивный доход.
9. Игрок открывает новый офисный tier.
10. После достижения цели выполняет prestige/rebrand и получает постоянные бонусы.

## 3. Первый сеанс

Цель onboarding — первый завершённый релиз за 5–8 минут.

Первые действия:

- получить свободный plot;
- поставить стартовый стол;
- нанять первого Developer;
- выбрать `Simple Mobile App`;
- дождаться короткой разработки;
- выполнить QA-шаг;
- выпустить приложение;
- получить первый доход;
- купить второе рабочее место;
- открыть экран целей.

Использовать короткие цели, подсветку объектов, контекстные подсказки и progress bar. Не заставлять читать длинные инструкции.

## 4. Ресурсы

### Cash

Источники:

- доход активных продуктов;
- награды за релизы;
- квесты;
- достижения;
- офлайн-доход;
- кооперативные контракты.

Расходы:

- комнаты;
- мебель и оборудование;
- зарплаты;
- найм;
- маркетинг;
- исследования;
- обслуживание;
- устранение технического долга.

### Gems

Источники:

- ограниченные бесплатные награды;
- достижения;
- события;
- Developer Products.

Расходы:

- косметические темы;
- reroll кандидатов;
- convenience-ускорители;
- дополнительные preset-слоты;
- эффекты релиза.

### Reputation

Получается за качественные релизы, достижения и сезонные цели. Открывает сложные продукты, инвесторов, офисные районы и prestige.

## 5. Сотрудники

| Роль | Основной вклад | Вторичный вклад |
|---|---|---|
| Developer | скорость разработки | качество и технический долг |
| Designer | UX и market fit | hype |
| QA Engineer | снижение багов | retention |
| Product Manager | координация | уменьшение штрафа большой команды |
| Marketer | launch hype | привлечение аудитории |

Характеристики:

- уровень;
- редкость;
- продуктивность;
- зарплата;
- morale;
- специализация;
- traits;
- fatigue;
- assigned desk;
- assigned product.

Статы должны быть понятны из карточки сотрудника.

## 6. Продукты

Категории v1:

1. Mobile App.
2. SaaS Tool.
3. Game Prototype.
4. Productivity Suite.
5. AI Assistant.

Параметры:

- scope;
- progress;
- quality;
- bugs;
- UX;
- market fit;
- hype;
- technical debt;
- retention;
- revenue per minute;
- lifecycle stage.

Жизненный цикл:

`Idea → Planning → Development → QA → Marketing → Release → Growth → Maintenance → Sunset`

## 7. Результат релиза

Формула хранится в конфиге и тестируется отдельно.

```text
ReleaseScore =
  QualityWeight * quality
+ UXWeight * ux
+ MarketFitWeight * marketFit
+ HypeWeight * hype
- BugPenalty * bugs
- DebtPenalty * technicalDebt
```

Требования:

- diminishing returns;
- узкий диапазон случайности;
- clamp значений;
- понятная расшифровка результата;
- серверный расчёт;
- отсутствие отрицательного дохода.

## 8. Офисы

Tiers:

1. Garage.
2. Small Loft.
3. Downtown Office.
4. Tech Campus.
5. Global HQ.

Комнаты:

- Development Room;
- Design Studio;
- QA Lab;
- Marketing Room;
- Meeting Room;
- Server Room;
- Recreation Area;
- Executive Office;
- Research Lab.

Каждый tier меняет площадь, число сотрудников, комнаты, очереди, автоматизацию и визуальный статус.

## 9. Исследования

Ветки:

- Engineering;
- Design;
- Quality;
- Marketing;
- Operations;
- Automation.

Примеры:

- Better Workstations;
- CI Pipeline;
- Automated Tests;
- Cloud Infrastructure;
- Analytics Suite;
- Better Recruitment;
- Remote Work;
- Release Automation.

## 10. Автоматизация

Late-game системы:

- автоматический найм в рамках бюджета;
- назначение сотрудников;
- исправление части багов;
- продление маркетинга;
- auto-release preset;
- auto-maintenance.

Автоматизация имеет лимиты и не отменяет решения игрока.

## 11. Prestige

Название: **Rebrand / New Venture**.

Условия:

- заданная valuation;
- нужный office tier;
- минимальная Reputation;
- успешный продукт высокого класса.

Сбрасываются Cash, обычные улучшения, большинство сотрудников и продукты. Сохраняются Gems, cosmetics, achievements, founder perks, часть исследований и сезонные награды.

Prestige-валюта: **Founder Points**.

## 12. Multiplayer

Launch-ready v1:

- отдельный plot;
- посещение офисов;
- likes/reactions;
- leaderboard;
- совместный контракт 2–4 игроков;
- party bonus без передачи валюты.

Запрещены:

- прямая передача Cash/Gems;
- изменение чужого plot;
- клиентский ownership;
- shared mutable state без серверного владельца.

## 13. Daily и LiveOps

Daily:

- выпустить продукт категории;
- нанять сотрудника;
- исправить баги;
- заработать Cash;
- посетить офис.

Events:

- Hackathon;
- AI Boom;
- Cybersecurity Week;
- Holiday App Rush;
- Game Jam;
- Market Crash.

События конфигурируются без переписывания core-кода.

## 14. Монетизация

### Game Passes

- VIP Founder;
- Extra Automation Slot;
- Office Theme Pack.

### Developer Products

- Small Gems Pack;
- Large Gems Pack;
- Funding Boost;
- Productivity Rush;
- Event Bundle.

### Subscription

`Studio+`:

- ежедневная небольшая награда;
- косметическая ротация;
- дополнительный preset;
- badge;
- небольшой convenience bonus.

Правила честности:

- free progression должна оставаться полной;
- первый prestige доступен без покупки;
- цены загружаются динамически;
- grants выполняются сервером;
- receipt-обработка идемпотентна;
- premium boosts не ломают leaderboard.

## 15. Analytics

События:

- onboarding_started;
- onboarding_step_completed;
- first_employee_hired;
- first_product_started;
- first_release;
- office_tier_unlocked;
- prestige_started;
- prestige_completed;
- purchase_prompted;
- purchase_completed;
- session_end_summary.

Ключевые воронки:

- вход → первый сотрудник;
- первый сотрудник → первый релиз;
- первый релиз → второй сеанс;
- второй сеанс → новый офис;
- новый офис → prestige.

## 16. Launch-ready v1

Обязательно:

- пять office tiers;
- пять ролей;
- пять категорий продуктов;
- полный core loop;
- portfolio;
- prestige;
- save/load;
- offline income;
- tutorial;
- desktop/mobile/gamepad UI;
- multiplayer plots;
- social visits;
- daily/weekly quests;
- конфигурируемое событие;
- Developer Products;
- Game Passes;
- subscription integration;
- analytics hooks;
- anti-exploit validation;
- performance pass;
- release checklist.

После релиза:

- alliances;
- cosmetic trading;
- новые города;
- инвесторы;
- пользовательские логотипы;
- расширенный рынок сотрудников.

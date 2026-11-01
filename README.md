# Z-City × WoundSystem (Casualties: Unknown Health System Beta)

Здесь лежат два аддона, связанные мостом `hg.WoundBridge`:

| Папка | Что это |
|---|---|
| `z_city/` | Z-City (gamemode-аддон) + мост `lua/homigrad/woundbridge/` |
| `casualties_unknown_health_system_beta/` | WoundSystem с небольшими правками под мост |

Исходные архивы (`archive (1).zip` = Z-City, `archive.zip` = WoundSystem) остались в корне без изменений.
Оба аддона нужно положить в `garrysmod/addons/`. Мост включается сам, когда установлен WoundSystem.

## Что делает мост

WoundSystem становится **единственной системой здоровья**, а Z-City оставляет себе то, что здоровьем не является:
броню и пробитие, физику рэгдолла (`hg.Fake` / `hg.FakeUp`), оружие, инерцию движения.

* **Урон.** Фронтенд Z-City (`homigrad-damage`: броня, пробитие, перенаправление урона с игрока на его рэгдолл, кровь/силы
  удара, хуки `PreHomigradDamage`) работает как раньше, но готовый урон передаётся в `WoundSystem.Health.HandleDamage`.
  Движковый урон блокируется, смерть наступает только через WoundSystem. Урон по рэгдоллу при падении/ударе об объекты
  (`velocityDamage`) тоже идёт в WoundSystem (`zcity_wounds_collision_scale`, по умолчанию 0.6).
* **Рэгдолл.** Собственный рэгдолл WoundSystem отключён: потеря сознания и «падение» создают Z-City fake-рэгдолл
  (`WB.CreateRagdoll`), вставание — `hg.FakeUp` (`WB.RestoreRagdoll`). Повторный `Spawn()` из `FakeUp` больше не запускает
  хуки респавна WoundSystem (раньше именно из-за двух механизмов рэгдолла игрок «баговал» при уроне).
  Оторванные конечности отображаются и на fake-рэгдолле, и на трупе.
* **`ply.organism` — «тень».** Сотни файлов Z-City читают `org.*`, поэтому таблица остаётся, но каждый тик перезаписывается
  из WoundSystem (`WB.Sync`): кровь, пульс, боль, сознание, шок, ампутации, выносливость, множитель скорости и т. д.
  Легаси-симуляция органов (кровотечения, лёгкие, печень, пульс…) для живых игроков не выполняется. Для трупов и NPC
  всё работает по-старому.
* **Движение.** `sh_inertia.lua` использует один множитель `org.wsmovemult`, посчитанный WoundSystem (кровь, боль, ноги,
  стамина…); вес, температура, переноска предметов остаются от Z-City.
* **Медицина.** SWEP'ы категории «ZCity Medicine» применяют предметы WoundSystem (`WB.SwepHeal` → `Health.ApplyItemToBody`):
  бинты → `GAUZE`/`STERILIZEDBANDAGE`, жгут → `TOURNIQUET`, игла → `INJECTION` (дренаж груди), морфин/фентанил/налоксон/
  обезболивающие → `MORPHINE`/`FENTANYL`/`NALOXONE`, адреналин/бета-блокатор/маннитол/тиамин → прямые эффекты на
  состояние тела, аптечка (5 режимов), пакет крови (переливание в обе стороны) → объём крови WoundSystem.
  Для NPC, трупов и непривязанных SWEP остаётся легаси-код.
* **Осмотр тела.** В круговом селекторе Z-City всегда есть кнопка **Examine Body** — открывает окно ран WoundSystem
  (то же, что клавиша T / `woundsys_open_panel`), независимо от того, получал ли игрок урон. Круговое меню больше не
  подменяется «болевым» режимом.

## Настройки (консоль)

| ConVar | По умолчанию | |
|---|---|---|
| `zc_woundsystem_bridge` | 1 | 1 — здоровье у WoundSystem, 0 — старый organism Z-City |
| `zc_wound_damage_scale` | 1 | множитель урона, передаваемого в WoundSystem |
| `zcity_wounds_collision_scale` | 0.6 | то же для урона рэгдолла при столкновениях |
| `zc_woundsystem_bridge_debug` | 0 | отладочный вывод моста |
| `zc_woundsystem_minigames` | 1 | 1 — лечебные свепы запускают мини-игру WoundSystem, эффект только после прохождения; 0 — мгновенное применение |

## Мини-игры при применении свепов

- Бинты → мини-игра бинтования; морфин/фентанил/налоксон → шприц; игла, adrenaline, betablock, mannitol, thiamine и режимы аптечки 2/3/5 → шприц (часть через носитель `SALINE`). Жгут, таблетки, пакет крови, режим аптечки 4 — мгновенно.
- Реализовано через временный виртуальный слот 6 инвентаря WS и «отложенные» (`deferred`) сессии: во время игры эффект не применяется, копится прогресс. Эффект и расход идут по ходу работы: бинт тратится на столько, на сколько им обмотали (его может не хватить на всё кровотечение, остаток сохраняется); шприц — доза = введённая часть (недовведённый остаётся с остатком). Исключение — игла (дренаж грудной клетки): только при полном введении.
- Если ничего не сделано / смерть / поломка иглы — эффект не применяется, свеп не тратится (сообщение «Not completed - nothing was applied»).
- Пока мини-игра открыта: курсор мыши включён (даже без открытого HUD WoundSystem), ходьба/прыжок/стрельба/смена оружия заблокированы (клиент и сервер, `StartCommand`); после закрытия ЛКМ нужно отпустить, иначе свеп не запустится снова.
- API: `WoundSystem.Health.StartExternalMinigame(ply, {kind, itemId, limbId, amount, onClose})`, `WoundSystem.Health.HasExternalMinigame(ply)`.
- Не проверено в реальной игре (только синтаксис и заглушечный тест).

## Что вырезано из WoundSystem

- **Инвентарь:** панель слотов, drag&drop, world-items (`item_healthvial` и т. п.), спавнер предметов, перемещение/использование из слотов, стартовые предметы. Остался только скрытый «слот 6» — рука для мини-игр свепов Z-City.
- **Не-медицинские модули:** чат/голос (talker chat, chat distance, voice proximity, self-talk HUD), happiness, HEV automedic, healthchargers, self-harm, skills, weather compat. Удалены файлы и записи в `sh_health_init.lua` и в меню опций.
- Лекарства — только свепы Z-City (`hg.WoundBridge.SwepHeal`). Снятый жгут возвращается свепом `weapon_tourniquet`.
- Мини-игры шрапнели/вывиха/дефибриллятора из панели тела требовали предметы инвентаря и без него недоступны.

## Мини-игры: полный экран

- Мини-игры (бинт/шприц и остальные) занимают весь экран: тёмный фон, без рамки-обрезки, без подсказок и названий. Остаётся только значок предмета и процент остатка.
- ConVar'ы: `woundsys_minigame_fullscreen` (1; 0 — старый вид с рамкой), `woundsys_minigame_fullscreen_alpha` (235).
- Расход и эффект идут по ходу работы: каждый оборот бинта / каждый нажим на поршень сразу применяет свою часть эффекта к цели и убавляет ту же часть у предмета Z-City (`modeValues`). Исключения (применяются при закрытии, пропорционально введённой дозе): игла-дренаж (нужно полное введение) и «носимые» предметы через `SALINE` (коагулянт).

## Reset organism (C-меню → игрок)

`properties` → «Reset organism» и консольная `hg_organism_clear` теперь вызывают `hg.WoundBridge.ResetOrganism(ent)`: новое тело и конечности WoundSystem (`WoundSystem.Health.ResetPlayer`), очистка легаси-хуков `Org Clear` (наручники, яды…), подъём из рэгдолла. Без моста — прежний `hg.organism.Clear`.

## Известные ограничения (не проверено в игре)

* Всё писалось без запуска Garry's Mod: синтаксис и логика моста проверены только на заглушках. Баланс урона и ощущения
  (`zc_wound_damage_scale`, `zcity_wounds_collision_scale`) надо подстроить на сервере.
* Яды, газ и радиация Z-City, еда/питьё, стамина Z-City, «ярость» (`fury13`/`fury16`) и `bigconsumable`/`smallconsumable`/
  `pluviska` по-прежнему работают на теневом organism и на WoundSystem не влияют (эти SWEP'ы не привязаны).
* Экран смерти WoundSystem может накладываться на экран смерти Z-City.
* Типы крови Z-City в WoundSystem не моделируются (переливание всегда «совместимо»).
* Отключение `zc_woundsystem_bridge 0` возвращает легаси-путь Z-City, но WoundSystem при этом продолжит свою работу,
  если его не удалить.

## Список изменений

WoundSystem: `server/sv_health.lua` (экспорты `Health.*`, `ApplyItemToBody`, мост-гейты, рэгдолл через мост),
`sv_happiness.lua`, `sv_hev_automedic.lua`, `client/cl_health_gui.lua`, `client/cl_sound_manager.lua`.

Z-City: `homigrad/woundbridge/*`, `organism/tier_1/sv_input.lua`, `sv_organism.lua`, `cl_main.lua`,
`movement/sh_inertia.lua`, `cl_hud.lua`, `cl_screeneffects.lua`, `weapons/weapon_{adrenaline,bandage_sh,betablock,
bigbandage_sh,bloodbag,fentanyl,mannitol,medkit_sh,morphine,naloxone,needle,painkillers,thiamine,tourniquet}.lua`.

## Вывихи (Z-City структура поверх C:U)

- Флаги Z-City `org.llegdislocation / rlegdislocation / larmdislocation / rarmdislocation` теперь считаются из конечностей WoundSystem (`limb.dislocated` у `thigh/crus/foot` и `arm/forearm/hand`, левая и правая сторона). Вывих рождается в WS (удары, падения) и сам заживает по таймеру WS.
- Радиальные пункты «Fix dislocation» (себе и другим) работают как в Z-City и вызывают `hg_fixdislocation`. Команда в мосте (`WB.FixDislocation`) использует прежнюю формулу шанса (боль фиксера, чужая конечность, `tries`, доктор, присед/рагдолл), а анальгезия берётся из опиатов WS. Успех вправляет все вывихнутые суставы стороны через `SetLimbDislocated(…, false)` и добавляет боль в сустав; неудача — `tries+1`, больше боли, шанс 1/5 ещё сильнее навредить.
- Штраф движения ×0.75 на каждую вывихнутую ногу и боль при беге остаются (боль уходит в WS-боль конечности); руки блокируют хват в fake-рагдолле, как в Z-City.
- Челюсть (`jawdislocation`) не поддерживается: в WS её нет.

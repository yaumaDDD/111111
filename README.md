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
- Реализовано через временный виртуальный слот 6 инвентаря WS и «отложенные» (`deferred`) сессии: во время игры эффект не применяется, копится прогресс. Критерий прохождения: бинт — ≥1 полный оборот или почти весь расход; шприц — ≥90% дозы.
- При провале/отмене эффект не применяется, свеп не тратится (сообщение «Not completed - nothing was applied»).
- API: `WoundSystem.Health.StartExternalMinigame(ply, {kind, itemId, limbId, amount, onClose})`, `WoundSystem.Health.HasExternalMinigame(ply)`.
- Не проверено в реальной игре (только синтаксис и заглушечный тест).

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

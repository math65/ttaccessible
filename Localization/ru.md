# Russian glossary

Catalogue: `App/ttaccessible/ru.lproj/Localizable.strings`. Reviewer: Georgy Aliabyev,
who is writing this glossary. The decisions below were approved with the catalogue in
pull request #51.

## Conventions

- History and journal announcements use masculine verb forms: «вошёл», «вышел», not «вошёл(ла)».
- A channel join or leave inserts the channel name directly, without «канал» before it:
  «Руслан вошёл в Штаб.»
- Quotes: «» guillemets.
- Ellipsis: `…` (one character). Dash: — (em dash).
- No abbreviations that speech synthesis reads letter by letter. Latin acronyms that are
  usual in spoken Russian (AEC, IP) stay as they are.
- The interface addresses the user as «вы», lower case inside a sentence. Actions are
  imperatives in the plural: «Выберите», «Нажмите», «Откройте».
- A full sentence ends with a full stop; a button title or a menu item does not.
- Where the sentence can avoid naming a gender, it does: «Выйти», not «Вышел».
- Mac key names stay Latin and are read by VoiceOver as they are: `Return`, `Delete`,
  `Command-N`. A key named in Russian («Ввод», «Удалить») is a second name for the same
  key, and the reader stops to work out whether it is one.
- Latin stays Latin: `Command-N`, `tt://`, BearWare, VoiceOver, file names and keys.

## Terms

- Channel — канал — the conference room, not a communication channel. Compound names
  agree with «канал»: «Сообщение в канал», «дерево каналов и пользователей».
- Root channel — Корень — the fallback channel name, kept short for speech; the
  auto-join preference says «корневой канал».
- User — пользователь.
- Server — сервер.
- Session — сеанс — not «сессия».
- Transmission — передача — the permission to send: «Управление передачей»,
  «Разрешить передачу голоса», «передача экрана».
- Media file stream — трансляция медиафайла — what plays at the listener's end.
  «Передача» is the permission to send; the two senses are not one word.
- Shared desktop — экран — «Разрешить передачу экрана», not «рабочий стол».
- Hotkey — горячая клавиша — «Горячие клавиши» in hints, not «шорткат».
- Auto — Авто — as the value of a picker, one word, the same one the input preset already
  uses (`preferences.audio.advanced.preset.auto`). «Автоматически» is the adverb for a
  sentence: «Автоматически входить в корневой канал».
- Input gain — громкость микрофона. Output gain — общая громкость вывода.
- Copy, with no object — Копировать — a menu item or a command on its own.
- Copy, with an object — Скопировать — «Скопировать ссылку», «Скопировать сообщение».
- Clipboard — буфер обмена.
- Leave, sign out — Выйти — «Выйти из канала», «Выйти» from an account. Not «Покинуть»,
  with one exception, and the reason is grammar, not style: where the channel name is
  inserted into the sentence, the two history strings say «%@ покинул %@.» and «Вы покинули
  %@.». The name then follows in the accusative, which for an inanimate word is the same as
  the nominative — «покинул Штаб», «покинули Штаб и Комнату» — so no channel name ever has
  to be declined. «Вышел из» would ask for the genitive, «из Штаба», «из Новой комнаты», and
  a template cannot produce that ending for a name it does not know. Sentences with no name
  in them keep the verb: «Пользователь вышел из канала», «%@ вышел с сервера».
- Accessibility label — not a translated term; the text says «озвучивается как».
- VoiceOver — VoiceOver — Latin, not declined.

## Open items

None. Both earlier items are settled: `savedServers.table.help` now says Return, in English
and in every catalogue, and the two «рабочий стол» lines became «экран» in #53.

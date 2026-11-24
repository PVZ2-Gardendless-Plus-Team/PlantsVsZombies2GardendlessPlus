# Translating

The game ships in English and Simplified Chinese, the two languages PVZGE
has. Players pick one under **Settings > Language**; "Automatic" follows the
operating system and falls back to English.

## How it works

English text is the translation key. The `I18n` autoload
(`core/i18n/i18n.gd`) builds one Godot `Translation` per language at startup
from two sources, later winning:

1. `data/native/i18n/pvzge_lyrics.json` - PVZGE's own UI text (its
   `InGameLyrics` asset), a tree of `{"en": ..., "zh": ...}` pairs. Every pair
   becomes an English -> Chinese message. Regenerate it with
   `python3 tools/extract_translations.py <import dir> <config.json>`.
2. `data/native/i18n/<locale>.json` - the port's own strings, and overrides:

```json
{
 "name": "简体中文",
 "pvzge": "zh",
 "strings": {"Sun: %d": "阳光：%d"},
 "contexts": {"world map": {"Play": "开始"}}
}
```

`name` is shown in the language picker, in its own language. `pvzge` names
the column of the lyrics tree this language reads, if any.

## Marking strings in new UI

1. **A plain English literal needs nothing.** `MenuUI.label("Choose Your
   Seeds!")`, `button.text = "BACK"`, tooltips and dialog text all translate
   themselves, and re-translate live when the language changes.
2. **Use PVZGE's exact English** where the same text exists in
   `pvzge_lyrics.json` (match case and punctuation). It is then translated
   already.
3. **Formatted text: translate the template, then format.**
   `tr("Sun: %d") % n`, never `tr("Sun: %d" % n)`. Code that builds text like
   this should set it again on `NOTIFICATION_TRANSLATION_CHANGED`, or the
   screen should be rebuilt, so a language switch reaches it. In a `static
   func` use `TranslationServer.translate("...")`.
4. **Data names** (worlds, levels, campaigns) are English text too: show
   them through `tr(name)`.
5. **Ambiguous short words** can take a context, `tr("Play", "world map")`,
   with the translation under `contexts` in the locale file.
6. **Text that must not translate** (a player name, a language's own name):
   set `auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED` on the
   Control.

Strings stored PVZGE-style as `{"en": ..., "zh": ...}` in data are read with
`I18n.pick(value)`, which also passes plain strings through. PVZGE text by its
lyrics path: `I18n.lyric("GamePaused/Title")`, the same as PVZGE's
`MultiLanguage.getStringByProps("GamePaused", "Title")`. `I18n.language()` is
PVZGE's key for the current language (`"en"`, `"zh"`).

## Adding translations

Run `python3 tools/check_translations.py` to list every marked string still
missing a translation, with its file and line, and any translation whose
`%` placeholders differ from the English. Godot's `%` formats by position,
so a translation must keep the placeholders in the English order.

New screens are usually added by several people at once, so leave
`zh_CN.json` alone while building one and fill in its strings afterwards.

## Adding a language

Drop `<locale>.json` (for example `fr.json`) into `data/native/i18n/` or into
a mod's `i18n/` folder with a `name` and `strings`. It appears in the picker
at once. A mod's file is layered over the base game's, so a pack can also fix
or extend an existing language.

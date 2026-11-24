extends Node
## Languages: loads every translation, picks one, and reads PVZGE's text.
##
## English is the source language and English text is the translation key,
## so a Label or Button whose text is a plain English literal translates
## itself (and re-translates when the language changes). Code that builds
## text calls `tr("Sun: %d") % n`. See docs/TRANSLATING.md.
##
## Where translations come from, later winning over earlier:
## - `i18n/pvzge_lyrics.json`: PVZGE's InGameLyrics tree of {"en", "zh", ...}
##   pairs. Every pair becomes an English -> other-language message for each
##   locale file that names that column with "pvzge".
## - `i18n/<locale>.json` in the base game, then in each enabled mod in load
##   order: {"name": "简体中文", "pvzge": "zh", "strings": {"English": "..."},
##   "contexts": {"world map": {"Play": "..."}}}. A mod adds a language just by
##   shipping a new locale file.
##
## Registered as an autoload singleton named `I18n`, before `Settings`, which
## sets the language through `set_language`.

## Emitted after the language changes, once every Control has re-translated.
signal language_changed(locale: String)

const DIR := "i18n"
const LYRICS_FILE := "pvzge_lyrics.json"
const SOURCE_LOCALE := "en"
const SOURCE_NAME := "English"
## The Settings value that means "follow the operating system".
const AUTO := ""

var _translations: Dictionary = {}   ## locale -> Translation
var _names: Dictionary = {}          ## locale -> its name, in that language
var _pvzge_keys: Dictionary = {}     ## locale -> its column in the lyrics tree
var _lyrics: Dictionary = {}
var _errors: Array[String] = []


func _ready() -> void:
	reload()


## Reads every translation again, e.g. after the mod list changes.
func reload() -> void:
	for t in _translations.values():
		TranslationServer.remove_translation(t)
	_translations.clear()
	_names = {SOURCE_LOCALE: SOURCE_NAME}
	_pvzge_keys = {SOURCE_LOCALE: "en"}
	_lyrics = {}
	_errors.clear()

	var roots: Array[String] = []
	for source in Mods.data_sources():
		roots.append(String(source["root"]).path_join(DIR))
	# Locale files first, so the lyrics know which columns are wanted; then
	# the lyrics underneath and the files on top, in source order.
	var files: Array[Dictionary] = []
	for root in roots:
		var lyrics = _read_json(root.path_join(LYRICS_FILE))
		if lyrics is Dictionary:
			_lyrics.merge(lyrics, true)
		for path in _locale_files(root):
			var spec = _read_json(path)
			if not spec is Dictionary:
				continue
			var locale := TranslationServer.standardize_locale(path.get_file().get_basename())
			spec["locale"] = locale
			files.append(spec)
			if spec.has("name"):
				_names[locale] = str(spec["name"])
			if spec.has("pvzge"):
				_pvzge_keys[locale] = str(spec["pvzge"])
	for locale in _pvzge_keys:
		if locale != SOURCE_LOCALE:
			_add_lyrics(locale, _lyrics, _pvzge_keys[locale])
	for spec in files:
		_add_file(spec)
	for t in _translations.values():
		TranslationServer.add_translation(t)


## Locales a player can pick, English first, then by locale code.
func languages() -> PackedStringArray:
	var out := PackedStringArray([SOURCE_LOCALE])
	var rest := _names.keys().filter(func(l: String) -> bool: return l != SOURCE_LOCALE)
	rest.sort()
	out.append_array(rest)
	return out


## A language's own name for itself ("简体中文"), for the language picker.
func language_name(locale: String) -> String:
	if locale == AUTO:
		return "%s (%s)" % [tr("Automatic"), language_name(resolve(AUTO))]
	return str(_names.get(locale, TranslationServer.get_locale_name(locale)))


## The locale a Settings value means: AUTO follows the operating system,
## falling back to English when it asks for a language we lack.
func resolve(setting: String) -> String:
	if setting != AUTO and _names.has(setting):
		return setting
	var wanted := OS.get_locale() if setting == AUTO else setting
	var best := SOURCE_LOCALE
	var best_score := 0
	for locale in _names:
		var score := TranslationServer.compare_locales(wanted, locale)
		if score > best_score:
			best_score = score
			best = locale
	return best


func set_language(setting: String) -> void:
	var locale := resolve(setting)
	if locale == TranslationServer.get_locale():
		return
	TranslationServer.set_locale(locale)
	language_changed.emit(locale)


## The current locale ("en", "zh_CN").
func locale() -> String:
	return TranslationServer.get_locale()


## The current language as PVZGE names it ("en", "zh"): the key to read from
## its {"en": ..., "zh": ...} strings.
func language() -> String:
	return str(_pvzge_keys.get(locale(), locale().get_slice("_", 0)))


## Picks the current language out of a PVZGE-style {"en": ..., "zh": ...}
## string, falling back to English. Anything else is returned as text, so a
## field can hold either a plain string or a per-language one.
func pick(value: Variant) -> String:
	if value is Dictionary:
		for key in [language(), locale(), SOURCE_LOCALE]:
			if value.has(key) and str(value[key]) != "":
				return str(value[key])
		return ""
	return "" if value == null else str(value)


## PVZGE's text at a path into InGameLyrics, in the current language:
## lyric("GamePaused/Title") is what PVZGE's
## MultiLanguage.getStringByProps("GamePaused", "Title") shows. "" when the
## path does not lead to a string.
func lyric(path: String) -> String:
	var node: Variant = _lyrics
	for part in path.split("/", false):
		if not node is Dictionary or not node.has(part):
			return ""
		node = node[part]
	return pick(node) if node is Dictionary and node.has(SOURCE_LOCALE) else ""


func errors() -> Array[String]:
	return _errors


func summary() -> String:
	return "i18n: %d languages (%s), now %s" % [_names.size(),
			", ".join(languages()), locale()]


func _translation(locale: String) -> Translation:
	if not _translations.has(locale):
		var t := Translation.new()
		t.locale = locale
		_translations[locale] = t
	return _translations[locale]


## Every {"en": ..., <key>: ...} pair under `node`. The first pair to claim an
## English text wins: PVZGE repeats a few words ("Play") with different
## Chinese, and a locale file's `contexts` can tell them apart.
func _add_lyrics(locale: String, node: Variant, key: String) -> void:
	if node is Dictionary:
		if node.has(SOURCE_LOCALE) and node[SOURCE_LOCALE] is String:
			var en: String = node[SOURCE_LOCALE]
			var text := str(node.get(key, ""))
			var t := _translation(locale)
			if en != "" and text != "" and t.get_message(en) == &"":
				t.add_message(en, text)
			return
		for child in node.values():
			_add_lyrics(locale, child, key)
	elif node is Array:
		for child in node:
			_add_lyrics(locale, child, key)


func _add_file(spec: Dictionary) -> void:
	var t := _translation(spec["locale"])
	var strings = spec.get("strings", {})
	if strings is Dictionary:
		for en in strings:
			t.add_message(en, str(strings[en]))
	var contexts = spec.get("contexts", {})
	if contexts is Dictionary:
		for context in contexts:
			var group = contexts[context]
			if group is Dictionary:
				for en in group:
					t.add_message(en, str(group[en]), context)


func _locale_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json" and f != LYRICS_FILE:
			out.append(dir_path.path_join(f))
	out.sort()
	return out


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		_errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

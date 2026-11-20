"""@package locjson.validate
Checks the translation CSVs of a language against the English strings.

Errors (the build stops): unreadable CSVs, duplicate keys, broken or
missing control codes and placeholders, unknown grammar tokens, unbalanced
format tags, characters the font can't draw, words too wide for their box,
invalid status/gender/sound values, and two different translations of text
the engine can't tell apart.

Warnings: untranslated or stale rows, unknown or missing keys, English columns
out of date, text that
needs more lines than its box has (or than the English needs), names wider
than any English name of the same kind, whitespace and format code changes.
"""

import os
import re
from collections import Counter, defaultdict

from . import codes
from .csvio import OBSOLETE, STALE, STATUSES, CsvError, read_csv
from .fonts import load_metrics

## Sound values allowed in the "sound" column.
SOUNDS = {"", "vowel", "consonant", "special"}
## Tokens in ribbon/mark titles that the engine replaces (see GameData::Ribbon#title).
_TITLE_TOKEN_RE = re.compile(r"/(?:Owner|Player|Variable_\d+)/")


class Problem:
    """One problem in a CSV."""

    def __init__(self, path, line, key, message, warning=False):
        ## CSV path, relative to the locales folder ("de/items.csv").
        self.path = path
        ## Line number (0 if not about one line).
        self.line = line
        ## Row key ("" if not about one row).
        self.key = key
        ## What is wrong.
        self.message = message
        ## True for a warning.
        self.warning = warning

    def __str__(self):
        where = self.path + (":%d" % self.line if self.line else "")
        if self.key:
            where += " (%s)" % self.key
        return "%s: %s" % (where, self.message)


def article_names(lang):
    """Article operations a language's grammar tokens can use (lower case)."""
    return {name.lower() for name in lang.articles}


class Checker:
    """Validates one language."""

    def __init__(self, config, lang, fonts_dir):
        ## locales.json.
        self.config = config
        ## The Language.
        self.lang = lang
        ## Folder of the fonts.
        self.fonts_dir = fonts_dir
        ## Problems found.
        self.problems = []
        box = config.message_box
        ## Metrics of the message window font.
        self.box_metrics = load_metrics(fonts_dir, box["font"], box["size"])
        nf = config.name_font
        ## Metrics of the font names are drawn in.
        self.name_metrics = load_metrics(fonts_dir, nf["font"], nf["size"])
        self._field_metrics = {}
        ## CSV -> number of untranslated rows.
        self.untranslated = {}
        self._articles = article_names(lang)

    def error(self, path, line, key, message):
        self.problems.append(Problem(path, line, key, message))

    def warning(self, path, line, key, message):
        self.problems.append(Problem(path, line, key, message, warning=True))

    def field_metrics(self, box):
        k = (box["font"], box["size"])
        if k not in self._field_metrics:
            self._field_metrics[k] = load_metrics(self.fonts_dir, box["font"], box["size"])
        return self._field_metrics[k]

    #---------------------------------------------------------------------------
    # One translation
    #---------------------------------------------------------------------------
    def check_codes(self, path, line, key, english, text, placeholders_ok=True):
        """Compares the codes, tags and placeholders of a translation with the English."""
        src = codes.tokenize(english)
        dst = codes.tokenize(text)
        for t in dst:
            if t.kind == codes.BAD:
                self.error(path, line, key, "%s: %s" % (t.arg, t.raw))
        for strict, report in ((codes.REQUIRED, self.error), (codes.FORMAT, self.warning)):
            a = Counter(t.signature() for t in src if t.kind in (codes.CODE, codes.TAG) and t.strict == strict)
            b = Counter(t.signature() for t in dst if t.kind in (codes.CODE, codes.TAG) and t.strict == strict)
            if a != b:
                missing = sorted((a - b).elements())
                extra = sorted((b - a).elements())
                parts = []
                if missing:
                    parts.append("missing " + " ".join(missing))
                if extra:
                    parts.append("extra " + " ".join(extra))
                what = "control codes" if strict == codes.REQUIRED else "format codes"
                report(path, line, key, "%s differ from the English: %s" % (what, "; ".join(parts)))
        # Title tokens (ribbon/mark titles: /Owner/, /Player/, /Variable_N/)
        a = Counter(_TITLE_TOKEN_RE.findall(english))
        b = Counter(_TITLE_TOKEN_RE.findall(text))
        if a != b:
            parts = []
            if a - b:
                parts.append("missing " + " ".join(sorted((a - b).elements())))
            if b - a:
                parts.append("extra " + " ".join(sorted((b - a).elements())))
            self.error(path, line, key, "title tokens differ from the English: %s" % "; ".join(parts))
        # Placeholders
        src_ph = {}
        for t in src:
            if t.kind == codes.PLACEHOLDER:
                src_ph.setdefault(t.name, set()).add(t.arg)
        used = set()
        for t in dst:
            if t.kind == codes.PLACEHOLDER:
                used.add(t.name)
                if t.name not in src_ph:
                    self.error(path, line, key, "%s: the English has no {%s}" % (t.raw, t.name))
                elif t.arg not in src_ph[t.name]:
                    fmt = sorted(x or "" for x in src_ph[t.name])
                    self.error(path, line, key, "%s: the English formats {%s} as %s" % (
                        t.raw, t.name, " or ".join(("{%s:%s}" % (t.name, f)) if f else "{%s}" % t.name
                                                   for f in fmt)))
            elif t.kind == codes.GRAMMAR:
                if t.name != "pg":
                    used.add(t.name)
                    if t.name not in src_ph:
                        self.error(path, line, key, "%s: the English has no {%s}" % (t.raw, t.name))
                self.check_grammar_token(path, line, key, t)
        for n in sorted(set(src_ph) - used):
            self.warning(path, line, key, "{%s} from the English isn't used" % n)
        # Tags
        stack = []
        for t in dst:
            if t.kind == codes.TAG and t.name in codes.PAIRED_TAGS:
                if not t.closing:
                    stack.append(t.name)
                elif t.name in stack:
                    del stack[len(stack) - 1 - stack[::-1].index(t.name)]
                else:
                    self.error(path, line, key, "</%s> closes a tag that isn't open" % t.name)
        src_closed = {t.name for t in src if t.kind == codes.TAG and t.closing}
        for name in stack:
            if name in src_closed:
                self.error(path, line, key, "<%s> is never closed" % name)

    def check_grammar_token(self, path, line, key, t):
        if t.name == "pg":
            if len(t.options) != 2:
                self.error(path, line, key, "%s needs two choices: {pg:male|female}" % t.raw)
        elif t.arg == "plural":
            if len(t.options) < 2:
                self.error(path, line, key, "%s needs at least two choices: {%s|plural:one|other}" % (t.raw, t.name))
        elif t.arg == "g":
            if len(t.options) < 2:
                self.error(path, line, key, "%s needs a choice per gender: {%s|g:%s}" % (
                    t.raw, t.name, "|".join(self.lang.genders)))
        else:
            if t.arg.lower() not in self._articles:
                self.error(path, line, key, "%s: %s has no article \"%s\" (see locales.json; known: %s)" % (
                    t.raw, self.lang.name, t.arg, ", ".join(sorted(self._articles)) or "none"))

    def check_glyphs(self, path, line, key, text, metrics):
        missing = sorted({c for c in text if not metrics.has_glyph(c)})
        if missing:
            self.error(path, line, key, "the font %s can't draw %s" % (
                os.path.basename(metrics.font.path), " ".join(repr(c) for c in missing)))

    def layout(self, text, box, metrics):
        shown = codes.displayed_text(text, self.config.samples)
        width = box["width"]
        if box.get("mode") == "chunks":
            return codes.chunk_lines(shown, metrics, width)
        return codes.message_lines(shown, metrics, width)

    def check_size(self, path, line, key, s, text, name_widths):
        """Checks a translation fits where it's shown."""
        if s.message:
            box = self.config.message_box
            for seg_src, seg_dst in _pairs(_split_m(s.english), _split_m(text)):
                lines, overflow = self.layout(seg_dst, box, self.box_metrics)
                for word in overflow:
                    self.error(path, line, key, "\"%s\" is wider than the message box (%d px)" % (word, box["width"]))
                src_lines = self.layout(seg_src, box, self.box_metrics)[0] if seg_src is not None else 0
                limit = box["lines"]
                for t in codes.tokenize(seg_dst):
                    if t.kind == codes.CODE and t.name == "l" and (t.arg or "").isdigit():
                        limit = int(t.arg)
                if lines > limit and lines > src_lines:
                    self.warning(path, line, key, "needs %d lines; the box shows %d (the English needs %d)" % (
                        lines, limit, src_lines))
            return
        if not s.field:
            return
        box = self.config.fields.get(s.field)
        if box:
            metrics = self.field_metrics(box)
            lines, overflow = self.layout(text, box, metrics)
            for word in overflow:
                self.error(path, line, key, "\"%s\" is wider than the text box (%d px, %s)" % (
                    word, box["width"], box.get("where", s.field)))
            if lines > box["lines"]:
                self.warning(path, line, key, "needs %d lines; only %d fit in the %s, the rest is cut off" % (
                    lines, box["lines"], box.get("where", s.field)))
            return
        limit = name_widths.get(s.field)
        if limit:
            shown = codes.displayed_text(text, self.config.samples)
            w = max(self.name_metrics.width(part) for part in shown.split("\n"))
            if w > limit:
                self.warning(path, line, key, "%d px wide; the widest English %s is %d px, so it may not fit" % (
                    w, s.field.split(".")[-1].replace("_", " "), limit))

    #---------------------------------------------------------------------------
    # One file
    #---------------------------------------------------------------------------
    def check_file(self, path, rel, strings, name_widths, compiled):
        """Checks one CSV. Adds the rows to compile to compiled (list of (SourceString, Row))."""
        expected = {s.key: s for s in strings}
        try:
            columns, rows = read_csv(path)
        except CsvError as e:
            self.error(rel, e.line or 0, "", str(e.args[0]))
            return
        seen = {}
        untranslated = 0
        no_gender = 0
        has_grammar_cols = "gender" in columns
        for row in rows:
            key = row.get_value("key").strip()
            line = row.line
            if not key:
                self.error(rel, line, "", "row without a key")
                continue
            if key in seen:
                self.error(rel, line, key, "duplicate key (also on line %d)" % seen[key])
                continue
            seen[key] = line
            status = row.get_value("status").strip().lower()
            if status not in STATUSES:
                self.error(rel, line, key, "unknown status \"%s\" (use stale, obsolete or leave it empty)" % status)
            s = expected.get(key)
            if s is None:
                if status != OBSOLETE:
                    self.warning(rel, line, key, "this key isn't in the game (any more); it is ignored. Run "
                                                 "`make update-locales` to mark it obsolete")
                continue
            if status == OBSOLETE:
                self.warning(rel, line, key, "marked obsolete but the key exists; run `make update-locales`")
            if row.get_value("english") != s.english:
                self.warning(rel, line, key, "the English column is out of date; run `make update-locales`")
            gender = row.get_value("gender").strip().lower()
            sound = row.get_value("sound").strip().lower()
            if gender and gender not in self.lang.genders:
                self.error(rel, line, key, "gender \"%s\" isn't one of %s" % (gender, "/".join(self.lang.genders)))
            if sound not in SOUNDS:
                self.error(rel, line, key, "sound \"%s\" isn't vowel, consonant or special" % sound)
            text = row.get_value("translation")
            if text == "":
                untranslated += 1
                continue
            if status == STALE:
                self.warning(rel, line, key, "stale: the English changed since this was translated "
                                             "(update it, then clear the status)")
            if text.strip() != text and s.english.strip() == s.english:
                self.warning(rel, line, key, "the translation starts or ends with spaces")
            if s.noun and s.number == "sg" and has_grammar_cols and not gender and self._articles:
                no_gender += 1
            self.check_codes(rel, line, key, s.english, text)
            self.check_glyphs(rel, line, key, codes.displayed_text(text, {}), self.box_metrics)
            self.check_size(rel, line, key, s, text, name_widths)
            compiled.append((s, row))
        missing_rows = [k for k in expected if k not in seen]
        if missing_rows:
            self.warning(rel, 0, "", "%d keys of the game have no row (e.g. %s); run `make update-locales`" % (
                len(missing_rows), missing_rows[0]))
        if untranslated:
            self.untranslated[rel] = untranslated
        if no_gender:
            self.warning(rel, 0, "", "%d translated nouns have no gender (%s is assumed for articles)" % (
                no_gender, self.lang.default_gender))


def _split_m(text):
    """Splits phone text at \\m, which starts a new message."""
    return text.replace("\\M", "\\m").split("\\m") if text is not None else [None]


def _pairs(a, b):
    for i, seg in enumerate(b):
        yield (a[i] if i < len(a) else None), seg


def name_width_limits(strings, config, fonts_dir):
    """Widest English text of each single-line name field. @return field -> px"""
    nf = config.name_font
    metrics = load_metrics(fonts_dir, nf["font"], nf["size"])
    ret = defaultdict(int)
    for s in strings:
        if s.field and s.field not in config.fields and not s.message:
            shown = codes.displayed_text(s.english, config.samples)
            w = max(metrics.width(p) for p in shown.split("\n"))
            ret[s.field] = max(ret[s.field], w)
    return dict(ret)


def check_conflicts(checker, compiled):
    """Two rows the engine looks up by the same English text must agree."""
    seen = {}
    for s, row in compiled:
        k = s.runtime_key
        text = row.get_value("translation")
        if k in seen:
            other_s, other_text = seen[k]
            if other_text != text:
                where = "%s (%s)" % (other_s.file, other_s.key)
                checker.error(os.path.join(checker.lang.code, s.file).replace(os.sep, "/"), row.line, s.key,
                              "same English as %s but translated differently; the game looks text up by its "
                              "English, so only one translation can be used. Make the English different or use "
                              "the same translation" % where)
        else:
            seen[k] = (s, text)


def validate_language(config, lang, strings, locales_dir, fonts_dir, name_widths=None):
    """Checks every CSV of a language.

    @return (problems, compiled) where compiled is the list of (SourceString, Row)
            of translated rows
    """
    checker = Checker(config, lang, fonts_dir)
    if name_widths is None:
        name_widths = name_width_limits(strings, config, fonts_dir)
    by_file = defaultdict(list)
    for s in strings:
        by_file[s.file].append(s)
    lang_dir = os.path.join(locales_dir, lang.code)
    compiled = []
    present = set()
    if os.path.isdir(lang_dir):
        for folder, subdirs, files in os.walk(lang_dir):
            subdirs[:] = sorted(d for d in subdirs if d != "graphics")
            for name in sorted(files):
                if not name.lower().endswith(".csv"):
                    continue
                path = os.path.join(folder, name)
                rel_file = os.path.relpath(path, lang_dir).replace(os.sep, "/")
                present.add(rel_file)
                rel = "%s/%s" % (lang.code, rel_file)
                if rel_file not in by_file:
                    checker.warning(rel, 0, "", "no game text belongs in this file; it is ignored")
                    continue
                checker.check_file(path, rel, by_file[rel_file], name_widths, compiled)
    for f in sorted(by_file):
        if f not in present:
            checker.warning("%s/%s" % (lang.code, f), 0, "", "file missing (%d strings); run `make update-locales`"
                            % len(by_file[f]))
    check_conflicts(checker, compiled)
    if checker.untranslated:
        total = sum(checker.untranslated.values())
        worst = sorted(checker.untranslated.items(), key=lambda kv: -kv[1])[:3]
        checker.warning(lang.code, 0, "", "%d rows in %d files aren't translated yet; English is shown for them "
                        "(most in %s)" % (total, len(checker.untranslated),
                                          ", ".join("%s: %d" % (f.split("/", 1)[1], n) for f, n in worst)))
    return checker.problems, compiled

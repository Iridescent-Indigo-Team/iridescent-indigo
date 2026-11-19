"""@package locjson.codes
Tokenizes game text into plain text, message control codes, format tags,
{n} placeholders and grammar tokens, and turns text into what the message
window measures.

Control codes are the ones pbMessageDisplay (011_Messages.rb) understands,
plus the phone codes (\\TN, \\TP, \\TE, \\m; 004_Item_Phone.rb). Format tags
are FORMATREGEXP in 010_DrawText.rb. Grammar tokens are handled by
003a_Intl_Grammar.rb at runtime:
- {1|def}, {1|Def}, {1|indef.acc}, {1|de.def}: noun with an article
- {1|plural:one|other}: chosen by the number in argument 1
- {1|g:masculine|feminine|neuter}: chosen by the gender of noun argument 1
- {pg:male|female}: chosen by the player's gender
"""

import re

#===============================================================================
# Token kinds
#===============================================================================
## Plain text.
TEXT = "text"
## A backslash control code (\\PN, \\v[1], ...).
CODE = "code"
## A <tag> or </tag>.
TAG = "tag"
## A {n} or {n:fmt} placeholder.
PLACEHOLDER = "placeholder"
## A grammar token ({n|...} or {pg:...}).
GRAMMAR = "grammar"
## Something that looks like a code but isn't one.
BAD = "bad"

## How strictly a code must match between the English and a translation.
## free: may be added, moved or dropped (line breaks, pauses).
FREE = "free"
## format: colours and styles; a different count is a warning.
FORMAT = "format"
## required: content and flow (names, variables, sounds, windows); a different
## count is an error.
REQUIRED = "required"

## Codes with a [argument]: name -> strictness.
_ARG_CODES = {
    "wtnp": REQUIRED, "wt": FREE, "ts": FORMAT, "cl": REQUIRED, "me": REQUIRED, "se": REQUIRED,
    "ch": REQUIRED, "ff": REQUIRED, "f": REQUIRED, "w": FORMAT, "l": FORMAT, "v": REQUIRED,
    "c": FORMAT, "n": REQUIRED, "sign": REQUIRED,
}
## Codes without an argument: name -> strictness.
_PLAIN_CODES = {
    "pog": FORMAT, "pg": FORMAT, "pn": REQUIRED, "pm": REQUIRED, "pt": REQUIRED, "cn": REQUIRED,
    "cl": REQUIRED, "wd": REQUIRED, "wm": REQUIRED, "wu": REQUIRED, "op": REQUIRED,
    "tn": REQUIRED, "tp": REQUIRED, "te": REQUIRED, "g": REQUIRED, "b": FORMAT, "r": FORMAT,
    "n": FREE, "m": REQUIRED, "1": FREE, ".": FREE, "|": FREE, "!": FREE, "^": REQUIRED,
}

_CODE_RE = re.compile(
    r"\\\\"                                                      # escaped backslash
    r"|\\(sign)\[([^\]]*)\]"
    r"|\\(wtnp|wt|ts|cl|me|se|ch|ff|f|w|l|v|c)\[([^\]]*)\]"
    r"|\\(n)\[([1-8])\]"
    r"|\\\[([0-9a-f]{8})\]"
    r"|\\(pog|pg|pn|pm|pt|cn|cl|wd|wm|wu|op|tn|tp|te|g|b|r|n|m|1|\.|\||!|\^)",
    re.I)
_TAG_RE = re.compile(
    r"<(/?)(c|c2|c3|o|fn|br|fs|i|b|r|pg|pog|u|s|icon|img|ac|ar|al|outln|outln2)(\s*=\s*([^>]*))?>",
    re.I)
## Tags that must be closed by a matching </tag> to be well formed.
PAIRED_TAGS = {"c", "c2", "c3", "o", "fn", "fs", "i", "b", "u", "s", "outln", "outln2"}
## Tags that are content rather than style.
REQUIRED_TAGS = {"icon", "img"}
## Tags that are just line breaks.
FREE_TAGS = {"br"}
_BRACE_RE = re.compile(r"\{(\d+|pg)([|:])([^{}]*)\}|\{(\d+)\}")
## Article/case operation of a grammar token: [prefix.]def|indef[.case]
_ARTICLE_OP_RE = re.compile(r"^[A-Za-z]+(\.[A-Za-z]+)*$")


class Token:
    """One piece of a tokenized string."""

    def __init__(self, kind, raw, name="", arg=None, strict=FREE, closing=False, options=None):
        ## TEXT, CODE, TAG, PLACEHOLDER, GRAMMAR or BAD.
        self.kind = kind
        ## The text the token was read from.
        self.raw = raw
        ## Code/tag name (lower case), placeholder number, or grammar head.
        self.name = name
        ## Code argument, tag value, sprintf format or grammar operation.
        self.arg = arg
        ## FREE, FORMAT or REQUIRED.
        self.strict = strict
        ## True for a closing tag.
        self.closing = closing
        ## Grammar token choices (list of str) or None.
        self.options = options

    def signature(self):
        """What must match between English and translation for this token."""
        if self.kind == CODE and self.name == "ch":
            parts = (self.arg or "").split(",")
            return "\\ch[%s,...%d options]" % (",".join(parts[:2]), max(len(parts) - 2, 0))
        if self.kind == CODE:
            return ("\\%s[%s]" % (self.name, self.arg)) if self.arg is not None else "\\" + self.name
        if self.kind == TAG:
            return "<%s%s%s>" % ("/" if self.closing else "", self.name,
                                 "=" + self.arg.strip() if self.arg else "")
        return self.raw

    def __repr__(self):
        return "Token(%s, %r)" % (self.kind, self.raw)


def _scan_brace(text, pos, out):
    """Reads a {...} token at text[pos]. @return the position after it."""
    m = _BRACE_RE.match(text, pos)
    if not m:
        end = text.find("}", pos)
        if end < 0 or "{" in text[pos + 1:end]:
            out.append(Token(TEXT, "{"))
            return pos + 1
        raw = text[pos:end + 1]
        if re.match(r"\{\s*(\d+|pg)\s*[|:}]", raw):
            out.append(Token(BAD, raw, arg="malformed placeholder or grammar token"))
        else:
            out.append(Token(TEXT, raw))
        return end + 1
    raw = m.group(0)
    if m.group(4) is not None:
        out.append(Token(PLACEHOLDER, raw, name=m.group(4), strict=REQUIRED))
        return m.end()
    head, sep, body = m.group(1), m.group(2), m.group(3)
    if head == "pg":
        if sep != ":":
            out.append(Token(BAD, raw, arg="the player gender token is {pg:male|female}"))
        else:
            out.append(Token(GRAMMAR, raw, name="pg", arg="pg", options=body.split("|")))
        return m.end()
    if sep == ":":
        # _ISPRINTF format, e.g. {1:d} or {2:05.1f}
        out.append(Token(PLACEHOLDER, raw, name=head, arg=body, strict=REQUIRED))
        return m.end()
    op, _, rest = body.partition(":")
    if op in ("plural", "g"):
        out.append(Token(GRAMMAR, raw, name=head, arg=op, options=rest.split("|")))
    elif ":" not in body and _ARTICLE_OP_RE.match(body):
        out.append(Token(GRAMMAR, raw, name=head, arg=body))
    else:
        out.append(Token(BAD, raw, arg="unknown grammar token operation %r" % body))
    return m.end()


def tokenize(text):
    """Splits a string into Tokens. Adjacent text is merged into one TEXT token."""
    out = []
    pos = 0
    n = len(text)
    while pos < n:
        ch = text[pos]
        if ch == "\\":
            m = _CODE_RE.match(text, pos)
            if m and m.group(0) == "\\\\":
                out.append(Token(TEXT, "\\"))
            elif m:
                g = m.groups()
                if g[0]:
                    out.append(Token(CODE, m.group(0), "sign", g[1], REQUIRED))
                elif g[2]:
                    name = g[2].lower()
                    out.append(Token(CODE, m.group(0), name, g[3], _ARG_CODES[name]))
                elif g[4]:
                    out.append(Token(CODE, m.group(0), "n", g[5], REQUIRED))
                elif g[6]:
                    out.append(Token(CODE, m.group(0), "color", g[6].lower(), FORMAT))
                else:
                    name = g[7].lower()
                    out.append(Token(CODE, m.group(0), name, None, _PLAIN_CODES[name]))
            else:
                bad = re.match(r"\\[A-Za-z]+(\[[^\]]*\])?", text[pos:])
                if bad:
                    out.append(Token(BAD, bad.group(0), arg="unknown control code %s" % bad.group(0)))
                    pos += len(bad.group(0))
                    continue
                out.append(Token(TEXT, "\\"))
                pos += 1
                continue
            pos = m.end()
        elif ch == "<":
            m = _TAG_RE.match(text, pos)
            if m:
                name = m.group(2).lower()
                strict = REQUIRED if name in REQUIRED_TAGS else FREE if name in FREE_TAGS else FORMAT
                out.append(Token(TAG, m.group(0), name, m.group(4), strict, closing=(m.group(1) == "/")))
                pos = m.end()
            else:
                out.append(Token(TEXT, "<"))
                pos += 1
        elif ch == "{":
            pos = _scan_brace(text, pos, out)
        else:
            nxt = pos
            while nxt < n and text[nxt] not in "\\<{":
                nxt += 1
            out.append(Token(TEXT, text[pos:nxt]))
            pos = nxt
    merged = []
    for t in out:
        if t.kind == TEXT and merged and merged[-1].kind == TEXT:
            merged[-1] = Token(TEXT, merged[-1].raw + t.raw)
        else:
            merged.append(t)
    return merged


#===============================================================================
# Measuring
#===============================================================================
## Escapes fmtReplaceEscapes turns back into characters.
_ESCAPES = (("&lt;", "<"), ("&gt;", ">"), ("&apos;", "'"), ("&quot;", "\""), ("&m;", "♂"),
            ("&f;", "♀"), ("&amp;", "&"))


def displayed_text(text, samples, grammar_sample=None):
    """The characters the message window lays out for a string.

    Content codes are replaced by sample text of a realistic worst case
    (samples: code name -> text, e.g. {"pn": "WWWWWWW"}), styles and pauses are
    dropped, \\n and <br> become line breaks and \\1/\\! become the wait
    character.

    @param samples dict of sample texts; "placeholder" is used for {n}
    @param grammar_sample function(Token) -> str for grammar tokens, or None to
           use the first option / the placeholder sample
    """
    out = []
    for t in tokenize(text):
        if t.kind == TEXT:
            s = t.raw
            for a, b in _ESCAPES:
                s = s.replace(a, b)
            out.append(s)
        elif t.kind == CODE:
            if t.name == "n" and t.arg is None:
                out.append("\n")
            elif t.name in ("1", "!"):
                out.append("\x01")
            elif t.name in samples:
                out.append(samples[t.name])
        elif t.kind == TAG:
            if t.name == "br" and not t.closing:
                out.append("\n")
        elif t.kind == PLACEHOLDER:
            out.append(samples.get("placeholder", ""))
        elif t.kind == GRAMMAR:
            if grammar_sample:
                out.append(grammar_sample(t))
            elif t.options:
                out.append(max(t.options, key=len))
            else:
                out.append(samples.get("placeholder", ""))
    return "".join(out)


def message_lines(text, metrics, width):
    """Lays text out like getFormattedText (the message window) does.

    @return (number of lines, list of overflowing words)
    """
    lines = 1
    x = 0
    lastword_x = 0
    word_width = 0
    word = []
    too_wide = False
    hadspace = False
    hadnonspace = False
    overflow = []

    def end_word():
        w_text = "".join(word).strip()
        if too_wide and w_text and w_text not in overflow:
            overflow.append(w_text)

    for ch in text:
        if ch == "\n":
            end_word()
            lines += 1
            x = 0
            lastword_x = 0
            word_width = 0
            word = []
            too_wide = False
            hadspace = True
            hadnonspace = False
            continue
        w = metrics.char_width(ch)
        isspace = ch.isspace() or ch in ("\x01", "\x02")
        if hadspace and not isspace:
            end_word()
            lastword_x = x
            word_width = 0
            word = []
            too_wide = False
            hadspace = False
            hadnonspace = True
        elif isspace:
            hadspace = True
        x += w
        word_width += w
        word.append(ch)
        if x + 1 > width and (not hadnonspace or not hadspace):
            if lastword_x != 0:
                lines += 1
                x = word_width
                lastword_x = 0
            elif not isspace:
                too_wide = True
    end_word()
    return lines, overflow


_CHUNK_RE = re.compile(r"\n|[^ \r\t\f\n\-]*-+|(\S*([ \r\t\f]?))")


def chunk_lines(text, metrics, width):
    """Lays text out like getLineBrokenChunks (drawTextEx) does.

    @return (number of lines, list of overflowing words)
    """
    lines = 1
    x = 0
    overflow = []
    pos = 0
    while pos < len(text):
        m = _CHUNK_RE.match(text, pos)
        if not m or m.end() == pos:
            break
        chunk = m.group(0)
        pos = m.end()
        if chunk == "\n":
            lines += 1
            x = 0
            continue
        w = metrics.width(chunk)
        if x > 0 and x + w > width and x + metrics.width(re.sub(r"\s*", "", chunk)) > width:
            lines += 1
            x = 0
        if x == 0 and metrics.width(chunk.rstrip()) > width:
            overflow.append(chunk.strip())
        x += w
    return lines, overflow

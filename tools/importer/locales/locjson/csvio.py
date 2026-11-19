"""@package locjson.csvio
Reads, writes and updates the translation CSVs.

Format: UTF-8 with a byte order mark (so spreadsheet programs detect the
encoding), RFC 4180 quoting (fields with commas, quotes or line breaks are
quoted; quotes are doubled), one header row. A line break inside a field is a
line break in game. CRLF inside fields is read as LF.
"""

import csv
import io
import os

## Columns of every CSV, in order.
COLUMNS = ["key", "context", "english", "translation", "status", "notes"]
## Extra columns of CSVs that hold nouns (grammar for articles).
NOUN_COLUMNS = ["gender", "sound"]
## Columns the tools write (translators edit the others).
TOOL_COLUMNS = {"key", "context", "english"}
## status: the English changed after this was translated.
STALE = "stale"
## status: the key no longer exists in the game; kept for reference.
OBSOLETE = "obsolete"
## Valid status values.
STATUSES = {"", STALE, OBSOLETE}
## How many other keys the context column lists.
MAX_ALSO = 4


class CsvError(Exception):
    """A CSV file can't be read."""

    def __init__(self, message, path=None, line=None):
        super().__init__(message)
        self.path = path
        self.line = line

    def __str__(self):
        where = self.path or ""
        if self.line:
            where += ":%d" % self.line
        return "%s: %s" % (where, self.args[0]) if where else self.args[0]


class Row(dict):
    """One CSV row: column -> value, plus the line it was read from."""

    def __init__(self, values=None, line=0):
        super().__init__(values or {})
        ## Line number in the file (0 if not read from a file).
        self.line = line

    def get_value(self, column):
        return self.get(column, "") or ""


def read_csv(path):
    """Reads a translation CSV. @return (columns, list of Row)"""
    with open(path, "rb") as f:
        raw = f.read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise CsvError("not UTF-8 (%s); save it as \"CSV UTF-8\"" % e, path)
    reader = csv.reader(io.StringIO(text, newline=""), strict=True)
    rows = []
    try:
        header = next(reader, None)
        if header is None:
            return list(COLUMNS), []
        header = [h.strip().lower() for h in header]
        for col in ("key", "english", "translation"):
            if col not in header:
                raise CsvError("the header row has no \"%s\" column" % col, path, 1)
        last_line = reader.line_num
        for record in reader:
            line = last_line + 1
            last_line = reader.line_num
            if not any(field.strip() for field in record):
                continue
            if len(record) > len(header) and any(v.strip() for v in record[len(header):]):
                raise CsvError("more fields than the header has columns (unquoted comma?)", path, line)
            values = {}
            for i, col in enumerate(header):
                v = record[i] if i < len(record) else ""
                values[col] = v.replace("\r\n", "\n").replace("\r", "\n")
            rows.append(Row(values, line))
    except csv.Error as e:
        raise CsvError("malformed CSV: %s" % e, path, reader.line_num)
    return header, rows


def render_csv(columns, rows):
    """CSV text (with the BOM) for rows."""
    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
    writer.writerow(columns)
    for row in rows:
        writer.writerow([row.get(c, "") or "" for c in columns])
    return "﻿" + out.getvalue()


def write_csv(path, columns, rows):
    """Writes a CSV if its contents change. @return True if written"""
    data = render_csv(columns, rows).encode("utf-8")
    if os.path.isfile(path):
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return True


def columns_for(strings):
    """The columns of a file holding these SourceStrings."""
    if any(s.noun for s in strings):
        return COLUMNS + NOUN_COLUMNS
    return list(COLUMNS)


def context_text(s):
    """The context column for a SourceString."""
    text = s.context
    if s.also:
        shown = ", ".join(s.also[:MAX_ALSO])
        more = len(s.also) - MAX_ALSO
        text += "%sSame text: %s%s" % ("; " if text else "", shown, " (+%d more)" % more if more > 0 else "")
    return text


def update_rows(old_rows, strings):
    """Merges a file's current English strings into its existing rows.

    - Rows keep their translation, notes and grammar.
    - A row whose English changed is marked stale (if it was translated).
    - A new key whose English matches an existing translated row (same file)
      gets that translation (translation memory), so moved or renumbered
      events keep their text.
    - Rows whose key is gone are marked obsolete if they hold a translation or
      notes, and dropped otherwise. Obsolete rows are kept at the end.

    @param old_rows list of Row from the existing file (may be empty)
    @param strings list of SourceString for this file, in order
    @return (rows, stats) where stats counts "new", "stale", "obsolete", "reused"
    """
    stats = {"new": 0, "stale": 0, "obsolete": 0, "reused": 0}
    by_key = {}
    memory = {}
    for row in old_rows:
        by_key.setdefault(row.get_value("key"), row)
        if row.get_value("translation") and row.get_value("status") != STALE:
            memory.setdefault(row.get_value("english"), row)
    rows = []
    used = set()
    for s in strings:
        old = by_key.get(s.key)
        row = Row({"key": s.key, "context": context_text(s), "english": s.english})
        if old is not None:
            used.add(s.key)
            for col, value in old.items():
                if col not in TOOL_COLUMNS:
                    row[col] = value
            if row.get_value("status") == OBSOLETE:
                row["status"] = ""
            if old.get_value("english") != s.english and row.get_value("translation"):
                if row.get_value("status") != STALE:
                    stats["stale"] += 1
                row["status"] = STALE
        else:
            stats["new"] += 1
            mem = memory.get(s.english)
            if mem is not None:
                for col in ("translation", "gender", "sound"):
                    if mem.get_value(col):
                        row[col] = mem.get_value(col)
                stats["reused"] += 1
        rows.append(row)
    current = {r.get_value("key") for r in rows}
    for row in old_rows:
        key = row.get_value("key")
        if key in used or key in current:
            continue
        if row.get_value("translation") or row.get_value("notes"):
            r = Row(row)
            if r.get_value("status") != OBSOLETE:
                stats["obsolete"] += 1
            r["status"] = OBSOLETE
            rows.append(r)
    return rows, stats

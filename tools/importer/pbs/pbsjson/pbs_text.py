"""@package pbsjson.pbs_text
Low-level PBS text handling, ported from the Essentials compiler
(src/data/021_Compiler/001_Compiler.rb) so values are read and written the
same way the engine does.
"""

import re

## The first line the engine writes in every PBS file (add_PBS_header_to_file).
HEADER = "# See the documentation on the wiki to learn how to edit this file."
## The line the engine writes before every section.
SEPARATOR = "#-------------------------------"
## Line ending the engine writes.
EOL = "\r\n"
## UTF-8 byte order mark.
BOM = "﻿"

_COMMENT_RE = re.compile(r"\s*#.*$")
_INT_RE = re.compile(r"^-?\d+$")
_UINT_RE = re.compile(r"^\d+$")
_HEX_RE = re.compile(r"^[A-F0-9]+$", re.IGNORECASE)
_FLOAT_RE = re.compile(r"^-?\d*\.?\d*$")
_TRUE_RE = re.compile(r"^(?:1|TRUE|YES|Y)$", re.IGNORECASE)
_FALSE_RE = re.compile(r"^(?:0|FALSE|NO|N)$", re.IGNORECASE)
_NAME_RE = re.compile(r"^(?![0-9])\w+$")


class PbsError(Exception):
    """An error in a PBS file, with the file and line it was found in."""

    def __init__(self, message, path=None, lineno=None):
        super().__init__(message)
        ## The message without location.
        self.message = message
        ## The PBS file, if known.
        self.path = path
        ## The 1-based line number, if known.
        self.lineno = lineno

    def __str__(self):
        where = ""
        if self.path:
            where = str(self.path)
            if self.lineno:
                where += ":%d" % self.lineno
            where += ": "
        return where + self.message


def read_lines(path):
    """Reads a PBS file.

    @param path path of the file
    @return (lines, bom): lines is a list of (line number, text without line
            ending); bom is True if the file starts with a UTF-8 BOM
    """
    with open(path, "rb") as f:
        data = f.read()
    bom = data.startswith(b"\xef\xbb\xbf")
    if bom:
        data = data[3:]
    text = data.decode("utf-8")
    lines = []
    for i, line in enumerate(text.split("\n")):
        lines.append((i + 1, line.rstrip("\r")))
    if lines and lines[-1][1] == "":
        lines.pop()
    return lines, bom


def is_comment_or_blank(line):
    """True for lines the compiler skips: comments and whitespace-only lines."""
    return line.startswith("#") or line.strip() == ""


def prepline(line):
    """Compiler.prepline: removes a trailing comment and surrounding whitespace.

    Note that the compiler removes everything after a "#" anywhere in a line,
    so values can never contain "#".
    """
    line = _COMMENT_RE.sub("", line, count=1)
    return line.strip()


def split_csv_line(string):
    """Port of Compiler.split_csv_line.

    Splits on commas, joining pieces back together while a piece has an odd
    number of quote marks, and strips whitespace from each value.
    """
    values = string.split(",")
    i = 0
    while i < len(values):
        value = values[i]
        if value is None or value == "":
            i += 1
            continue
        quote_count = value.count('"')
        if quote_count != 0:
            for j in range(i, len(values) - 1):
                quote_count = values[i].count('"')
                if quote_count == 2 and value.startswith('\\"') and values[i].endswith('\\"'):
                    values[i] = values[i][2:-2]
                    break
                elif quote_count % 2 == 0:
                    break
                values[i] += "," + (values[j + 1] or "")
                values[j + 1] = None
            if quote_count != 2:
                if value.count('"') == 2 and value.startswith('\\"') and value.endswith('\\"'):
                    values[i] = values[i][2:-2]
        values[i] = values[i].strip()
        i += 1
    return [v for v in values if v is not None]


def csv_quote(value):
    """Port of Compiler.csvQuote: quotes a string if it has a comma or quote."""
    if value is None or value == "":
        return ""
    if "," in value or '"' in value:
        return '"' + value.replace('"', '\\"') + '"'
    return value


def csv_unquote(value):
    """Undoes csv_quote, so a quoted string reads back as its text.

    The engine keeps the quote marks of a quoted value; JSON holds the text
    without them, and csv_quote puts them back when the PBS file is written.
    """
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        return value[1:-1].replace('\\"', '"')
    return value


def format_float(value):
    """Formats a float like Ruby's Float#inspect (1.0, 0.7, 1.0e+16)."""
    text = repr(float(value))
    if "e" in text:
        mantissa, exponent = text.split("e")
        if "." not in mantissa:
            mantissa += ".0"
        sign = exponent[0] if exponent[0] in "+-" else "+"
        digits = exponent.lstrip("+-").rjust(2, "0")
        text = mantissa + "e" + sign + digits
    return text


def cast_value(value, letter):
    """Port of Compiler.cast_csv_value for one schema letter.

    Enumerations ("e", "y") are kept as the text written in the PBS file
    (with "y" turned into an integer when it is a number); they are checked by
    the validator instead.

    @param value the text of the value (None if missing)
    @param letter one schema letter, upper or lower case
    @return the JSON value
    @throws PbsError if the value doesn't match the letter
    """
    kind = letter.lower()
    if kind == "i":
        if value is None or not _INT_RE.match(value):
            raise PbsError("Field '%s' is not an integer." % (value or ""))
        return int(value)
    if kind == "u":
        if value is None or not _UINT_RE.match(value):
            raise PbsError("Field '%s' is not a positive integer or 0." % (value or ""))
        return int(value)
    if kind == "v":
        if value is None or not _UINT_RE.match(value):
            raise PbsError("Field '%s' is not a positive integer." % (value or ""))
        if int(value) == 0:
            raise PbsError("Field '%s' must be greater than 0." % value)
        return int(value)
    if kind == "x":
        if value is None or not _HEX_RE.match(value):
            raise PbsError("Field '%s' is not a hexadecimal number." % (value or ""))
        return value
    if kind == "f":
        if value is None or not _FLOAT_RE.match(value):
            raise PbsError("Field '%s' is not a number." % (value or ""))
        try:
            return float(value)
        except ValueError:
            return 0.0
    if kind == "b":
        if value is not None and _TRUE_RE.match(value):
            return True
        if value is not None and _FALSE_RE.match(value):
            return False
        raise PbsError("Field '%s' is not a Boolean value (true, false, 1, 0)." % (value or ""))
    if kind in ("n", "m"):
        if value is None or not _NAME_RE.match(value):
            raise PbsError("Field '%s' must contain only letters, digits, and underscores "
                           "and can't begin with a number." % (value or ""))
        return value
    if kind == "e":
        if value is None or value == "":
            raise PbsError("Undefined value '' in an enumeration.")
        return value
    if kind == "y":
        if value is not None and _INT_RE.match(value):
            return int(value)
        if value is None or value == "":
            raise PbsError("Undefined value '' in an enumeration.")
        return value
    if kind == "s":
        return csv_unquote(value) if value is not None else None
    # "q" is handled by the caller; anything else is kept as text.
    return value


def format_value(value, letter):
    """Writes one value the way Compiler.pbWriteCsvRecord does."""
    kind = letter.lower()
    if kind in ("e", "y"):
        return str(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return value if kind == "q" else csv_quote(value)
    if isinstance(value, float):
        return format_float(value)
    return str(value)


def write_record(rec, schema_type):
    """Port of Compiler.pbWriteCsvRecord.

    @param rec flat list of values (None for missing optional values)
    @param schema_type the schema type string, e.g. "*ue" or "uUUUUU"
    @return the text of the record
    """
    out = []
    start = 1 if schema_type[:1] in ("*", "^") else 0
    index = -1
    while True:
        for i in range(start, len(schema_type)):
            index += 1
            value = rec[index] if index < len(rec) else None
            letter = schema_type[i]
            if letter.isupper():
                if not any(rec[j] is not None for j in range(index, len(rec))):
                    start = -1
                    break
            if index > 0:
                out.append(",")
            if value is None:
                continue
            out.append(format_value(value, letter))
        if start > 0 and index >= len(rec) - 1:
            break
        if start <= 0:
            break
    return "".join(out)

"""@package pbsjson.fields
One PBS property ("Key = value" line) described by an engine schema entry,
and how its value is turned into JSON and back.
"""

from .pbs_text import PbsError, cast_value, split_csv_line, write_record


def json_key(prop):
    """The JSON key for an engine property symbol (snake_case, lower case)."""
    return prop.lower()


class Field:
    """A schema entry: PBS key, JSON key, type string and enum references.

    JSON shapes, from the type string:
    - one letter: a scalar ("FIRE", 40, true)
    - several letters: an object whose keys come from names.json
    - "*" + one letter: a list of scalars
    - "*" + several letters: a list of objects
    - "^" + letters: one "Key = value" line per element of a list
    - "q": the unformatted rest of the line
    """

    def __init__(self, entry, dataset, names):
        ## The key in the PBS file, e.g. "BaseStats".
        self.key = entry["key"]
        ## The engine property, e.g. "base_stats".
        self.prop = entry["property"]
        ## The JSON key, e.g. "base_stats".
        self.json_key = json_key(self.prop)
        ## The full type string, e.g. "*ue".
        self.type = entry["type"]
        ## "*", "^" or "".
        self.prefix = self.type[0] if self.type[:1] in ("*", "^") else ""
        ## The type letters without the prefix.
        self.letters = self.type[len(self.prefix):]
        ## One enum reference (or None) per letter.
        self.enums = list(entry.get("enums") or [])
        while len(self.enums) < len(self.letters):
            self.enums.append(None)
        ## Names of the values of a multi-value record, from names.json.
        self.names = None
        if len(self.letters) > 1:
            self.names = names.tuple_names(dataset, self.key)
            if self.names is None:
                raise PbsError("names.json has no tuple names for %s.%s (type %s). Add an entry "
                               "with %d names." % (dataset, self.key, self.type, len(self.letters)))
            if len(self.names) != len(self.letters):
                raise PbsError("names.json gives %d names for %s.%s but its type %s has %d values."
                               % (len(self.names), dataset, self.key, self.type, len(self.letters)))

    @property
    def multi_line(self):
        """True for "^" fields, which are written as one line per value."""
        return self.prefix == "^"

    @property
    def is_list(self):
        """True if the JSON value is a list."""
        return self.prefix in ("*", "^")

    def _record(self, values):
        """Turns a list of record values into a scalar or a named object."""
        if self.names is None:
            return values[0] if values else None
        obj = {}
        for name, value in zip(self.names, values):
            if value is not None:
                obj[name] = value
        return obj

    def parse_one(self, raw):
        """Parses the text of one line (or one "^" line) into JSON.

        Mirrors Compiler.get_csv_record.
        """
        if self.letters == "q":
            return raw
        repeat = self.prefix == "*"
        values = split_csv_line(raw)
        if repeat and len(values) == 0:
            return []
        result = []
        idx = -1
        while True:
            record = []
            for letter in self.letters:
                idx += 1
                value = values[idx] if idx < len(values) else None
                if letter.isupper() and (value is None or value == ""):
                    record.append(None)
                    continue
                record.append(cast_value(value, letter))
            if repeat:
                result.append(self._record(record))
            else:
                result = record
            if not repeat or idx >= len(values) - 1:
                break
        if repeat:
            return result
        return self._record(result)

    def parse(self, raw):
        """Parses a property: a string, or a list of strings for "^" fields."""
        if self.multi_line:
            return [self.parse_one(line) for line in raw]
        return self.parse_one(raw)

    def _flatten(self, value):
        """Turns one record (scalar or object) into a flat list of values."""
        if self.names is None:
            return [value]
        if not isinstance(value, dict):
            raise PbsError("%s must be an object with keys %s." % (self.json_key, ", ".join(self.names)))
        return [value.get(name) for name in self.names]

    def format_one(self, value):
        """Writes one value (or one "^" element) as PBS text."""
        if self.prefix == "*":
            rec = []
            for item in value:
                rec.extend(self._flatten(item))
            return write_record(rec, self.type)
        return write_record(self._flatten(value), self.type)

    def format_lines(self, value):
        """The "Key = value" lines for a JSON value (none if it is empty)."""
        if value is None:
            return []
        if self.is_list and isinstance(value, list) and len(value) == 0:
            return []
        if self.multi_line:
            return ["%s = %s" % (self.key, self.format_one(v)) for v in value]
        return ["%s = %s" % (self.key, self.format_one(value))]


class FieldGroup:
    """The fields of one schema, with PBS keys that share a property merged.

    Species has both "Evolutions" (all on one line) and "Evolution" (one per
    line) for the same property; JSON has one "evolutions" key, and the engine
    writes the one-per-line form.
    """

    def __init__(self, entries, dataset, names):
        ## Every field by PBS key, in schema order.
        self.by_key = {}
        ## Fields by JSON key, in schema order; each is a list of the fields
        ## that share it (writer first).
        self.by_json = {}
        for entry in entries:
            field = Field(entry, dataset, names)
            self.by_key[field.key] = field
            self.by_json.setdefault(field.json_key, []).append(field)
        for key, fields in self.by_json.items():
            if len(fields) > 1:
                fields.sort(key=lambda f: 0 if f.multi_line else 1)
                first = fields[0]
                for other in fields[1:]:
                    if other.letters.lower() != first.letters.lower() or not other.is_list or not first.is_list:
                        raise PbsError("PBS keys %s and %s share the property %s but have different "
                                       "shapes." % (first.key, other.key, key))
        ## PBS keys accepted for other keys (old names), from names.json.
        self.aliases = names.aliases(dataset)

    @property
    def section_field(self):
        """The "SectionName" field, or None."""
        return self.by_key.get("SectionName")

    def property_fields(self):
        """(JSON key, writer field) for each property except SectionName."""
        for key, fields in self.by_json.items():
            if fields[0].key == "SectionName":
                continue
            yield key, fields[0]

    def field_for_key(self, pbs_key):
        """The field for a PBS key (resolving old names), or None."""
        pbs_key = self.aliases.get(pbs_key, pbs_key)
        return self.by_key.get(pbs_key)

    def is_multi_line(self, pbs_key):
        """True if a PBS key may appear on several lines of a section."""
        field = self.field_for_key(pbs_key)
        return field is not None and field.multi_line

    def section_to_json(self, section_name):
        """Parses a section name into JSON keys (merged into the entry)."""
        field = self.section_field
        if field is None:
            return {"id": section_name}
        value = field.parse(section_name)
        if field.names is None:
            return {field.json_key: value}
        return value

    def section_from_json(self, entry):
        """Writes the section name of an entry."""
        field = self.section_field
        if field is None:
            return str(entry["id"])
        if field.names is None:
            return field.format_one(entry.get(field.json_key))
        return field.format_one({name: entry.get(name) for name in field.names})

    def section_keys(self):
        """The JSON keys that hold the section name."""
        field = self.section_field
        if field is None:
            return ["id"]
        return list(field.names) if field.names else [field.json_key]

    def properties_to_json(self, contents, warn):
        """Parses a section's "Key = value" texts into JSON properties.

        @param contents dict of PBS key -> text (list of texts for "^" keys),
               in file order
        @param warn function(message) for keys the schema doesn't know
        """
        resolved = {}
        for pbs_key, raw in contents.items():
            field = self.field_for_key(pbs_key)
            if field is None or field.key == "SectionName":
                warn("Unknown property %s (ignored, as the compiler does)." % pbs_key)
                continue
            if field.multi_line:
                resolved.setdefault(field.key, []).extend(raw)
            else:
                resolved[field.key] = raw
        result = {}
        # The compiler reads properties in schema order, which matters when two
        # keys add to the same list.
        for pbs_key, field in self.by_key.items():
            if pbs_key not in resolved:
                continue
            value = field.parse(resolved[pbs_key])
            if field.is_list:
                if value is None:
                    continue
                result.setdefault(field.json_key, [])
                result[field.json_key].extend(value)
            else:
                result[field.json_key] = value
        ordered = {}
        for key in self.by_json:
            if key in result and not (isinstance(result[key], list) and len(result[key]) == 0):
                ordered[key] = result[key]
        return ordered

    def properties_to_lines(self, entry):
        """The "Key = value" lines of an entry, in schema order."""
        lines = []
        for key, field in self.property_fields():
            lines.extend(field.format_lines(entry.get(key)))
        return lines

    def known_json_keys(self):
        """Every JSON key an entry may have."""
        return set(self.section_keys()) | {k for k, _ in self.property_fields()}

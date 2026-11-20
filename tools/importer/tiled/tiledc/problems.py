"""@package tiledc.problems
Errors and warnings found while validating or compiling.
"""


class TiledError(Exception):
    """A problem that stops the current command."""


class Problem:
    """One error or warning about a source file."""

    def __init__(self, path, where, message, warning=False):
        ## File the problem is in (relative to the repository root when possible).
        self.path = path
        ## Position inside the file (layer, object, tile, ...), or "".
        self.where = where
        ## What's wrong.
        self.message = message
        ## True for warnings, which don't stop a build unless --strict.
        self.warning = warning

    def __str__(self):
        where = " (%s)" % self.where if self.where else ""
        return "%s%s: %s" % (self.path, where, self.message)


class Problems:
    """Collects problems."""

    def __init__(self):
        ## Every problem, in the order found.
        self.items = []

    def error(self, path, where, message):
        """Adds an error."""
        self.items.append(Problem(path, where, message))

    def warning(self, path, where, message):
        """Adds a warning."""
        self.items.append(Problem(path, where, message, warning=True))

    def errors(self, strict=False):
        """@return the problems that stop a build (warnings too if strict)"""
        return [p for p in self.items if strict or not p.warning]

    def extend(self, other):
        """Adds another collection's problems."""
        self.items.extend(other.items)

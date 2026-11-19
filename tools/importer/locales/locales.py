#!/usr/bin/env python3
"""CSV localization for Pokessentials.

Usage: python3 -I tools/importer/locales/locales.py [options] COMMAND

Commands:
  update             write the current English text into every language's CSVs
                     in src/assets/locales/<lang>/ (translations are kept)
  validate           check the translations
  build BUILD_DIR    check, then write BUILD_DIR/Data/messages_<lang>_*.dat and
                     the localized graphics

See docs/LOCALIZATION.md.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from locjson.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Checks that every text the app shows has a Finnish translation.

All text shown to people is written as tr("English text") in the Swift sources. This
script collects those English texts and compares them with the table in
Sources/SiivOSCore/Localization/FinnishTexts.swift. It fails if a text has no
translation, if a translation is no longer used, or if a translation uses different
changing parts (%1$@, %2$@, ...) than the English text.

Usage (from the project folder):  python3 Scripts/check-translations.py
Add --list-missing to print the untranslated texts ready to paste into the table.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLE = ROOT / "Sources/SiivOSCore/Localization/FinnishTexts.swift"
STRING = r'"((?:[^"\\]|\\.)*)"'
USE = re.compile(r'\btr\(\s*' + STRING)
ENTRY = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r'\s*,?\s*$')
PLACEHOLDER = re.compile(r'%(\d+)\$@')


def used_texts():
    found = {}
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        if path == TABLE:
            continue
        # Comment lines are left out: an example in a comment is not a text shown to people.
        code = "\n".join(
            line for line in path.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("//")
        )
        for match in USE.finditer(code):
            found.setdefault(match.group(1), path.relative_to(ROOT))
    return found


def translations():
    table = {}
    for line in TABLE.read_text(encoding="utf-8").splitlines():
        match = ENTRY.match(line)
        if match:
            if match.group(1) in table:
                sys.exit(f"Listed twice in the Finnish table: {match.group(1)}")
            table[match.group(1)] = match.group(2)
    return table


def main():
    used = used_texts()
    table = translations()
    missing = [text for text in used if text not in table]
    unused = [text for text in table if text not in used]
    mismatched = [
        text for text, finnish in table.items()
        if set(PLACEHOLDER.findall(text)) != set(PLACEHOLDER.findall(finnish))
    ]
    dynamic = [text for text in used if "\\(" in text]

    if "--list-missing" in sys.argv:
        for text in missing:
            print(f'        "{text}": "",')
        return

    problems = False
    for title, texts in [
        ("No Finnish translation", missing),
        ("Translated but no longer used", unused),
        ("Changing parts differ between English and Finnish", mismatched),
        ("Uses \\( ) inside tr(); use %1$@ and pass the value separately", dynamic),
    ]:
        if texts:
            problems = True
            print(f"{title}:")
            for text in texts:
                where = f"  [{used[text]}]" if text in used else ""
                print(f"  {text}{where}")
    if problems:
        sys.exit(1)
    print(f"Translations: all {len(used)} texts have a Finnish translation.")


if __name__ == "__main__":
    main()

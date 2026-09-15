#!/usr/bin/env python3
"""Check store limits, locale coverage and version wiring without building the app."""
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EU = {"fr-FR", "nl-NL", "de-DE", "es-ES", "it-IT", "pl-PL", "sv-SE",
      "da-DK", "fi-FI", "pt-PT", "ro", "cs-CZ"}
LANGUAGES = {locale.split("-")[0] for locale in EU} | {"en", "ru"}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def main():
    page = text("eupage.txt")
    listings = re.findall(r"^\[([\w-]+)\]\n(.*?)^\[/\1\]$", page, re.M | re.S)
    require(len(listings) == len(EU) and {code for code, _ in listings} == EU,
            "Expected exactly 12 EU listings")
    for code, body in listings:
        title = re.search(r"^Название: (.+)$", body, re.M)
        short = re.search(r"^Краткое описание: (.+)$", body, re.M)
        full = re.search(r"^Полное описание:\n(.+)", body, re.M | re.S)
        for field, match, limit in (("title", title, 30), ("short", short, 80),
                                    ("full", full, 4000)):
            require(match is not None, f"{code}: missing {field}")
            length = len(match.group(1).strip())
            require(0 < length <= limit, f"{code}: {field} has {length}/{limit} characters")

    notes = re.findall(r"^<([\w-]+)>\n(.*?)^</\1>$", page, re.M | re.S)
    require(len(notes) == 14 and {code for code, _ in notes} == EU | {"en-US", "ru-RU"},
            "Expected one release-note block per supported Play locale")
    for code, body in notes:
        require(0 < len(body.strip()) <= 500, f"{code}: invalid release-note length")

    namespace = "{http://schemas.android.com/apk/res/android}"
    locales = ET.fromstring(text("android/app/src/main/res/xml/locales_config.xml"))
    codes = [node.attrib[namespace + "name"] for node in locales]
    require(len(codes) == 14 and {code.split("-")[0] for code in codes} == LANGUAGES,
            "Android locales do not match the supported languages")
    require("pt-PT" in codes, "European Portuguese must be explicit")
    dart = text("lib/l10n/app_localizations.dart")
    supported = re.search(r"supportedLocales = <Locale>\[(.*?)\];", dart, re.S)
    require(supported is not None, "Missing Flutter supportedLocales")
    require(set(re.findall(r"Locale\('([a-z]+)'", supported.group(1))) == LANGUAGES,
            "Flutter locale coverage differs from Android")

    for directory, expected in (("values", "Rabochiy VPN"), ("values-ru", "Рабочий VPN")):
        strings = ET.fromstring(text(f"android/app/src/main/res/{directory}/strings.xml"))
        require(strings.find("string[@name='app_name']").text == expected,
                f"Incorrect launcher name in {directory}")

    require(re.search(r"^version: 1\.0\.1\+3$", text("pubspec.yaml"), re.M),
            "Expected release version 1.0.1+3")
    gradle = text("android/app/build.gradle.kts")
    require("versionCode = flutter.versionCode" in gradle and
            "versionName = flutter.versionName" in gradle,
            "Android version must be derived from Flutter")
    example = json.loads(text("config/build-secrets.example.json"))
    require(example == {"RABOCHIY_SIGNING_SECRET": ""}, "Example must not contain credentials")
    print("Validated 12 listings, 14 release-note blocks, locale coverage, branding and version 1.0.1+3.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Проверка GDScript без движка: gdtoolkit (парсер + линтер) и `godot --check-only`
там, где движок доступен. Запускается локально и в CI.

Использование:
    python3 tools/check_gdscript.py            # только парсинг
    python3 tools/check_gdscript.py --lint     # плюс gdlint (правила стиля)
    python3 tools/check_gdscript.py --godot /path/to/Godot   # плюс полная проверка движком
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXCLUDE_DIRS = {".git", ".godot", "addons", "art", "docs"}


def find_scripts() -> list[Path]:
    found: list[Path] = []
    for path in ROOT.rglob("*.gd"):
        if any(part in EXCLUDE_DIRS for part in path.parts):
            continue
        found.append(path)
    return sorted(found)


def run_gdparse(binary: str, path: Path) -> tuple[bool, str]:
    result = subprocess.run([binary, str(path)], capture_output=True, text=True)
    if result.returncode != 0:
        return False, (result.stdout + result.stderr).strip()
    return True, ""


def run_gdlint(binary: str, path: Path) -> tuple[bool, str]:
    result = subprocess.run([binary, str(path)], capture_output=True, text=True)
    if result.returncode != 0:
        return False, (result.stdout + result.stderr).strip()
    return True, ""


def run_godot(godot: str, script: str) -> tuple[bool, str]:
    result = subprocess.run(
        [godot, "--headless", "--path", str(ROOT), "--check-only", "--script", script],
        capture_output=True,
        text=True,
    )
    output = (result.stdout + result.stderr).strip()
    failed = result.returncode != 0 or "SCRIPT ERROR" in output or "Parse Error" in output
    return (not failed), output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lint", action="store_true", help="запустить gdlint")
    parser.add_argument("--godot", default=None, help="путь к бинарнику Godot 4.3")
    args = parser.parse_args()

    gdparse = shutil.which("gdparse")
    gdlint = shutil.which("gdlint")
    if gdparse is None and args.godot is None:
        print("нет ни gdparse, ни Godot — проверять нечем", file=sys.stderr)
        return 2

    scripts = find_scripts()
    print(f"Проверяю {len(scripts)} скриптов...")
    failures = 0

    for path in scripts:
        rel = path.relative_to(ROOT)
        if gdparse is not None:
            ok, output = run_gdparse(gdparse, path)
            if not ok:
                failures += 1
                print(f"  [PARSE] {rel}\n{output}\n")
                continue
        if args.lint and gdlint is not None:
            ok, output = run_gdlint(gdlint, path)
            if not ok:
                failures += 1
                print(f"  [LINT] {rel}\n{output}\n")

    if args.godot:
        print("Проверяю проект движком (импорт + шейдеры)...")
        import_result = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT), "--import", "--quit"],
            capture_output=True,
            text=True,
        )
        import_output = (import_result.stdout + import_result.stderr)
        errors = [
            line
            for line in import_output.splitlines()
            if "ERROR" in line or "Parse Error" in line or "Compile Error" in line
        ]
        if errors:
            failures += len(errors)
            print("  [ENGINE] ошибки импорта:")
            for line in errors[:60]:
                print("   ", line)
        if import_result.returncode != 0:
            failures += 1
            print(f"  [ENGINE] код возврата {import_result.returncode}")
            print(import_output[-4000:])

    if failures:
        print(f"\nПРОВАЛ: {failures} проблем(ы)")
        return 1
    print("\nOK: парсинг чистый" + (", линтер чистый" if args.lint else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

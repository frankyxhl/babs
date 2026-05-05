#!/usr/bin/env python3
"""Browser-harness BDD runner for Phase 1a terminal characterization."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from babs_steps import BabsBddContext, SkipScenario, scenarios  # noqa: E402


def main() -> None:
    context = BabsBddContext()
    failures = []

    print(f"browser-harness BDD base_url={context.base_url}")

    try:
        context.ensure_server()

        for scenario in scenarios():
            print(f"\nSCENARIO {scenario.name}")
            print(f"  Given {scenario.given}")
            print(f"  When  {scenario.when}")
            print(f"  Then  {scenario.then}")

            try:
                scenario.run(context)
            except SkipScenario as reason:
                print(f"  SKIP {reason}")
            except Exception as error:  # noqa: BLE001 - test runner reports any failure.
                failures.append((scenario.name, error))
                print(f"  FAIL {type(error).__name__}: {error}")
            else:
                print("  PASS")
            finally:
                context.close_test_tab()
    finally:
        context.cleanup()

    if failures:
        print("\nBDD failures:")
        for name, error in failures:
            print(f"- {name}: {type(error).__name__}: {error}")
        raise SystemExit(1)

    print("\nBDD PASS")


if __name__ == "__main__":
    main()

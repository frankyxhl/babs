#!/usr/bin/env python3
"""Browser-harness BDD runner for Babs terminal workflows."""

from __future__ import annotations

import sys
import os
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from babs_steps import BabsBddContext, SkipScenario, scenarios  # noqa: E402


def main() -> None:
    context = BabsBddContext()
    failures = []

    print(f"browser-harness BDD base_url={context.base_url}")

    try:
        context.ensure_server()

        scenario_filter = os.environ.get("BABS_BDD_SCENARIO", "").strip().lower()
        selected = 0

        for scenario in scenarios():
            if scenario_filter and scenario_filter not in scenario.name.lower():
                continue

            selected += 1
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

        if scenario_filter and selected == 0:
            failures.append((scenario_filter, RuntimeError("no BDD scenario matched filter")))
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

# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml"]
# ///
"""Package the charts to release into .cr-release-packages, in dependency order.

Dependencies come from their published repository. A dependency on an in-repo
chart whose locked version is not published yet but released in this run takes
this run's package instead: it is not on gh-pages until chart-releaser uploads.

Usage: release-charts.py [CHART_DIR...]  (default: charts changed since the latest tag)
"""

import shutil
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from graphlib import TopologicalSorter
from pathlib import Path

import yaml

REPO_URL = "https://nw-tech.github.io/public_charts/"
PACKAGES = Path(".cr-release-packages")


@dataclass(frozen=True)
class Dependency:
    name: str
    version: str
    repository: str


@dataclass
class Chart:
    path: Path
    name: str
    version: str
    dependencies: list[Dependency]


def load_chart(path: Path) -> Chart:
    meta = yaml.safe_load((path / "Chart.yaml").read_text())
    declared = [
        Dependency(d["name"], str(d["version"]), d["repository"].rstrip("/"))
        for d in meta.get("dependencies") or []
    ]
    lock_file = path / "Chart.lock"
    lock = yaml.safe_load(lock_file.read_text()) if lock_file.exists() else {}
    locked = [
        Dependency(d["name"], str(d["version"]), d["repository"].rstrip("/"))
        for d in lock.get("dependencies") or []
    ]
    # Every dependency is pinned to an exact version, so the lock must match Chart.yaml.
    if set(declared) != set(locked):
        sys.exit(
            f"{path}: Chart.lock is out of sync with Chart.yaml, run `helm dependency update {path}`"
        )
    return Chart(path, meta["name"], str(meta["version"]), locked)


def run(*args: str | Path) -> str:
    return subprocess.run(
        args, check=True, stdout=subprocess.PIPE, text=True
    ).stdout.strip()


def changed_chart_dirs() -> set[Path]:
    tag = run(
        "git",
        "describe",
        "--tags",
        "--abbrev=0",
        run("git", "rev-list", "--tags", "--max-count=1"),
    )
    print(f"Discovering changed charts since '{tag}'...")
    files = run(
        "git", "diff", "--find-renames", "--name-only", tag, "--", "charts"
    ).splitlines()
    dirs = {Path(*Path(f).parts[:2]) for f in files if len(Path(f).parts) > 2}
    # Deleted charts and non-chart folders have no Chart.yaml.
    return {d for d in dirs if (d / "Chart.yaml").exists()}


def published_versions() -> set[tuple[str, str]]:
    with urllib.request.urlopen(REPO_URL + "index.yaml") as response:
        index = yaml.safe_load(response)
    return {
        (name, str(e["version"]))
        for name, entries in index["entries"].items()
        for e in entries
    }


def charts_to_release(dirs: set[Path]) -> dict[str, Chart]:
    """The given charts whose version is not published yet, by name."""
    published = published_versions()
    to_release = {}
    for path in sorted(dirs):
        chart = load_chart(path)
        if (chart.name, chart.version) in published:
            print(
                f"::warning::{path} changed but {chart.name} {chart.version} is already published, bump its version to release it"
            )
        else:
            to_release[chart.name] = chart
    return to_release


def is_local(dep: Dependency, to_release: dict[str, Chart]) -> bool:
    """An unpublished in-repo chart version built by this run."""
    local = to_release.get(dep.name)
    return (
        dep.repository == REPO_URL.rstrip("/")
        and local is not None
        and local.version == dep.version
    )


def packaging_order(to_release: dict[str, Chart]) -> list[Chart]:
    """Charts after the in-repo dependencies they take from this run. Raises CycleError on a cycle."""
    graph = {
        name: {d.name for d in c.dependencies if is_local(d, to_release)}
        for name, c in to_release.items()
    }
    return [to_release[name] for name in TopologicalSorter(graph).static_order()]


def download(deps: set[Dependency], destination: Path) -> None:
    """Download each dependency once, fetching each repository index once."""
    repos = {
        url: f"release-charts-{i}"
        for i, url in enumerate(sorted({d.repository for d in deps}))
    }
    for url, alias in repos.items():
        run("helm", "repo", "add", "--force-update", alias, url)
    if repos:
        run("helm", "repo", "update", *repos.values())
    for dep in sorted(deps, key=lambda d: (d.name, d.version)):
        print(f"Downloading {dep.name} {dep.version} from {dep.repository}")
        run(
            "helm",
            "pull",
            f"{repos[dep.repository]}/{dep.name}",
            "--version",
            dep.version,
            "-d",
            destination,
        )


def package(chart: Chart, to_release: dict[str, Chart], downloads: Path) -> None:
    """Fill the chart's charts/ with its locked dependencies, then package it."""
    print(f"Packaging chart '{chart.path}'...")
    subcharts = chart.path / "charts"
    subcharts.mkdir(exist_ok=True)
    for old in subcharts.glob("*.tgz"):
        old.unlink()
    for dep in chart.dependencies:
        source = PACKAGES if is_local(dep, to_release) else downloads
        shutil.copy(source / f"{dep.name}-{dep.version}.tgz", subcharts)
    print(run("helm", "package", chart.path, "--destination", PACKAGES))


def main() -> None:
    shutil.rmtree(PACKAGES, ignore_errors=True)
    PACKAGES.mkdir()
    dirs = {Path(a.rstrip("/")) for a in sys.argv[1:]} or changed_chart_dirs()
    to_release = charts_to_release(dirs)
    if not to_release:
        print("No chart to release.")
        return

    order = packaging_order(to_release)
    print(f"Packaging order: {', '.join(c.name for c in order)}")
    remote = {
        d
        for c in to_release.values()
        for d in c.dependencies
        if not is_local(d, to_release)
    }
    with tempfile.TemporaryDirectory() as downloads:
        download(remote, Path(downloads))
        for chart in order:
            package(chart, to_release, Path(downloads))


if __name__ == "__main__":
    main()

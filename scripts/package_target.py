#!/usr/bin/env python3
"""Validate a Product deployment and dispatch its Target Capsule."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9._-]*$")


class ProfileError(ValueError):
    """A deployment composition is malformed or internally inconsistent."""


def _load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ProfileError(f"cannot read {label}: {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ProfileError(f"invalid {label} JSON: {path}: {error.msg}") from error
    if not isinstance(value, dict):
        raise ProfileError(f"{label} must be a JSON object: {path}")
    return value


def _exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        raise ProfileError(
            f"{label} fields differ: missing={sorted(expected - actual)}, "
            f"extra={sorted(actual - expected)}"
        )


def _safe_id(value: object, label: str) -> str:
    if not isinstance(value, str) or SAFE_ID.fullmatch(value) is None:
        raise ProfileError(f"{label} must match {SAFE_ID.pattern}")
    return value


def _relative_file(value: object, label: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ProfileError(f"{label} must be a non-empty relative path")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts:
        raise ProfileError(f"{label} must stay inside the Product repository")
    path = (REPOSITORY_ROOT / Path(*pure.parts)).resolve(strict=False)
    try:
        path.relative_to(REPOSITORY_ROOT)
    except ValueError as error:
        raise ProfileError(f"{label} resolves outside the Product repository") from error
    if not path.is_file():
        raise ProfileError(f"{label} is missing: {value}")
    return path


def _application(path: Path) -> dict[str, Any]:
    app = _load_object(path, "application manifest")
    _exact_keys(app, {"schema_version", "id", "build", "runtime"}, "application manifest")
    if app["schema_version"] != 1:
        raise ProfileError("application schema_version must be 1")
    _safe_id(app["id"], "application id")

    build = app["build"]
    if not isinstance(build, dict):
        raise ProfileError("application build must be an object")
    _exact_keys(build, {"owner"}, "application build")
    if build["owner"] != "target-capsule":
        raise ProfileError("application build owner must be target-capsule")

    runtime = app["runtime"]
    if not isinstance(runtime, dict):
        raise ProfileError("application runtime must be an object")
    _exact_keys(runtime, {"entrypoint", "install_dir"}, "application runtime")
    for field in ("entrypoint", "install_dir"):
        if runtime[field] is not None and (
            not isinstance(runtime[field], str) or not runtime[field]
        ):
            raise ProfileError(f"application runtime.{field} must be null or a string")
    return app


def compose(
    deployment_id: str,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Path | None]]:
    deployment_id = _safe_id(deployment_id, "deployment id")
    profile_path = REPOSITORY_ROOT / "config" / "deployments" / f"{deployment_id}.json"
    profile = _load_object(profile_path, "deployment profile")
    _exact_keys(
        profile,
        {
            "schema_version",
            "id",
            "status",
            "product",
            "application",
            "target",
            "binding",
            "artifact",
            "packager",
        },
        "deployment profile",
    )
    if profile["schema_version"] != 1:
        raise ProfileError("deployment schema_version must be 1")
    if profile["id"] != deployment_id:
        raise ProfileError("deployment id must match its filename")
    if profile["status"] not in {"active", "planned"}:
        raise ProfileError("deployment status must be active or planned")
    product = _safe_id(profile["product"], "deployment product")
    target = _safe_id(profile["target"], "deployment target")

    artifact = profile["artifact"]
    if not isinstance(artifact, dict):
        raise ProfileError("deployment artifact must be an object")
    _exact_keys(artifact, {"kind", "manifest"}, "deployment artifact")
    _safe_id(artifact["kind"], "deployment artifact kind")

    paths: dict[str, Path | None] = {
        "profile": profile_path.resolve(),
        "application": _relative_file(profile["application"], "deployment application"),
        "binding": None,
        "artifact_manifest": _relative_file(
            artifact["manifest"], "deployment artifact manifest"
        ),
        "packager": _relative_file(profile["packager"], "deployment packager"),
    }
    if profile["binding"] is not None:
        paths["binding"] = _relative_file(profile["binding"], "deployment binding")

    app = _application(paths["application"])  # type: ignore[arg-type]
    if paths["binding"] is not None:
        binding = _load_object(paths["binding"], "hardware binding")
        if binding.get("product") != product:
            raise ProfileError("hardware binding product does not match the deployment")
        binding_target = binding.get("target", binding.get("target_id"))
        if binding_target != target:
            raise ProfileError("hardware binding target does not match the deployment")

    manifest = _load_object(paths["artifact_manifest"], "artifact manifest")  # type: ignore[arg-type]
    if manifest.get("target") != target:
        raise ProfileError("artifact manifest target does not match the deployment")
    try:
        files = manifest["deploy"]["app"]["files"]
    except (KeyError, TypeError) as error:
        raise ProfileError("artifact manifest has no deploy.app.files") from error
    if not isinstance(files, list) or not files:
        raise ProfileError("artifact manifest deploy.app.files must not be empty")
    if not os.access(paths["packager"], os.X_OK):  # type: ignore[arg-type]
        raise ProfileError("deployment packager is not executable")
    return profile, app, paths


def _relative(path: Path | None) -> str | None:
    if path is None:
        return None
    return path.relative_to(REPOSITORY_ROOT).as_posix()


def describe(
    profile: dict[str, Any],
    app: dict[str, Any],
    paths: dict[str, Path | None],
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "deployment": profile["id"],
        "status": profile["status"],
        "product": profile["product"],
        "application": app["id"],
        "target": profile["target"],
        "artifact_kind": profile["artifact"]["kind"],
        "runtime": app["runtime"],
        "paths": {name: _relative(path) for name, path in paths.items()},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--deployment",
        default=os.environ.get("GAR_DEPLOYMENT") or os.environ.get("GAR_TARGET"),
    )
    parser.add_argument("--describe", action="store_true")
    parser.add_argument("action", nargs="?", choices=("clean",))
    arguments = parser.parse_args(argv)
    if arguments.deployment is None:
        parser.error("--deployment is required when GAR_DEPLOYMENT and GAR_TARGET are unset")
    if arguments.describe and arguments.action:
        parser.error("--describe cannot be combined with clean")

    try:
        profile, app, paths = compose(arguments.deployment)
    except ProfileError as error:
        print(f"deployment profile: {error}", file=sys.stderr)
        return 2

    requested_target = os.environ.get("GAR_TARGET")
    if requested_target and requested_target != profile["target"]:
        print(
            "deployment profile: GAR_TARGET does not match the selected deployment: "
            f"{requested_target} != {profile['target']}",
            file=sys.stderr,
        )
        return 2
    if arguments.describe:
        print(json.dumps(describe(profile, app, paths), ensure_ascii=False, indent=2))
        return 0
    if profile["status"] != "active":
        print(
            f"deployment profile: {profile['id']} is planned and cannot be packaged",
            file=sys.stderr,
        )
        return 3

    environment = dict(os.environ)
    environment.update(
        {
            "GAR_DEPLOYMENT": profile["id"],
            "GAR_DEPLOYMENT_PROFILE": str(paths["profile"]),
            "GAR_PRODUCT_ID": profile["product"],
            "GAR_TARGET": profile["target"],
            "GAR_APP_ID": app["id"],
            "GAR_APP_MANIFEST": str(paths["application"]),
            "GAR_APP_ROOT": str(paths["application"].parent),
            "GAR_APP_ENTRYPOINT_NAME": app["runtime"]["entrypoint"] or "",
            "GAR_APP_INSTALL_DIR": app["runtime"]["install_dir"] or "",
            "GAR_TARGET_ARTIFACT_KIND": profile["artifact"]["kind"],
            "GAR_TARGET_ARTIFACT_MANIFEST": str(paths["artifact_manifest"]),
            "GAR_HARDWARE_BINDING": (
                str(paths["binding"]) if paths["binding"] is not None else ""
            ),
        }
    )
    command = [str(paths["packager"])]
    if arguments.action:
        command.append(arguments.action)
    os.execve(command[0], command, environment)
    return 127


if __name__ == "__main__":
    raise SystemExit(main())


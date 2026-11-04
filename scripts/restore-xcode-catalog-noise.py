#!/usr/bin/env python3
"""Undoes Xcode's rewrite of the String Catalogs, leaving any real edit alone.

Building in the Xcode 27 IDE reformats a catalog, changes extraction states and
adds untranslated keys, which fails LocalizationTests. No build setting stops it.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def is_xcode_noise(head, current):
    def without_state(entry):
        return {key: value for key, value in entry.items() if key != "extractionState"}

    def metadata(catalog):
        return {key: value for key, value in catalog.items() if key != "strings"}

    old, new = head["strings"], current["strings"]
    if metadata(head) != metadata(current) or not old.keys() <= new.keys():
        return False
    if any(without_state(entry) != without_state(new[key]) for key, entry in old.items()):
        return False
    return not any(
        new[key].get("extractionState") == "manual"
        or "es" in new[key].get("localizations", {})
        for key in new.keys() - old.keys()
    )


def git(root, *arguments):
    return subprocess.run(
        ["git", *arguments], cwd=root, capture_output=True, text=True, check=False
    )


def catalogs(root):
    listed = git(root, "ls-files", "--", "Apps/*/Localizable.xcstrings")
    return listed.stdout.split() if listed.returncode == 0 else []


def differs_from_head_only_by_noise(root, path, text):
    head = git(root, "show", f"HEAD:{path}")
    if head.returncode != 0 or head.stdout == text:
        return False
    try:
        return is_xcode_noise(json.loads(head.stdout), json.loads(text))
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        return False


def restore(root):
    for path in catalogs(root):
        if git(root, "diff", "--cached", "--quiet", "--", path).returncode != 0:
            continue
        text = (Path(root) / path).read_text(encoding="utf-8")
        if differs_from_head_only_by_noise(root, path, text):
            git(root, "restore", "--", path)
            print(f"Restored {path}: only Xcode's rewrite had changed it")
    return 0


def check_staged(root):
    status = 0
    for path in catalogs(root):
        staged = git(root, "show", f":{path}")
        if staged.returncode == 0 and differs_from_head_only_by_noise(root, path, staged.stdout):
            print(f"{path} is staged with only Xcode's rewrite. Unstage and restore it:")
            print(f"  git restore --staged --worktree -- {path}")
            status = 1
    return status


def self_test():
    entry = {"localizations": {"es": {"stringUnit": {"value": "Copiar"}}}}
    head = {"sourceLanguage": "en", "version": "1.1", "strings": {"Copy": entry}}

    def changed(strings):
        return {**head, "strings": {**head["strings"], **strings}}

    assert is_xcode_noise(head, changed({"Copy": {**entry, "extractionState": "stale"}}))
    assert is_xcode_noise(head, changed({"%@ clips": {"comment": "A count."}}))
    assert not is_xcode_noise(
        head, changed({"Copy": {"localizations": {"es": {"stringUnit": {"value": "Pegar"}}}}})
    )
    assert not is_xcode_noise(head, {**head, "strings": {}})
    assert not is_xcode_noise(head, changed({"New": entry}))
    assert not is_xcode_noise(head, changed({"New": {"extractionState": "manual"}}))
    assert not is_xcode_noise(head, {**head, "version": "1.2"})

    with tempfile.TemporaryDirectory() as root:
        path = Path(root) / "Apps/GanchoMac/Localizable.xcstrings"
        relative = "Apps/GanchoMac/Localizable.xcstrings"
        path.parent.mkdir(parents=True)
        original = json.dumps(head)
        path.write_text(original, encoding="utf-8")
        git(root, "init", "--quiet")
        git(root, "add", "--", relative)
        git(
            root, "-c", "user.name=test", "-c", "user.email=test@example.com",
            "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "base",
        )

        noise = json.dumps(changed({"%@ clips": {}}), indent=2)
        path.write_text(noise, encoding="utf-8")
        restore(root)
        assert path.read_text(encoding="utf-8") == original

        edit = json.dumps(changed({"New": entry}))
        path.write_text(edit, encoding="utf-8")
        restore(root)
        assert path.read_text(encoding="utf-8") == edit

        path.write_text(noise, encoding="utf-8")
        git(root, "add", "--", relative)
        assert check_staged(root) == 1
        restore(root)
        assert path.read_text(encoding="utf-8") == noise, "a staged change stays"

        git(root, "restore", "--staged", "--worktree", "--", relative)
        path.write_text(edit, encoding="utf-8")
        git(root, "add", "--", relative)
        assert check_staged(root) == 0
    print("Xcode catalog noise self-test passed")
    return 0


def main():
    root = Path(__file__).resolve().parent.parent
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if sys.argv[1:] == ["--check-staged"]:
        return check_staged(root)
    return restore(root)


if __name__ == "__main__":
    sys.exit(main())

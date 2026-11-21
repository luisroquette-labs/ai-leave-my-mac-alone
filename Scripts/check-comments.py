from pathlib import Path
import io
import re
import subprocess
import tokenize


ROOT = Path(__file__).resolve().parents[1]
FILES = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
failures = []


def slash_comments(text, style):
    found = []
    pairs = {"(": ")", "[": "]", "{": "}"}

    def string_at(i):
        raw = re.match(r'#+("""|")', text[i:]) if style == "swift" else None
        hashes = "#" * (len(raw.group(0)) - len(raw.group(1))) if raw else ""
        quote = raw.group(1) if raw else ('"""' if style == "swift" and text.startswith('"""', i) else text[i])
        i += len(hashes) + len(quote)
        while i < len(text):
            if style == "swift" and text.startswith("\\" + hashes + "(", i):
                i = code_at(i + 2 + len(hashes), ")")
            elif style == "js" and quote == "`" and text.startswith("${", i):
                i = code_at(i + 2, "}")
            elif text.startswith(quote + hashes, i):
                return i + len(quote) + len(hashes)
            elif text[i] == "\\" and not hashes:
                i += 2
            else:
                i += 1
        return i

    def regex_at(i):
        i += 1
        in_class = False
        while i < len(text):
            if text[i] == "\\":
                i += 2
            elif text[i] == "[":
                in_class = True
                i += 1
            elif text[i] == "]":
                in_class = False
                i += 1
            elif text[i] == "/" and not in_class:
                return i + 1
            else:
                i += 1
        return i

    def code_at(i, closing=None):
        previous = ""
        while i < len(text):
            char = text[i]
            if closing and char == closing:
                return i + 1
            if closing and char in pairs:
                i = code_at(i + 1, pairs[char])
                previous = ")"
                continue
            if style == "swift" and re.match(r'#+"', text[i:]):
                i = string_at(i)
                previous = '"'
                continue
            if char in ('"', "'", "`"):
                i = string_at(i)
                previous = char
                continue
            if style != "css" and text.startswith("//", i):
                found.append(i)
                end = text.find("\n", i)
                i = len(text) if end < 0 else end + 1
                continue
            if text.startswith("/*", i):
                found.append(i)
                depth = 1
                i += 2
                while i < len(text) and depth:
                    if style == "swift" and text.startswith("/*", i):
                        depth += 1
                        i += 2
                    elif text.startswith("*/", i):
                        depth -= 1
                        i += 2
                    else:
                        i += 1
                continue
            if style == "js" and char == "/" and (
                previous in "=([{:,;!?&|"
                or text[:i].rstrip().endswith("=>")
                or re.search(r"\b(?:return|throw|case|yield|await)\s*$", text[:i])
            ):
                i = regex_at(i)
                previous = "/"
                continue
            if not char.isspace():
                previous = char
            i += 1
        return i

    code_at(0)
    return found


def hash_comments(text):
    found = []
    pos = 0
    for line in text.splitlines(keepends=True):
        quote = ""
        for i, char in enumerate(line):
            if quote:
                if char == quote:
                    quote = ""
            elif char in ("'", '"'):
                quote = char
            elif char == "#" and (i == 0 or line[i - 1].isspace()):
                if not (pos == 0 and line.startswith("#!")):
                    found.append(pos + i)
                break
        pos += len(line)
    return found


assert slash_comments('let url = "https://example.test/path"', "swift") == []
assert len(slash_comments('let value = 1 // comment', "swift")) == 1
assert slash_comments('let text = #"/* literal */"#', "swift") == []
assert hash_comments('#!/bin/sh\necho "# literal"\n# comment\n') == [27]

for name in FILES:
    if not name:
        continue
    path = ROOT / name
    if not path.is_file():
        continue
    text = path.read_text() if path.suffix in {".swift", ".js", ".css", ".html", ".py", ".sh", ".yml", ".yaml"} else ""
    if path.suffix == ".swift":
        offsets = slash_comments(text, "swift")
        if name == "Package.swift" and re.match(r"// swift-tools-version: \d+\.\d+(?:\.\d+)?(?:\n|$)", text):
            offsets = [offset for offset in offsets if offset != 0]
    elif path.suffix == ".js":
        offsets = slash_comments(text, "js")
    elif path.suffix == ".css":
        offsets = slash_comments(text, "css")
    elif path.suffix == ".html":
        offsets = [match.start() for match in re.finditer(r"<!--[\s\S]*?-->", text)]
    elif path.suffix == ".py":
        offsets = [token.start[0] for token in tokenize.generate_tokens(io.StringIO(text).readline) if token.type == tokenize.COMMENT and not (token.start[0] == 1 and token.string.startswith("#!"))]
        failures.extend(f"{name}:{line}" for line in offsets)
        continue
    elif path.suffix in {".sh", ".yml", ".yaml"}:
        offsets = hash_comments(text)
    else:
        continue
    failures.extend(f"{name}:{text.count(chr(10), 0, offset) + 1}" for offset in offsets)

if failures:
    raise SystemExit("Comments are forbidden (baseline: 0):\n" + "\n".join(failures))
print("Comment lint passed (baseline: 0).")

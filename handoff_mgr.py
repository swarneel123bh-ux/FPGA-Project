#!/usr/bin/env python3
"""
Handoff Section Manager (`handoff_mgr.py`) — v3

Addressed-section mutation tool for structured Markdown.

Sections are addressed by an explicit anchor placed under the heading:

    ### Phase 1.5 — Sync-read integration
    <!-- id: phase.1-5 -->

The anchor is invisible when rendered. Heading text becomes purely human-facing
and can be reworded freely; the id is machine-facing and never changes.

Sections without an anchor fall back to their slugified heading path, so a
document can be migrated incrementally. Use `anchor` to add ids in bulk.

Commands:
  tree      hierarchical view with ids and slug paths
  ids       flat id -> heading listing
  validate  duplicate ids, unclosed fences, dangling section cross-references
  anchor    bulk-insert anchors from a two-column map file
  apply     apply a patch file

Patch block format:

  TARGET: <id or slug path>
  ACTION: REPLACE | REPLACE_TREE | APPEND | PREPEND | DELETE | SET
        | INSERT_BEFORE | INSERT_AFTER | INSERT_CHILD
  HEADING: ### New heading text          (optional; SET, REPLACE, INSERT_*)
  ID: new.anchor.id                      (optional; INSERT_*)
  <<<
  content
  >>>

Block markers are exactly three characters. A patch whose markers arrive
mangled is rejected outright rather than repaired — see parse_patch.

Lines outside a block are ignored.
"""

import argparse
import os
import re
import shutil
import sys
from datetime import datetime

HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
ANCHOR_RE = re.compile(r"^\s*<!--\s*id:\s*([A-Za-z0-9._:+-]+)\s*-->\s*$")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
FIELD_RE = re.compile(r"^([A-Z][A-Z0-9_]*):\s?(.*)$")
SECNUM_RE = re.compile(r"^#{1,6}\s+(\d+)\.")
SECREF_RE = re.compile(r"§(\d+)")

ACTIONS = {
  "REPLACE", "REPLACE_TREE", "APPEND", "PREPEND", "DELETE", "SET",
  "INSERT_BEFORE", "INSERT_AFTER", "INSERT_CHILD",
}

# Every action except DELETE must carry an explicit <<< ... >>> body.
MARKER_REQUIRED = ACTIONS - {"DELETE"}

# These additionally refuse an empty body: an empty REPLACE is a wipe, and an
# empty APPEND/SET is a no-op. Both are almost always a mangled patch file.
NONEMPTY_REQUIRED = {"REPLACE", "REPLACE_TREE", "APPEND", "PREPEND", "SET"}

MANGLED_RE = re.compile(r"^\s*(<+|>+)\s*$")


class PatchError(Exception):
  pass


def slugify(text):
  text = re.sub(r"[^\w\s-]", "", text).strip().lower()
  return re.sub(r"[-\s]+", "-", text)


class Node:

  def __init__(self, level, title, raw_line):
    self.level = level
    self.title = title
    self.raw_line = raw_line
    self.anchor_id = None
    self.body_lines = []
    self.children = []
    self.parent = None
    self.path_id = ""

  # ---- identity -----------------------------------------------------------

  @property
  def ref(self):
    return self.anchor_id or self.path_id

  def recompute_paths(self, parent_path=""):
    slug = slugify(self.title) if self.title else ""
    if parent_path and slug:
      self.path_id = parent_path + "/" + slug
    elif slug:
      self.path_id = slug
    else:
      self.path_id = parent_path
    for child in self.children:
      child.recompute_paths(self.path_id)

  def walk(self):
    yield self
    for child in self.children:
      for n in child.walk():
        yield n

  # ---- field block --------------------------------------------------------

  def split_fields(self):
    """Return (ordered field pairs, remaining body lines)."""
    fields = []
    i = 0
    while i < len(self.body_lines):
      m = FIELD_RE.match(self.body_lines[i])
      if not m:
        break
      fields.append([m.group(1), m.group(2)])
      i += 1
    return fields, self.body_lines[i:]

  def set_fields(self, updates):
    fields, rest = self.split_fields()
    for key, value in updates:
      for pair in fields:
        if pair[0] == key:
          pair[1] = value
          break
      else:
        fields.append([key, value])
    lines = ["%s: %s" % (k, v) if v else "%s:" % k for k, v in fields]
    if rest and rest[0].strip():
      lines.append("")
    self.body_lines = lines + rest

  # ---- render -------------------------------------------------------------

  def render(self):
    lines = []
    if self.raw_line:
      lines.append(self.raw_line)
    if self.anchor_id:
      lines.append("<!-- id: %s -->" % self.anchor_id)
    lines.extend(self.body_lines)
    for child in self.children:
      lines.extend(child.render())
    return lines


def build_tree(lines):
  """Parse lines into a Node tree. Fenced code blocks are never scanned."""
  root = Node(0, "ROOT", "")
  stack = [root]
  in_fence = False
  for line in lines:
    if FENCE_RE.match(line):
      in_fence = not in_fence
      stack[-1].body_lines.append(line)
      continue
    if not in_fence:
      m = HEADING_RE.match(line)
      if m:
        level = len(m.group(1))
        node = Node(level, m.group(2).strip(), line)
        while stack[-1].level >= level:
          stack.pop()
        node.parent = stack[-1]
        stack[-1].children.append(node)
        stack.append(node)
        continue
      a = ANCHOR_RE.match(line)
      if (a and stack[-1] is not root and stack[-1].anchor_id is None
          and not stack[-1].body_lines):
        stack[-1].anchor_id = a.group(1)
        continue
    stack[-1].body_lines.append(line)
  return root, in_fence


class DocumentTree:

  def __init__(self, raw_text):
    self.trailing_newline = raw_text.endswith("\n")
    self.root, self.fence_open = build_tree(raw_text.splitlines())
    self.root.recompute_paths()
    self.reindex()

  def reindex(self):
    self.by_anchor = {}
    self.by_path = {}
    self.root.recompute_paths()
    for node in self.root.walk():
      if node is self.root:
        continue
      if node.anchor_id:
        if node.anchor_id in self.by_anchor:
          raise PatchError(
            "duplicate anchor id '%s' — ids must be unique" % node.anchor_id
          )
        self.by_anchor[node.anchor_id] = node
      if node.path_id:
        prev = self.by_path.get(node.path_id)
        if prev is not None and (prev.anchor_id is None or node.anchor_id is None):
          raise PatchError(
            "duplicate slug path '%s' and at least one side has no anchor id; "
            "give both an explicit id or rename one heading" % node.path_id
          )
        self.by_path[node.path_id] = node

  def resolve(self, ref):
    if ref in self.by_anchor:
      return self.by_anchor[ref]
    if ref in self.by_path:
      return self.by_path[ref]
    raise PatchError("target '%s' not found" % ref)

  def resolve_loose(self, key):
    """Exact path, exact anchor, or unique slug-path suffix. For `anchor`."""
    if key in self.by_anchor:
      return self.by_anchor[key]
    if key in self.by_path:
      return self.by_path[key]
    hits = [n for p, n in self.by_path.items()
            if p == key or p.endswith("/" + key)]
    if len(hits) == 1:
      return hits[0]
    if not hits:
      raise PatchError("no section matches '%s'" % key)
    raise PatchError(
      "'%s' is ambiguous, matches %d sections: %s"
      % (key, len(hits), ", ".join(sorted(h.path_id for h in hits)))
    )

  def render(self):
    text = "\n".join(self.root.render())
    return text + "\n" if self.trailing_newline or text else text


# ---- patch parsing --------------------------------------------------------


def parse_patch(path):
  with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

  blocks = []
  cur = None
  in_body = False
  open_at = 0
  lineno = 0
  for line in lines:
    lineno += 1
    if in_body:
      if line.rstrip() == ">>>":
        in_body = False
        continue
      cur["content"].append(line)
      continue

    # Outside a body, a run of angle brackets that is not exactly <<< or >>>
    # is a corrupted delimiter. Refuse the whole patch rather than treat the
    # block as bodyless and silently wipe a section.
    if MANGLED_RE.match(line) and line.strip() not in ("<<<", ">>>"):
      raise PatchError(
        "line %d: malformed delimiter %r \u2014 block markers must be exactly "
        "'<<<' and '>>>'. Refusing to apply; nothing was written."
        % (lineno, line.strip())
      )

    if line.startswith("TARGET:"):
      if cur is not None:
        blocks.append(cur)
      cur = {"target": line[len("TARGET:"):].strip(), "action": None,
             "heading": None, "id": None, "content": [],
             "has_body": False, "line": lineno}
      continue
    if cur is None:
      continue
    if line.startswith("ACTION:"):
      cur["action"] = line[len("ACTION:"):].strip().upper()
    elif line.startswith("HEADING:"):
      cur["heading"] = line[len("HEADING:"):].strip()
    elif line.startswith("ID:"):
      cur["id"] = line[len("ID:"):].strip()
    elif line.rstrip() == "<<<":
      in_body = True
      cur["has_body"] = True
      open_at = lineno

  if in_body:
    raise PatchError(
      "patch ends inside a <<< block opened at line %d \u2014 no closing '>>>'"
      % open_at
    )
  if cur is not None:
    blocks.append(cur)

  for b in blocks:
    if b["action"] not in ACTIONS:
      raise PatchError(
        "line %d: bad or missing ACTION for target '%s' (got %r)"
        % (b["line"], b["target"], b["action"])
      )
    if b["action"] in MARKER_REQUIRED and not b["has_body"]:
      raise PatchError(
        "line %d: %s on '%s' has no '<<<' ... '>>>' body. If the markers were "
        "mangled in transit, fix them \u2014 applying this would destroy the "
        "section." % (b["line"], b["action"], b["target"])
      )
    if b["action"] in NONEMPTY_REQUIRED and not any(
        l.strip() for l in b["content"]):
      raise PatchError(
        "line %d: %s on '%s' has an empty body. Use DELETE to remove a "
        "section." % (b["line"], b["action"], b["target"])
      )
  if not blocks:
    raise PatchError("no mutation blocks found")
  return blocks


# ---- mutation -------------------------------------------------------------


def make_node(heading_line, anchor_id, content):
  m = HEADING_RE.match(heading_line)
  if not m:
    raise PatchError("HEADING must be a markdown heading, got %r" % heading_line)
  node = Node(len(m.group(1)), m.group(2).strip(), heading_line)
  node.anchor_id = anchor_id
  node.body_lines = list(content)
  return node


def apply_block(doc, b):
  action = b["action"]

  if action.startswith("INSERT_"):
    if not b["heading"]:
      raise PatchError("%s on '%s' needs a HEADING:" % (action, b["target"]))
    target = doc.resolve(b["target"])
    node = make_node(b["heading"], b["id"], b["content"])
    if action == "INSERT_CHILD":
      node.parent = target
      target.children.append(node)
    else:
      parent = target.parent
      if parent is None:
        raise PatchError("cannot insert a sibling of the document root")
      idx = parent.children.index(target)
      if action == "INSERT_AFTER":
        idx += 1
      node.parent = parent
      parent.children.insert(idx, node)
    return

  target = doc.resolve(b["target"])

  if action == "DELETE":
    if target.parent is None:
      raise PatchError("cannot delete the document root")
    target.parent.children.remove(target)
    return

  if action == "REPLACE_TREE":
    sub_root, open_fence = build_tree(b["content"])
    if open_fence:
      raise PatchError("REPLACE_TREE content leaves a code fence open")
    if len(sub_root.children) != 1 or sub_root.body_lines:
      raise PatchError(
        "REPLACE_TREE content must be exactly one heading and its subtree"
      )
    new = sub_root.children[0]
    if target.parent is None:
      raise PatchError("cannot REPLACE_TREE the document root")
    idx = target.parent.children.index(target)
    new.parent = target.parent
    target.parent.children[idx] = new
    return

  if b["heading"]:
    m = HEADING_RE.match(b["heading"])
    if not m:
      raise PatchError("HEADING must be a markdown heading")
    if len(m.group(1)) != target.level:
      raise PatchError(
        "HEADING level %d does not match section level %d for '%s'"
        % (len(m.group(1)), target.level, b["target"])
      )
    target.raw_line = b["heading"]
    target.title = m.group(2).strip()

  if action == "SET":
    updates = []
    for line in b["content"]:
      if not line.strip():
        continue
      m = FIELD_RE.match(line)
      if not m:
        raise PatchError("SET content must be KEY: value lines, got %r" % line)
      updates.append((m.group(1), m.group(2)))
    if updates:
      target.set_fields(updates)
  elif action == "REPLACE":
    target.body_lines = list(b["content"])
  elif action == "APPEND":
    target.body_lines.extend(b["content"])
  elif action == "PREPEND":
    target.body_lines = list(b["content"]) + target.body_lines


def bump_revision(text):
  now = datetime.now().strftime("%d %b %Y, %H:%M IST")
  had_newline = text.endswith("\n")
  lines = text.splitlines()
  out = []
  found = False
  for line in lines:
    m = re.match(r"^\*Rev (\d+) — patched .*\*$", line)
    if m and not found:
      out.append("*Rev %d — patched %s*" % (int(m.group(1)) + 1, now))
      found = True
    else:
      out.append(line)
  if not found:
    final = []
    inserted = False
    for line in out:
      final.append(line)
      if not inserted and line.startswith("# "):
        final.append("")
        final.append("*Rev 1 — patched %s*" % now)
        inserted = True
    out = final
  text = "\n".join(out)
  return text + "\n" if had_newline else text


def backup(path):
  stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
  base, ext = os.path.splitext(path)
  dest = "%s_%s%s" % (base, stamp, ext)
  shutil.copyfile(path, dest)
  return dest


def load(path):
  with open(path, "r", encoding="utf-8") as f:
    return DocumentTree(f.read())


# ---- commands -------------------------------------------------------------


def cmd_tree(args):
  doc = load(args.file)

  def show(node, depth=0):
    for child in node.children:
      tag = child.anchor_id or "(no id: %s)" % child.path_id
      print("%s%s  %s" % ("  " * depth, tag, child.title))
      show(child, depth + 1)

  print("Sections in %s\n" % args.file)
  show(doc.root)


def cmd_ids(args):
  doc = load(args.file)
  rows = [(n.anchor_id or "-", n.path_id, n.title)
          for n in doc.root.walk() if n is not doc.root]
  width = max([len(r[0]) for r in rows] + [2])
  for anchor, path, title in rows:
    print("%-*s  %s" % (width, anchor, title if anchor != "-" else path))


def cmd_validate(args):
  doc = load(args.file)
  problems = []
  if doc.fence_open:
    problems.append("a code fence is opened and never closed")

  missing_ids = [n.path_id for n in doc.root.walk()
                 if n is not doc.root and not n.anchor_id]

  numbers = set()
  for n in doc.root.walk():
    m = SECNUM_RE.match(n.raw_line or "")
    if m:
      numbers.add(m.group(1))
  refs = set()
  for n in doc.root.walk():
    for line in n.body_lines:
      refs.update(SECREF_RE.findall(line))
  dangling = sorted(refs - numbers, key=int)
  if dangling:
    problems.append("cross-references to sections that do not exist: "
                    + ", ".join("§" + d for d in dangling))

  total = len(list(doc.root.walk())) - 1
  print("%d sections, %d with explicit ids" % (total, total - len(missing_ids)))
  if missing_ids:
    print("%d sections still addressed by slug path:" % len(missing_ids))
    for p in missing_ids:
      print("  " + p)
  for p in problems:
    print("PROBLEM: " + p, file=sys.stderr)
  if problems:
    sys.exit(1)
  print("OK")


def cmd_anchor(args):
  doc = load(args.file)
  pairs = []
  with open(args.map, "r", encoding="utf-8") as f:
    for raw in f:
      line = raw.split("#", 1)[0].strip()
      if not line:
        continue
      parts = line.split()
      if len(parts) != 2:
        raise PatchError("bad map line: %r (expected '<key> <id>')" % raw.strip())
      pairs.append((parts[0], parts[1]))

  seen = set()
  planned = []
  for key, new_id in pairs:
    if new_id in seen:
      raise PatchError("id '%s' assigned twice in the map" % new_id)
    seen.add(new_id)
    planned.append((doc.resolve_loose(key), new_id))

  for node, new_id in planned:
    node.anchor_id = new_id
  doc.reindex()

  if args.dry_run:
    print("would anchor %d sections; no changes written" % len(planned))
    return
  dest = backup(args.file)
  with open(args.file, "w", encoding="utf-8") as f:
    f.write(doc.render())
  print("anchored %d sections. backup at '%s'" % (len(planned), dest))


def cmd_apply(args):
  doc = load(args.file)
  blocks = parse_patch(args.patch)

  # Resolve every target up front so the run is all-or-nothing.
  for b in blocks:
    doc.resolve(b["target"])

  for b in blocks:
    apply_block(doc, b)

  doc.reindex()
  text = bump_revision(doc.render())

  if args.dry_run:
    print("%d mutation(s) would apply cleanly; no changes written" % len(blocks))
    return
  dest = backup(args.file)
  with open(args.file, "w", encoding="utf-8") as f:
    f.write(text)
  print("applied %d mutation(s). backup at '%s'" % (len(blocks), dest))


def main():
  p = argparse.ArgumentParser(description="Addressed section manager.")
  sub = p.add_subparsers(dest="command", required=True)

  t = sub.add_parser("tree", help="hierarchical section view")
  t.add_argument("file")
  t.set_defaults(func=cmd_tree)

  i = sub.add_parser("ids", help="flat id listing")
  i.add_argument("file")
  i.set_defaults(func=cmd_ids)

  v = sub.add_parser("validate", help="check ids, fences, cross-references")
  v.add_argument("file")
  v.set_defaults(func=cmd_validate)

  a = sub.add_parser("anchor", help="bulk-insert anchors from a map file")
  a.add_argument("file")
  a.add_argument("map")
  a.add_argument("--dry-run", action="store_true")
  a.set_defaults(func=cmd_anchor)

  ap = sub.add_parser("apply", help="apply a patch file")
  ap.add_argument("file")
  ap.add_argument("patch")
  ap.add_argument("--dry-run", action="store_true")
  ap.set_defaults(func=cmd_apply)

  args = p.parse_args()
  try:
    args.func(args)
  except PatchError as e:
    print("error: %s" % e, file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
  main()

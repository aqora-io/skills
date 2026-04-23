#!/usr/bin/env bash
# Validate skill layout and frontmatter against the repo's authoring rules.
# Exits non-zero on any violation. Runs in CI and locally.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
skills_dir="$repo_root/skills"

errors=0

error() {
  echo "ERROR: $*" >&2
  errors=$((errors + 1))
}

if [[ ! -d "$skills_dir" ]]; then
  echo "No skills/ directory at $skills_dir" >&2
  exit 1
fi

name_regex='^[a-z0-9]+(-[a-z0-9]+)*$'
found_any=false

for skill_dir in "$skills_dir"/*/; do
  [[ -d "$skill_dir" ]] || continue
  found_any=true
  skill_dir="${skill_dir%/}"
  skill_name="$(basename "$skill_dir")"
  skill_md="$skill_dir/SKILL.md"

  if [[ ! -f "$skill_md" ]]; then
    error "$skill_name: missing SKILL.md"
    continue
  fi

  # Extract YAML frontmatter between first pair of --- lines
  frontmatter=$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2) exit; next} c==1{print}' "$skill_md")

  fm_name=$(printf '%s\n' "$frontmatter" | awk -F':[ \t]*' '/^name:/{print $2; exit}' | sed -e 's/^["'\'']//' -e 's/["'\'']$//')
  fm_desc=$(printf '%s\n' "$frontmatter" | awk '/^description:/{sub(/^description:[ \t]*/,""); print; exit}' | sed -e 's/^["'\'']//' -e 's/["'\'']$//')

  if [[ -z "$fm_name" ]]; then
    error "$skill_name: SKILL.md missing 'name' frontmatter field"
  else
    if [[ "$fm_name" != "$skill_name" ]]; then
      error "$skill_name: frontmatter name '$fm_name' does not match directory '$skill_name'"
    fi
    if [[ ! "$fm_name" =~ $name_regex ]]; then
      error "$skill_name: name '$fm_name' does not match regex '$name_regex'"
    fi
    if [[ ${#fm_name} -gt 64 ]]; then
      error "$skill_name: name '$fm_name' exceeds 64 characters"
    fi
  fi

  if [[ -z "$fm_desc" ]]; then
    error "$skill_name: SKILL.md missing 'description' frontmatter field"
  elif [[ ${#fm_desc} -gt 1024 ]]; then
    error "$skill_name: description exceeds 1024 characters (got ${#fm_desc})"
  fi

  # Check that markdown links to reference files resolve
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if [[ ! -f "$skill_dir/$ref" ]]; then
      error "$skill_name: broken link in SKILL.md to $ref"
    fi
  done < <(grep -oE '\(references?/[^)]+\)' "$skill_md" | sed -e 's/^(//' -e 's/)$//' || true)

  echo "OK: $skill_name"
done

if [[ "$found_any" != true ]]; then
  error "no skills found under $skills_dir"
fi

if [[ $errors -gt 0 ]]; then
  echo
  echo "Validation failed with $errors error(s)." >&2
  exit 1
fi

echo
echo "All skills validated."

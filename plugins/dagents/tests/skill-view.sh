# Sourced by pin tests after they set P (the plugin root) and SKILL_VIEW_DIR (a
# directory the test creates and removes). skill_view SKILL prints the path of
# a file named SKILL.md that holds the skill's SKILL.md followed by every file
# of its references/, so a pin finds text a split moved out of SKILL.md.
skill_view() {
  mkdir -p "$SKILL_VIEW_DIR/$1"
  cat "$P/skills/$1/SKILL.md" "$P/skills/$1"/references/*.md > "$SKILL_VIEW_DIR/$1/SKILL.md"
  printf '%s\n' "$SKILL_VIEW_DIR/$1/SKILL.md"
}

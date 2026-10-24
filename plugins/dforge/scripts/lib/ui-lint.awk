function hit(rule, msg) { printf "%s:%d: %s %s\n", f, FNR, rule, msg }
kind == "web" {
  line = $0
  if (line ~ /focus-visible/) focusvis = 1
  # The boundary before the property name skips a custom property such as
  # --brand-color, which defines a token wherever it sits on the line.
  if (!token &&
      (line ~ /(^|[^A-Za-z0-9_-])(color|background|fill|stroke|border|shadow|outline)[A-Za-z-]*["']?[ \t]*[:=][^;]*(#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*([^0-9a-zA-Z_-]|$)|rgba?\(|hsla?\()/ ||
       line ~ /-\[(#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]|rgba?\(|hsla?\()/))
    hit("raw-color", "raw colour value; use the design system token")
  if (line ~ /outline[ \t]*:[ \t]*(none|0)([ \t;!]|$)/ || line ~ /(^|[ "'`])outline-none([ "'`]|$)/) outl[FNR] = 1
  if (line ~ /<(div|span|li|td|p|img|section|article)[ \t][^>]*(onClick=|@click=|on:click=|v-on:click=)/ &&
      line !~ /role=/ && line !~ /(onKeyDown|onKeyUp|onKeyPress|@keydown|@keyup|on:keydown|on:keyup)/)
    hit("click-non-interactive", "click handler on a non-interactive element without a role and a key handler; use a button")
  if (line ~ /<img[ \t]/ && line ~ /<img[^>]*>/ && line !~ /<img[^>]*[ \t]alt=/) hit("img-alt", "image without alt text")
  if (line ~ /transition[ \t]*:[ \t]*all([ \t;]|$)/ || line ~ /(^|[ "'`])transition-all([ "'`]|$)/)
    hit("transition-all", "transition: all animates layout properties; name the properties")
  if (line ~ /user-scalable[ \t]*=[ \t]*(no|0)/ || line ~ /maximum-scale[ \t]*=[ \t]*1(\.0)?([^0-9.]|$)/)
    hit("zoom-disabled", "the viewport blocks zoom")
  if (line ~ /tab[Ii]ndex[ \t]*=[ \t]*[{"']*[ \t]*[1-9]/) hit("tabindex-positive", "a positive tabIndex breaks the natural focus order")
  if ((line ~ /onPaste=/ && line ~ /preventDefault/) || line ~ /@paste\.prevent/ || line ~ /on:paste\|preventDefault/)
    hit("paste-blocked", "blocking paste stops password managers and assistive input")
}
kind == "xaml" {
  if ($0 ~ /(Foreground|Background|Fill|Stroke|BorderBrush)="#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/)
    hit("xaml-hardcoded-brush", "hard-coded brush; use a ThemeResource or StaticResource")
}
kind == "android" {
  if ($0 ~ /android:(textColor|background|tint|backgroundTint)="#/) hit("android-hardcoded-color", "hard-coded colour; use @color/ or a theme attribute")
  if ($0 ~ /android:(text|hint|contentDescription)="[^@?"]/) hit("android-hardcoded-text", "hard-coded text; use a @string/ resource")
  if ($0 ~ /<(ImageView|ImageButton)([ \t>\/]|$)/) { inimg = 1; imgline = FNR; desc = 0 }
  if (inimg && $0 ~ /android:contentDescription=|android:importantForAccessibility="no"/) desc = 1
  if (inimg && $0 ~ />/) {
    if (!desc) printf "%s:%d: %s %s\n", f, imgline, "android-image-description", "image without contentDescription"
    inimg = 0
  }
}
END {
  if (!focusvis) for (n in outl) printf "%s:%d: %s %s\n", f, n, "outline-removed", "focus outline removed with no :focus-visible replacement"
}

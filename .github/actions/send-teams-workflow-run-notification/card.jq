def optional($v; item): if $v == "" then [] else [item] end;
def trim: gsub("^\\s+|\\s+$"; "");
def lines: split("\n") | map(trim) | map(select(. != ""));

# One bullet per job so the list stays readable past the two or three a FactSet row can hold.
($failed_jobs | lines
  | map("- " + gsub("(?<c>[\\\\\\[\\]*`_])"; "\\\(.c)"))
  | if length == 0 then "- none reported" else join("\n") end) as $jobs
| ($facts | lines
  | map(split("|") | {title: (.[0] | trim), value: (.[1:] | join("|") | trim)})) as $extra_facts
| [
    {type: "ColumnSet", columns: [
      {type: "Column", width: "auto", items: [
        {type: "TextBlock", text: "🔴", size: "large", spacing: "none"}]},
      {type: "Column", width: "stretch", items: (
        optional($title; {type: "TextBlock", text: $title, size: "large", weight: "bolder", wrap: true, spacing: "none"})
        + optional($subtitle; {type: "TextBlock", text: $subtitle, isSubtle: true, wrap: true, spacing: "none"}))}]},
    {type: "TextBlock", spacing: "medium", wrap: true,
     text: ([$headline, $message] | map(trim) | map(select(. != "")) | join(" "))},
    {type: "FactSet", spacing: "medium", facts: ([
      {title: "Repository", value: $repository},
      {title: "Branch", value: $branch},
      {title: "Workflow", value: $workflow},
      {title: "Attempt", value: $attempts}] + $extra_facts)},
    {type: "Container", spacing: "medium", items: [
      {type: "TextBlock", text: "Failed jobs", weight: "bolder", spacing: "none"},
      {type: "TextBlock", wrap: true, spacing: "small", text: $jobs}]}
  ]
  + optional($footer; {type: "TextBlock", spacing: "medium", wrap: true, isSubtle: true, text: $footer})

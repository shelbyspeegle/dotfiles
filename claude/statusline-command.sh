#!/usr/bin/env bash
# Claude Code status line — mirrors oh-my-posh mytheme.omp.json style
# Receives JSON on stdin

input=$(cat)

# Pull every field in ONE jq pass and split on US (\037). US (not TAB) because
# TAB is IFS-whitespace — `read` would collapse empty fields and shift the rest.
IFS=$'\037' read -r cwd model used_pct total_in total_out git_worktree cost_usd effort < <(
  printf '%s' "$input" | jq -r '
    [ (.workspace.current_dir // .cwd // ""),
      (.model.display_name // ""),
      (.context_window.used_percentage // ""),
      (.context_window.total_input_tokens // ""),
      (.context_window.total_output_tokens // ""),
      (.workspace.git_worktree // ""),
      (.cost.total_cost_usd // ""),
      (.effort.level // "") ]
    | map(tostring) | join("")')

# Show only the portion after "source/", or indicate we're outside it
if [[ "$cwd" == *"/source/"* ]]; then
  short_path="${cwd#*/source/}"
  # Treat `~/source/ir/` as a transparent container — its children are the real repos.
  if [[ "$short_path" == "ir" || "$short_path" == "ir/"* ]]; then
    short_path="${short_path#ir}"
    short_path="${short_path#/}"
  fi
  repo="${short_path%%/*}"
  rest="${short_path#*/}"
  if [[ "$rest" == "$repo" ]]; then
    short_path="${repo}"
  elif [[ "$rest" == *".claude/worktrees"* ]]; then
    # Inside a worktree path — show only the repo name; worktree label comes from git_worktree
    short_path="${repo}"
  else
    short_path="${repo}/${rest}"
  fi
elif [[ "$cwd" == */source ]]; then
  short_path=""
else
  short_path="[not in source]"
fi

# Git branch and status (using cwd from JSON for reliability)
git_branch=""
git_ahead=0
git_behind=0
git_staged=0
git_unstaged=0
git_untracked=0
if [ -n "$cwd" ]; then
  git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$git_branch" = "HEAD" ]; then
    # Detached HEAD — show the short SHA rather than the literal "HEAD".
    git_branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$git_branch" ]; then
    # Unpushed-commit count. Prefer ahead-of-upstream; if no upstream is set,
    # fall back to commits not reachable from any remote-tracking branch.
    git_ahead=$(git -C "$cwd" rev-list --count "@{u}..HEAD" 2>/dev/null)
    if [ -z "$git_ahead" ]; then
      if [ -n "$(git -C "$cwd" for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | head -1)" ]; then
        git_ahead=$(git -C "$cwd" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
      else
        git_ahead=0
      fi
    fi
    # How far behind the default branch (main/master) we are. Prefer the remote-tracking
    # ref so we reflect what's on the server, not just local. Skip when HEAD is the base.
    # Resolve the repo's real default branch from origin/HEAD when it's configured
    # (handles develop/trunk/etc.), falling back to probing the usual names.
    base_ref=$(git -C "$cwd" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)
    if [ -z "$base_ref" ]; then
      for candidate in origin/main origin/master main master; do
        if git -C "$cwd" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
          base_ref="$candidate"
          break
        fi
      done
    fi
    if [ -n "$base_ref" ] && [ "$git_branch" != "${base_ref#origin/}" ]; then
      git_behind=$(git -C "$cwd" rev-list --count "HEAD..$base_ref" 2>/dev/null || echo 0)
    fi
    # Porcelain v1: XY PATH — parse staged/unstaged/untracked counts
    while IFS= read -r line; do
      x="${line:0:1}"
      y="${line:1:1}"
      if [ "$x" = "?" ] && [ "$y" = "?" ]; then
        git_untracked=$((git_untracked + 1))
      else
        [ "$x" != " " ] && [ "$x" != "?" ] && git_staged=$((git_staged + 1))
        [ "$y" != " " ] && [ "$y" != "?" ] && git_unstaged=$((git_unstaged + 1))
      fi
    done < <(git -C "$cwd" status --porcelain 2>/dev/null)
  fi
fi

# Token total (input + output for session)
tok_display=""
if [ -n "$total_in" ] && [ -n "$total_out" ]; then
  total_tok=$((total_in + total_out))
  if [ "$total_tok" -ge 1000 ]; then
    tok_display=$(awk "BEGIN { printf \"%.1fk\", $total_tok/1000 }")
  else
    tok_display="$total_tok"
  fi
fi

# Build parts
parts=""
worktree_icon=$'\U000F0405'

# Shorten a branch name:
#   - Linear convention `<team>-<NUM>` (e.g. `eng-123`, possibly under a `user/` prefix) → `TEAM-NUM`
#     (excludes `sc-NNNNN` — that's Shortcut, not Linear, and is shown in full)
#   - Otherwise, if longer than 48 chars, truncate at end
shorten_branch() {
  local name="$1"
  if [[ "$name" =~ (^|/)([a-z]{2,5})-([0-9]+) ]] && [ "${BASH_REMATCH[2]}" != "sc" ]; then
    local team="${BASH_REMATCH[2]}"
    local num="${BASH_REMATCH[3]}"
    printf '%s-%s' "$(echo "$team" | tr '[:lower:]' '[:upper:]')" "$num"
    return
  fi
  if [ "${#name}" -gt 48 ]; then
    printf '%s…' "${name:0:47}"
    return
  fi
  printf '%s' "$name"
}

# ---- CI / MR-PR status (#6) ----------------------------------------------
# Renders the current branch's pipeline/check status as e.g. `!4505 ✓`.
# The render path NEVER touches the network: it only reads a cache file.
# When that cache is older than CI_TTL, a detached background job refreshes it.
CI_CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-ci"
CI_TTL=45        # seconds before a refresh is kicked off
CI_LOCK_TTL=30   # seconds a refresh lock is honored (self-heals if a fetch dies)

# Cache key from cwd + branch (no subshell — pure param expansion).
ci_cache_file=""
if [ -n "$git_branch" ] && [ -n "$cwd" ]; then
  _ci_raw="${cwd//\//_}__${git_branch//\//_}"
  ci_cache_file="$CI_CACHE_DIR/${_ci_raw//[^A-Za-z0-9_.-]/_}"
fi

# Background refresh — writes "host<TAB>kind<TAB>number<TAB>state<TAB>url".
# state is normalized to: passed|failed|running|pending|canceled|skipped|none
refresh_ci() {
  cd "$cwd" 2>/dev/null || return
  mkdir -p "$CI_CACHE_DIR" 2>/dev/null
  local remote host="" kind="" number="" state="none" url=""
  local sc_id="" sc_url="" mr_title=""
  remote=$(git remote get-url origin 2>/dev/null)
  case "$remote" in
    *github.com*) host="github" ;;
    *gitlab.com*) host="gitlab" ;;
  esac

  if [ "$host" = "gitlab" ] && command -v glab >/dev/null 2>&1; then
    local cs raw src="" mrjson
    cs=$(timeout 12 glab ci status 2>/dev/null)
    raw=$(printf '%s\n' "$cs" | sed -n 's/^Pipeline state: //p' | head -1)
    url=$(printf '%s\n' "$cs" | grep -o 'https://[^ ]*/pipelines/[0-9]*' | head -1)
    mrjson=$(timeout 12 glab mr view --output json 2>/dev/null)
    # Agent worktrees carry a mangled `worktree-…` local branch with no matching
    # remote MR/pipeline, so glab's current-branch lookups above come back empty.
    # Fall back to the upstream tracking branch (the real remote source branch).
    if { [ -z "$mrjson" ] || [ -z "$raw" ]; } && command -v jq >/dev/null 2>&1; then
      src=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null); src=${src#*/}
      if [ -n "$src" ]; then
        [ -z "$mrjson" ] && mrjson=$(timeout 12 glab mr list --source-branch "$src" --output json 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null)
        if [ -z "$raw" ]; then
          local pj; pj=$(timeout 12 glab api "projects/:id/pipelines?ref=$src&per_page=1" 2>/dev/null | jq -r '.[0] // empty' 2>/dev/null)
          if [ -n "$pj" ]; then
            raw=$(printf '%s' "$pj" | jq -r '.status // empty' 2>/dev/null)
            local pu; pu=$(printf '%s' "$pj" | jq -r '.web_url // empty' 2>/dev/null)
            [ -n "$pu" ] && url="$pu"
          fi
        fi
      fi
    fi
    case "$raw" in
      success)                 state="passed" ;;
      failed)                  state="failed" ;;
      running)                 state="running" ;;
      pending|created|scheduled|manual|waiting_for_resource) state="pending" ;;
      canceled|cancelled)      state="canceled" ;;
      skipped)                 state="skipped" ;;
      *)                       state="${raw:-none}" ;;
    esac
    if [ -n "$mrjson" ] && command -v jq >/dev/null 2>&1; then
      number=$(printf '%s' "$mrjson" | jq -r '.iid // empty' 2>/dev/null)
      local wu; wu=$(printf '%s' "$mrjson" | jq -r '.web_url // empty' 2>/dev/null)
      [ -n "$wu" ] && url="$wu"
      [ -n "$number" ] && kind="mr"
      # Ticket line data: MR title is the description text; pull the Shortcut
      # story id + URL out of the MR description (the /ir-mr header blockquote).
      mr_title=$(printf '%s' "$mrjson" | jq -r '.title // empty' 2>/dev/null)
      local mr_desc; mr_desc=$(printf '%s' "$mrjson" | jq -r '.description // empty' 2>/dev/null)
      sc_url=$(printf '%s' "$mr_desc" | grep -oE 'https://app\.shortcut\.com/[^ )]*/story/[0-9]+' | head -1)
      sc_id=$(printf '%s' "$mr_desc" | grep -oE 'sc-[0-9]+' | head -1)
    fi

  elif [ "$host" = "github" ] && command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local prjson
    prjson=$(timeout 12 gh pr view --json number,state,url,statusCheckRollup 2>/dev/null)
    if [ -n "$prjson" ]; then
      kind="pr"
      number=$(printf '%s' "$prjson" | jq -r '.number // empty')
      url=$(printf '%s' "$prjson" | jq -r '.url // empty')
      state=$(printf '%s' "$prjson" | jq -r '
        (.statusCheckRollup // []) as $c
        | if ($c|length)==0 then "none"
          elif any($c[]; ((.status // "")|ascii_upcase) as $s | $s=="IN_PROGRESS" or $s=="QUEUED" or $s=="PENDING" or $s=="WAITING" or $s=="REQUESTED") then "running"
          elif any($c[]; ((.conclusion // .state // "")|ascii_upcase) as $x | $x=="FAILURE" or $x=="ERROR" or $x=="CANCELLED" or $x=="TIMED_OUT" or $x=="ACTION_REQUIRED") then "failed"
          else "passed" end')
    else
      # No PR for this branch — fall back to the latest workflow run.
      local runjson
      runjson=$(timeout 12 gh run list --branch "$git_branch" --limit 1 --json status,conclusion,url 2>/dev/null)
      if [ -n "$runjson" ] && [ "$runjson" != "[]" ]; then
        state=$(printf '%s' "$runjson" | jq -r '.[0] | if (.status|ascii_downcase)!="completed" then "running" elif (.conclusion|ascii_downcase)=="success" then "passed" else "failed" end')
        url=$(printf '%s' "$runjson" | jq -r '.[0].url // empty')
        kind="run"
      fi
    fi
  fi

  # Pre-MR fallback: if no MR gave us a story id, derive one from the branch,
  # then fetch the Shortcut story name so the ticket line has a description
  # even before an MR exists. Needs a read-only Shortcut REST token, resolved
  # from (in order) $SHORTCUT_API_TOKEN, ~/.claude/shortcut-token, or the macOS
  # Keychain (generic password, service "andon-shortcut"). Degrades to no
  # title when absent. The story-title text rides in the same `mr_title` field.
  if [ -z "$sc_id" ] && [[ "$git_branch" =~ sc-[0-9]+ ]]; then
    sc_id="${BASH_REMATCH[0]}"
    sc_url="https://app.shortcut.com/idearoominc/story/${sc_id#sc-}"
  fi
  if [ -z "$mr_title" ] && [ -n "$sc_id" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local sc_token="$SHORTCUT_API_TOKEN"
    [ -z "$sc_token" ] && [ -f "$HOME/.claude/shortcut-token" ] && sc_token=$(head -1 "$HOME/.claude/shortcut-token" 2>/dev/null)
    if [ -z "$sc_token" ] && command -v security >/dev/null 2>&1; then
      sc_token=$(security find-generic-password -w -s andon-shortcut -a "$USER" 2>/dev/null)
    fi
    if [ -n "$sc_token" ]; then
      local sc_json
      sc_json=$(timeout 8 curl -s -H "Shortcut-Token: $sc_token" \
        "https://api.app.shortcut.com/api/v3/stories/${sc_id#sc-}" 2>/dev/null)
      [ -n "$sc_json" ] && mr_title=$(printf '%s' "$sc_json" | jq -r '.name // empty' 2>/dev/null)
      # Keep it tidy — long story names would blow out the status line.
      [ "${#mr_title}" -gt 60 ] && mr_title="${mr_title:0:59}…"
    fi
  fi

  # Use US (\037) as the delimiter, not TAB: TAB is IFS-whitespace and `read`
  # would collapse consecutive empties, shifting fields into the wrong vars.
  printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
    "$host" "$kind" "$number" "$state" "$url" "$sc_id" "$sc_url" "$mr_title" \
    > "$ci_cache_file.tmp" 2>/dev/null && mv -f "$ci_cache_file.tmp" "$ci_cache_file" 2>/dev/null
  rm -f "$ci_cache_file.lock" 2>/dev/null
}

# Turn a cached record into a colored, clickable segment.
format_ci() {
  local kind="$2" number="$3" state="$4" url="$5"
  if { [ -z "$state" ] || [ "$state" = "none" ]; } && [ -z "$number" ]; then
    return
  fi
  local icon color
  case "$state" in
    passed)   icon=$'\xe2\x9c\x93'; color=$'\033[32m' ;;  # ✓ green
    failed)   icon=$'\xe2\x9c\x97'; color=$'\033[31m' ;;  # ✗ red
    running)  icon=$'\xe2\x97\x8f'; color=$'\033[36m' ;;  # ● cyan
    pending)  icon=$'\xe2\x97\x8b'; color=$'\033[33m' ;;  # ○ yellow
    canceled) icon=$'\xe2\x8a\x98'; color=$'\033[90m' ;;  # ⊘ gray
    skipped)  icon=$'\xc2\xbb';     color=$'\033[90m' ;;  # » gray
    *)        icon=$'\xe2\x80\xa2'; color=$'\033[90m' ;;  # • gray/unknown
  esac
  local pfx=""
  case "$kind" in
    mr) [ -n "$number" ] && pfx="!$number" ;;
    pr|run) [ -n "$number" ] && pfx="#$number" ;;
  esac
  local lo="" lc=""
  if [ -n "$url" ]; then lo=$'\033]8;;'"$url"$'\033\\'; lc=$'\033]8;;\033\\'; fi
  if [ -n "$pfx" ]; then
    printf '%s%s%s%s %s\033[0m' "$color" "$lo" "$pfx" "$lc" "$icon"
  else
    printf '%s%s%s%s\033[0m' "$color" "$lo" "$icon" "$lc"
  fi
}

# Accent color (#E7698E) — Shelby's pink/magenta. Reused wherever we want the brand pink.
ACCENT_PINK=$'\033[38;2;231;105;142m'

# Path segment (Claude orange #D97757), with optional worktree icon in cyan (icon-only — name is redundant with branch)
CLAUDE_ORANGE=$'\033[38;2;217;119;87m'
if [ -n "$short_path" ]; then
  if [ -n "$git_worktree" ]; then
    parts=$(printf '%s%s\033[0m \033[32m%s\033[0m' "$CLAUDE_ORANGE" "$short_path" "$worktree_icon")
  else
    parts=$(printf '%s%s\033[0m' "$CLAUDE_ORANGE" "$short_path")
  fi
fi

# Git branch segment (light magenta, slightly dimmer — 35m = magenta)
SEP=$'\xe2\x94\x82'
if [ -n "$git_branch" ]; then
  display_branch=$(shorten_branch "$git_branch")
  # Brand-color the branch when it matches a known ticket convention, and wrap clickable
  # OSC 8 hyperlinks where we can resolve a ticket URL.
  link_open=""
  link_close=""
  if [[ "$git_branch" =~ (^|/)([a-z]{2,5})-([0-9]+) ]] && [ "${BASH_REMATCH[2]}" != "sc" ]; then
    branch_color=$'\033[38;2;244;245;248m'
  else
    branch_color="$ACCENT_PINK"
  fi
  git_status_str=$(printf '%s%s %s%s%s\033[0m \033[90m%s\033[0m' "$branch_color" $'\U000F062C' "$link_open" "$display_branch" "$link_close" "$SEP")
  [ "$git_ahead" -gt 0 ]     && git_status_str=$(printf '%s \033[36m%s%d\033[0m' "$git_status_str" $'\xe2\x86\x91' "$git_ahead")
  [ "$git_behind" -gt 0 ]    && git_status_str=$(printf '%s '"$ACCENT_PINK"'%s%d\033[0m' "$git_status_str" $'\xe2\x86\x93' "$git_behind")
  [ "$git_staged" -gt 0 ]    && git_status_str=$(printf '%s \033[32mS:%d\033[0m' "$git_status_str" "$git_staged")
  [ "$git_unstaged" -gt 0 ]  && git_status_str=$(printf '%s \033[33mM:%d\033[0m' "$git_status_str" "$git_unstaged")
  [ "$git_untracked" -gt 0 ] && git_status_str=$(printf '%s \033[31mU:%d\033[0m' "$git_status_str" "$git_untracked")
  if [ "$git_staged" -eq 0 ] && [ "$git_unstaged" -eq 0 ] && [ "$git_untracked" -eq 0 ]; then
    git_status_str=$(printf '%s \033[32m\xe2\x9c\x93 clean\033[0m' "$git_status_str")
  fi
  parts=$(printf '%s \033[90m%s\033[0m %s' "$parts" "$SEP" "$git_status_str")
else
  no_repo_str=$(printf '\033[90m%s no repo\033[0m' $'\U000F062C')
  if [ -n "$parts" ]; then
    parts=$(printf '%s \033[90m%s\033[0m %s' "$parts" "$SEP" "$no_repo_str")
  else
    parts="$no_repo_str"
  fi
fi

# CI / MR-PR segment (#6) — read-only render; kick a detached refresh if stale.
if [ -n "$ci_cache_file" ]; then
  now=$(date +%s)
  cache_mtime=0
  [ -f "$ci_cache_file" ] && cache_mtime=$(stat -f %m "$ci_cache_file" 2>/dev/null || echo 0)
  if [ "$(( now - cache_mtime ))" -ge "$CI_TTL" ]; then
    lock="$ci_cache_file.lock"
    lock_mtime=0
    [ -f "$lock" ] && lock_mtime=$(stat -f %m "$lock" 2>/dev/null || echo 0)
    if [ "$(( now - lock_mtime ))" -ge "$CI_LOCK_TTL" ]; then
      mkdir -p "$CI_CACHE_DIR" 2>/dev/null
      : > "$lock" 2>/dev/null
      { refresh_ci; } >/dev/null 2>&1 &
    fi
  fi
  if [ -f "$ci_cache_file" ]; then
    IFS=$'\037' read -r ci_host ci_kind ci_number ci_state ci_url ci_sc_id ci_sc_url ci_title < "$ci_cache_file"
    # ci_segment is the line-1 fallback (`!N ✓`). It's only appended to line 1
    # when the MR link is NOT relocated onto the ticket line (decided below).
    ci_segment=$(format_ci "$ci_host" "$ci_kind" "$ci_number" "$ci_state" "$ci_url")
  fi
fi

# ---- Ticket line (top) ----------------------------------------------------
# Top line groups the work context:  📌 <story> · <MR/PR ✓> · <description>
# Story id comes from the linked MR (cached with the CI data above), falling
# back to an sc-NNNNN in the branch name. The MR/PR number is relocated here
# from line 1 (with its pipeline status glyph); line 1 keeps it only when there
# is no ticket line to host it. Links are #B0B9F9, underlined, OSC-8 clickable;
# SGR is emitted before the OSC-8 open (the ordering terminals reliably link).
LINK=$'\033[38;2;176;185;249m'
ticket_line=""
mr_on_ticket=""
tk_id="$ci_sc_id"
tk_url="$ci_sc_url"
tk_title="$ci_title"
if [ -z "$tk_id" ] && [[ "$git_branch" =~ sc-[0-9]+ ]]; then
  tk_id="${BASH_REMATCH[0]}"
  tk_url="https://app.shortcut.com/idearoominc/story/${tk_id#sc-}"
fi
if [ -n "$tk_id" ]; then
  # Story id link. OSC-8 with a BEL (\a) terminator — the exact form the Claude
  # Code statusline docs document, and what the VS Code extension's ANSI parser
  # expects (the ST terminator did not render as clickable here).
  tk_lo=""; tk_lc=""
  if [ -n "$tk_url" ]; then tk_lo=$'\033]8;;'"$tk_url"$'\a'; tk_lc=$'\033]8;;\a'; fi
  id_link=$(printf '%s\033[4m%s%s%s\033[0m' "$LINK" "$tk_lo" "$tk_id" "$tk_lc")

  # MR/PR link relocated from line 1, plus its pipeline status glyph.
  mr_seg=""
  mr_pfx=""
  case "$ci_kind" in
    mr)     [ -n "$ci_number" ] && mr_pfx="!$ci_number" ;;
    pr|run) [ -n "$ci_number" ] && mr_pfx="#$ci_number" ;;
  esac
  if [ -n "$mr_pfx" ]; then
    m_lo=""; m_lc=""
    if [ -n "$ci_url" ]; then m_lo=$'\033]8;;'"$ci_url"$'\a'; m_lc=$'\033]8;;\a'; fi
    mr_link=$(printf '%s\033[4m%s%s%s\033[0m' "$LINK" "$m_lo" "$mr_pfx" "$m_lc")
    st_icon=""; st_color=""
    case "$ci_state" in
      passed)   st_icon=$'\xe2\x9c\x93'; st_color=$'\033[32m' ;;  # ✓ green
      failed)   st_icon=$'\xe2\x9c\x97'; st_color=$'\033[31m' ;;  # ✗ red
      running)  st_icon=$'\xe2\x97\x8f'; st_color=$'\033[36m' ;;  # ● cyan
      pending)  st_icon=$'\xe2\x97\x8b'; st_color=$'\033[33m' ;;  # ○ yellow
      canceled) st_icon=$'\xe2\x8a\x98'; st_color=$'\033[90m' ;;  # ⊘ gray
      skipped)  st_icon=$'\xc2\xbb';     st_color=$'\033[90m' ;;  # » gray
    esac
    if [ -n "$st_icon" ]; then
      mr_seg=$(printf '%s%s\033[0m %s' "$st_color" "$st_icon" "$mr_link")
    else
      mr_seg="$mr_link"
    fi
    mr_on_ticket=1
  fi

  # Assemble the line; each `·`-separated piece is optional.
  gsep=$'\033[90m·\033[0m'
  ticket_line=$(printf '\xf0\x9f\x93\x8c %s' "$id_link")
  [ -n "$mr_seg" ]   && ticket_line=$(printf '%s %s %s' "$ticket_line" "$gsep" "$mr_seg")
  [ -n "$tk_title" ] && ticket_line=$(printf '%s %s %s' "$ticket_line" "$gsep" "$tk_title")
fi

# Line-1 CI segment: only when the MR link was NOT relocated to the ticket line
# (no ticket line at all, or a ticket line but no MR number to host).
if [ -z "$mr_on_ticket" ] && [ -n "$ci_segment" ]; then
  parts=$(printf '%s \033[90m%s\033[0m %s' "$parts" "$SEP" "$ci_segment")
fi

# Model / token / context segments live on a second line (dark gray)
SEP=$'\xe2\x94\x82'
line2=""

if [ -n "$model" ]; then
  if [ -n "$effort" ]; then
    model_seg=$(printf '\033[90m%s (%s)\033[0m' "$model" "$effort")
  else
    model_seg=$(printf '\033[90m%s\033[0m' "$model")
  fi
  if [ -n "$line2" ]; then
    line2=$(printf '%s \033[90m%s\033[0m %s' "$line2" "$SEP" "$model_seg")
  else
    line2="$model_seg"
  fi
fi

# Session-cost segment — always dimmed gray, matching the rest of line 2.
cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { if (c != "" && c+0 > 0) printf "%.2f", c+0 }')
if [ -n "$cost_fmt" ]; then
  cost_seg=$(printf '\033[90m$%s\033[0m' "$cost_fmt")
  if [ -n "$line2" ]; then
    line2=$(printf '%s \033[90m%s\033[0m %s' "$line2" "$SEP" "$cost_seg")
  else
    line2="$cost_seg"
  fi
fi

# Token usage segment (dark gray)
if [ -n "$tok_display" ]; then
  if [ -n "$line2" ]; then
    line2=$(printf '%s \033[90m%s\033[0m \033[90mtok:%s\033[0m' "$line2" "$SEP" "$tok_display")
  else
    line2=$(printf '\033[90mtok:%s\033[0m' "$tok_display")
  fi
fi

# Context usage segment
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    color='\033[91m'  # red
  elif [ "$used_int" -ge 50 ]; then
    color='\033[93m'  # yellow
  else
    color='\033[90m'  # dark gray
  fi
  if [ -n "$line2" ]; then
    line2=$(printf '%s \033[90m%s\033[0m '"$color"'ctx:%d%%\033[0m' "$line2" "$SEP" "$used_int")
  else
    line2=$(printf "$color"'ctx:%d%%\033[0m' "$used_int")
  fi
fi

# Background-session badge (end of line 2). Background jobs run with
# CLAUDE_JOB_DIR set; an interactive session has it empty. The statusline
# command inherits the parent Claude Code process env, so this reliably
# distinguishes the two. Shown as a bright magenta "bg" chip.
if [ -n "$CLAUDE_JOB_DIR" ]; then
  bg_seg=$(printf '\033[90mbg\033[0m')
  if [ -n "$line2" ]; then
    line2=$(printf '%s \033[90m%s\033[0m %s' "$line2" "$SEP" "$bg_seg")
  else
    line2="$bg_seg"
  fi
fi

out="$parts"
[ -n "$line2" ] && out=$(printf '%s\n%s' "$out" "$line2")
[ -n "$ticket_line" ] && out=$(printf '%s\n%s' "$ticket_line" "$out")
printf '%s' "$out"
exit 0

# frozen_string_literal: true

# Parses git log output (format: COMMIT %H|%aI|%s + numstat) and emits
# CUSTOM-CHANGELOG.md grouped by month → day → commit, listing every
# commit attributed to our emails together with the files touched.
#
# Run inside the rails container (host-side ruby is not available):
#   docker compose exec -T rails ruby /app/.codi/scripts/build-changelog.rb \
#     <input.txt> <output.md>
#
# ⚠️ DESTRUCTIVE — do NOT point this at the live CUSTOM-CHANGELOG.md.
#
# This script REWRITES its output file from scratch. It does not merge, and
# despite older wording in CUSTOM-MERGES-GUIDE.md it does NOT preserve the
# milestones block: it emits the table hard-coded below, which has drifted
# from the real one in CUSTOM-CHANGELOG.md (missing the 2026-05-11 and
# 2026-05-14 rows). It also replaces every hand-written per-release
# narrative with auto-generated "path +N/-M" lists.
#
# Running it during the .88 upgrade rewrote 453 lines and destroyed the
# .86 / .74 / WABA write-ups; the change was reverted and the changelog is
# now maintained BY HAND. Keep this script for one-off scaffolding into a
# scratch file only:
#
#   ... build-changelog.rb <input.txt> /app/.llm/temporary/scaffold.md
#
# See CUSTOM-MERGES-GUIDE.md step 6.

require 'date'

input  = ARGV[0] || '.llm/temporary/our-history.txt'
output = ARGV[1] || 'CUSTOM-CHANGELOG.md'

commits = []
current = nil
File.foreach(input) do |line|
  line = line.chomp
  next if line.empty?

  if line.start_with?('COMMIT ')
    commits << current if current
    parts = line.sub('COMMIT ', '').split('|', 3)
    current = { sha: parts[0], date: DateTime.parse(parts[1]), subject: parts[2], files: [] }
  else
    cols = line.split("\t")
    next unless cols.length == 3

    add, del, path = cols
    current[:files] << { add: add, del: del, path: path }
  end
end
commits << current if current

# Reverse so newest first (changelog convention)
commits.sort_by! { |c| c[:date] }.reverse!

File.open(output, 'w') do |f|
  f.puts <<~HEADER
    # Própria Cloud / Chatwoot — Custom Changelog

    Curated history of customizations made to this Chatwoot fork on top of
    the upstream `fazer-ai/chatwoot` tree. Only commits authored by the
    project owner are listed (filtered by `robson@robson.com.br`,
    `robson@controle.digital`, `*@propria.cloud`, `*@controle.digital`).
    Upstream merges and third-party PRs are intentionally excluded — they
    are visible via `git log` against the remote tracking branches.

    Newest first. Each entry shows the commit subject, the short SHA, and
    the files touched (additions / deletions). Regenerate from inside the
    rails container with:

    ```bash
    git log --all --reverse --pretty=format:'COMMIT %H|%aI|%s' --numstat \\
      --author='robson@robson.com.br' > .llm/temporary/our-history.txt
    docker compose exec -T rails ruby /app/.codi/scripts/build-changelog.rb \\
      .llm/temporary/our-history.txt CUSTOM-CHANGELOG.md
    ```

    Add new author emails to the `--author` filter as the team grows; the
    builder script accepts the input/output paths positionally.

  HEADER

  f.puts <<~MILESTONES
    ## Version milestones

    Each adopted upstream tag becomes its own `codi-vX.Y.Z-fazer-ai.N`
    branch and gets a `codi-vX.Y.Z-fazer-ai.N.ITER` tag for every
    Própria-Cloud-side release cut on top of it. The chatwoot core
    version (`vX.Y.Z`) is the upstream Chatwoot release embedded inside
    fazer-ai; the `.N` suffix is fazer-ai's own iteration counter.

    Update this table whenever a new fazer-ai upstream tag is adopted
    or a new `codi-*` release tag is cut. The script preserves the
    block on regen — edit it directly inside `.codi/scripts/build-changelog.rb`.

    | Date       | Branch                          | Adopted upstream tag        | Chatwoot core | Notes                                                                                       |
    | :--------- | :------------------------------ | :-------------------------- | :------------ | :------------------------------------------------------------------------------------------ |
    | 2025-11-03 | `codi-v4.7.0-fazer-ai.6`        | `v4.7.0-fazer-ai.6`         | 4.7.0         | Initial fork — Click2Run / OpenID Connect / WhatsApp baseline.                              |
    | 2026-05-07 | `codi-v4.9.0-fazer-ai.13`       | `v4.9.0-fazer-ai.13`        | 4.9.0         | Tagged `codi-v4.9.0-fazer-ai.13.1` after intermediate upgrade. Safety tag: `codi-pre-upgrade-2026-05-07`. |
    | 2026-05-08 | `codi-v4.13.0-fazer-ai.66`      | `v4.13.0-fazer-ai.66`       | 4.13.0        | Tagged `codi-v4.13.0-fazer-ai.66.1`. Safety tag: `codi-pre-upgrade2-2026-05-08`. |
    | 2026-05-09 | _(still on `.66` branch)_       | `fazerai/main` head (post-`.66`) | 4.13.0   | Merged 2 untagged upstream commits (#285, #286) — within the `.66` cycle until fazer-ai cuts `.67`. |
    | 2026-05-20 | `codi-v4.14.0-fazer-ai.74`      | `v4.14.0-fazer-ai.74`       | 4.14.0        | First core bump (4.13 → 4.14). New branch off the upstream tag; merged 159 commits from `codi-v4.13.0-fazer-ai.66`. Safety tag: `codi-pre-upgrade-2026-05-20`. |
    | 2026-06-28 | `codi-v4.15.1-fazer-ai.86`      | `v4.15.1-fazer-ai.86`       | 4.15.1        | Minor bump (4.14 → 4.15). New branch cut FROM current `codi-v4.14.0-fazer-ai.74` (base = our codi), upstream tag merged in — 178 commits. Safety tag: `codi-pre-upgrade-2026-06-27`. |
    | 2026-07-18 | `codi-v4.15.1-fazer-ai.88`      | `v4.15.1-fazer-ai.88`       | 4.15.1        | Iteration bump only (core unchanged). Branch cut FROM `codi-v4.15.1-fazer-ai.86`, tag `.88` merged in — 22 commits, 36 files. `.87` skipped (contained in `.88`); `.88` == `fazerai/main` HEAD. Chatwoot core `v4.16.0` existed upstream but fazer-ai had not adopted it. 4 conflicts, all additive unions. Safety tag: `codi-pre-upgrade-2026-07-18`. **Current branch.** |

    Pre-upgrade safety tags taken before each version bump (kept as
    rollback anchors): `codi-pre-upgrade-2026-05-07`, `codi-pre-upgrade2-2026-05-08`, `codi-pre-upgrade-2026-05-11`, `codi-pre-upgrade-2026-05-14`, `codi-pre-upgrade-2026-05-20`, `codi-pre-upgrade-2026-06-27`, `codi-pre-upgrade-2026-07-18`.

  MILESTONES

  current_month = nil
  current_day   = nil

  commits.each do |c|
    month = c[:date].strftime('%Y-%m')
    day   = c[:date].strftime('%Y-%m-%d')

    if month != current_month
      f.puts "\n## #{month}\n"
      current_month = month
    end
    if day != current_day
      f.puts "\n### #{day}\n"
      current_day = day
    end

    f.puts "- **`#{c[:sha][0, 9]}`** — #{c[:subject]}"
    next if c[:files].empty?

    if c[:files].size <= 20
      c[:files].each do |fi|
        stats = "+#{fi[:add]}/-#{fi[:del]}"
        stats = '(binary)' if fi[:add] == '-' && fi[:del] == '-'
        f.puts "  - `#{fi[:path]}` #{stats}"
      end
    else
      f.puts "  - _#{c[:files].size} files touched_:"
      c[:files].first(15).each do |fi|
        stats = "+#{fi[:add]}/-#{fi[:del]}"
        stats = '(binary)' if fi[:add] == '-' && fi[:del] == '-'
        f.puts "    - `#{fi[:path]}` #{stats}"
      end
      f.puts "    - … and #{c[:files].size - 15} more"
    end
  end
end

puts "wrote #{commits.size} commits to #{output}"

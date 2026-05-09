# frozen_string_literal: true

# Parses git log output (format: COMMIT %H|%aI|%s + numstat) and emits
# CUSTOM-CHANGELOG.md grouped by month → day → commit, listing every
# commit attributed to our emails together with the files touched.
#
# Run inside the rails container (host-side ruby is not available):
#   docker compose exec -T rails ruby /app/.codi/scripts/build-changelog.rb \
#     <input.txt> <output.md>
#
# See CUSTOM-CHANGELOG.md header for the full regen recipe.

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
    the files touched (additions / deletions). Generated from the git
    history; rebuild with `.llm/temporary/20260509-changelog-builder.rb`.

  HEADER

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

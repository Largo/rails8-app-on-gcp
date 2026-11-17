#!/usr/bin/env ruby
# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# bin/sync_devsite_codelab.rb
# Synchronizes workshop/CODELAB.md (GitHub source of truth) with an external DevSite Codelab
# export path (via ENV["DEVSITE_CODELAB_PATH"] or workshop/build/devsite/index.lab.md).
#
# The destination may carry metadata that does not exist in CODELAB.md: its frontmatter, and
# single `Key: Value` lines placed right under a `## ` step heading. Both are preserved, so a
# sync never silently removes something that was added on the destination side.

require "fileutils"

REPO_ROOT = File.expand_path("..", __dir__)
CODELAB_MD = File.join(REPO_ROOT, "workshop", "CODELAB.md")
DEFAULT_BUILD_PATH = File.join(REPO_ROOT, "workshop", "build", "devsite", "index.lab.md")
DOTENV_PATHS = [
  File.join(REPO_ROOT, ".env"),
  File.expand_path("../rails8-app-on-gcp-pvt/.env", REPO_ROOT)
].freeze

TITLE_HEADING = /^(?=# Rails 8 on Google Cloud)/
# A metadata line is a lone `Key: value` with a single-token value, e.g. `Duration: 10:00`.
# CODELAB.md writes its own in italics (`*Duration: 10min*`); those belong to the source.
OPENING_LINE = /\A\*?([A-Z][A-Za-z0-9_]*): \S+?\*?\z/

# "## Step 3: Deploy 1 ..." -> "step 3"; any other heading -> its lowercased words.
# Step titles get reworded between releases, their numbers do not.
def heading_key(heading)
  text = heading.sub(/\A##\s+/, "")
  return "step #{Regexp.last_match(1)}" if text =~ /\AStep\s+(\d+)\b/i

  text.downcase.gsub(/[^a-z0-9]+/, " ").strip
end

# Splits markdown into [heading_line_or_nil, lines_until_next_heading] sections.
def sections_of(markdown)
  sections = [[nil, []]]
  markdown.each_line do |line|
    if line.start_with?("## ")
      sections << [line, []]
    else
      sections.last[1] << line
    end
  end
  sections
end

# The blank and metadata lines that open a section, before its first line of prose.
def opening_lines(lines)
  lines.take_while { |l| l.strip.empty? || l.strip.match?(OPENING_LINE) }
end

# Returns { heading_key => ["Key: Value", ...] } for the destination-style (non-italic)
# metadata lines that open each section.
def step_metadata(markdown)
  sections_of(markdown).each_with_object({}) do |(heading, lines), found|
    next unless heading

    meta = opening_lines(lines).map(&:strip).reject { |l| l.empty? || l.start_with?("*") }
    found[heading_key(heading)] = meta unless meta.empty?
  end
end

# Re-inserts destination-only metadata lines under the matching headings of the new body.
# A key the new body already states right under that heading (e.g. Duration) is not repeated.
def carry_over_step_metadata(body, existing)
  preserved = step_metadata(existing)
  return body if preserved.empty?

  sections_of(body).map do |heading, lines|
    next lines.join unless heading

    opening = opening_lines(lines)
    missing = preserved.fetch(heading_key(heading), []).reject do |meta|
      key = meta[OPENING_LINE, 1]
      opening.any? { |l| l.strip[OPENING_LINE, 1] == key }
    end
    next heading + lines.join if missing.empty?

    rest = lines.drop(opening.size)
    kept_opening = opening.reverse.drop_while { |l| l.strip.empty? }.reverse
    heading + kept_opening.join + "\n" + missing.map { |m| "#{m}\n" }.join + "\n" + rest.join
  end.join
end

dotenv_devsite_path = nil
DOTENV_PATHS.each do |dotenv_path|
  next unless File.exist?(dotenv_path)
  File.readlines(dotenv_path).each do |line|
    if line.strip =~ /\A(?:export\s+)?DEVSITE_CODELAB_PATH=(['"]?)(.+?)\1\s*(?:#.*)?\z/
      dotenv_devsite_path ||= Regexp.last_match(2).strip
    end
  end
end

external_devsite_path = ENV["DEVSITE_CODELAB_PATH"] || dotenv_devsite_path
target_paths = [DEFAULT_BUILD_PATH]
target_paths << external_devsite_path if external_devsite_path && !external_devsite_path.empty?

codelab_content = File.read(CODELAB_MD)
body = codelab_content.sub(/\A.*?#{TITLE_HEADING.source}/m, "")
# Rewrite relative image paths from GitHub Codelab to DevSite Codelab paths
body = body.gsub(%r{\(assets/images/([^)]+)\)}, '(/codelabs/rails8-on-google-cloud/img/\1)')
# Convert `<details><summary>...</summary>...</details>` to standard markdown sections for DevSite parser compatibility (fixes M3)
body = body.gsub(%r{<details>\s*<summary>(.*?)</summary>(.*?)</details>}m) do
  title = Regexp.last_match(1).gsub(%r{</?strong>}, "").strip
  "#### #{title}\n#{Regexp.last_match(2)}"
end

target_paths.uniq.each do |devsite_path|
  begin
    FileUtils.mkdir_p(File.dirname(devsite_path))
    frontmatter = ""
    target_body = body
    if File.exist?(devsite_path)
      existing = File.read(devsite_path)
      header_match = existing.match(/\A(.*?)#{TITLE_HEADING.source}/m)
      frontmatter = header_match ? header_match[1] : ""
      target_body = carry_over_step_metadata(body, existing)
    end
    File.write(devsite_path, "#{frontmatter}#{target_body}")
    puts "✅ Synchronized workshop/CODELAB.md (v#{File.read(File.join(REPO_ROOT, 'workshop/CODELAB_VERSION')).strip}) -> #{devsite_path}"
  rescue Errno::EROFS, Errno::EACCES, Errno::ENOENT => e
    raise if devsite_path == DEFAULT_BUILD_PATH
    warn "⚠️  Skipped optional external DevSite mirror #{devsite_path} (#{e.class}: #{e.message})"
  end
end

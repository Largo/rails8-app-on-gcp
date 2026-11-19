require "minitest/autorun"
require "open3"
require "fileutils"

class SlidesTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  SLIDES_MD = File.join(REPO_ROOT, "slides/index.md")
  AGY_EN_MD = File.join(REPO_ROOT, "slides/antigravity.en.md")
  AGY_IT_MD = File.join(REPO_ROOT, "slides/antigravity.it.md")
  ALL_SLIDE_SOURCES = Dir[File.join(REPO_ROOT, "slides/*.md")].reject { |f| File.basename(f) == "README.md" }.sort
  SLIDES_DIST_DIR = File.join(REPO_ROOT, "slides/dist")
  SLIDES_HTML = File.join(SLIDES_DIST_DIR, "index.html")
  AGY_EN_HTML = File.join(SLIDES_DIST_DIR, "antigravity.en.html")
  AGY_IT_HTML = File.join(SLIDES_DIST_DIR, "antigravity.it.html")
  RUBYISTS_MD = File.join(REPO_ROOT, "slides/rubyists.en.md")
  RUBYISTS_HTML = File.join(SLIDES_DIST_DIR, "rubyists.en.html")
  # Body-text budget for the Rubyists deck: about 10 words per slide. The ceiling is 12 because
  # one mandatory disclaimer sentence on the comparison slide is 12 words long.
  RUBYISTS_MAX_BODY_WORDS = 12

  def marp_cmd
    nvm_bins = Dir[File.expand_path("~/.nvm/versions/node/*/bin")].sort.reverse
    ENV["PATH"] = (nvm_bins + [ENV["PATH"]]).join(":") unless nvm_bins.empty?
    system("which marp > /dev/null 2>&1") ? "marp" : "npx -y @marp-team/marp-cli"
  end

  def setup
    FileUtils.mkdir_p(SLIDES_DIST_DIR)
    cmd = marp_cmd
    system("#{cmd} #{SLIDES_MD} -o #{SLIDES_HTML} --html > /dev/null 2>&1")
    system("#{cmd} #{AGY_EN_MD} -o #{AGY_EN_HTML} --html > /dev/null 2>&1") if File.exist?(AGY_EN_MD)
    system("#{cmd} #{AGY_IT_MD} -o #{AGY_IT_HTML} --html > /dev/null 2>&1") if File.exist?(AGY_IT_MD)
    system("#{cmd} #{RUBYISTS_MD} -o #{RUBYISTS_HTML} --html > /dev/null 2>&1") if File.exist?(RUBYISTS_MD)
  end

  def test_slides_md_has_valid_frontmatter
    assert File.exist?(SLIDES_MD), "slides/index.md must exist"
    content = File.read(SLIDES_MD, encoding: "utf-8")
    assert_match(/^marp:\s*true/m, content)
    assert_match(/^theme:\s*gaia/m, content)
    assert_match(/^paginate:\s*true/m, content)
  end

  def test_antigravity_en_and_it_decks_exist_and_have_valid_frontmatter_and_prompts
    %w[
      codelab-page1-intro.png
      agy-step1-new-project.png
      agy-step2-select-folder.png
      agy-step3-project-settings.png
      agy-step4-turbo-mode.png
    ].each do |img|
      assert File.exist?(File.join(REPO_ROOT, "slides/images", img)), "Screenshot slides/images/#{img} must exist"
    end

    [AGY_EN_MD, AGY_IT_MD].each do |deck_path|
      assert File.exist?(deck_path), "#{File.basename(deck_path)} must exist"
      content = File.read(deck_path, encoding: "utf-8")
      assert_match(/^marp:\s*true/m, content)
      assert_match(/^theme:\s*gaia/m, content)
      assert_match(/^paginate:\s*true/m, content)
      # Must contain WSL note for Windows
      assert_match(/WSL/i, content, "#{File.basename(deck_path)} must mention WSL for Windows")
      # Must contain Step 1.5 Codelab Page 1 (#0) screenshot and QR code
      assert_match(/codelab-page1-intro\.png/, content)
      assert_match(/codelab-qr\.png/, content)
      # Must contain Prompt 1 (git clone into Documents + sound)
      assert_match(%r{https://github\.com/palladius/rails8-app-on-gcp/}, content)
      assert_match(/git clone/i, content)
      assert_match(/Documents/i, content)
      # Must contain Step 4 Turbo mode instruction, 4 screenshots, and PROD disclaimer
      assert_match(/TURBO/i, content, "#{File.basename(deck_path)} must mention TURBO mode")
      assert_match(/agy-step1-new-project\.png/, content)
      assert_match(/agy-step2-select-folder\.png/, content)
      assert_match(/agy-step3-project-settings\.png/, content)
      assert_match(/agy-step4-turbo-mode\.png/, content)
      assert_match(/PROD/i, content, "#{File.basename(deck_path)} must include the DO NOT DO IN PROD disclaimer")
      # Must contain Prompt 2 (Codelab + landing-page README)
      assert_match(%r{https://codelabs\.developers\.google\.com/codelabs/rails8-on-google-cloud}, content)
      assert_match(%r{workshop/landing-page/README}, content)
      # Must contain Step 2.5 Credits on Page 2 (#1) and Green button check
      assert_match(/#1/, content)
      # Must contain Prompt 3 (GCP project creation after coupon)
      assert_match(/workshop-(rails8|wbh|modena)-YYYYMMDD/i, content)
    end
  end

  def test_no_unrendered_html_tags_or_code_escaped_markup_in_rendered_slides
    [SLIDES_HTML, AGY_EN_HTML, AGY_IT_HTML, RUBYISTS_HTML].each do |html_path|
      assert File.exist?(html_path), "Rendered slides HTML #{File.basename(html_path)} must exist"
      html = File.read(html_path, encoding: "utf-8")

      # In Marp, when indentation causes HTML to be parsed as code block,
      # it gets wrapped in <pre ...><code>&lt;div... or &lt;button...
      code_block_divs = html.scan(/<code>.*?&lt;div\s+style.*?<\/code>/m)
      assert_empty code_block_divs, "Found unrendered <div style> escaped inside code block in #{File.basename(html_path)}:\n#{code_block_divs.join("\n")}"

      code_block_buttons = html.scan(/<code>.*?&lt;button.*?<\/code>/m)
      assert_empty code_block_buttons, "Found unrendered <button> escaped inside code block in #{File.basename(html_path)}:\n#{code_block_buttons.join("\n")}"

      # Also ensure no raw unrendered literal text like '<div style=' or '<button onclick' is visible outside attributes
      text_leaks = html.scan(/&lt;div\s+style=[^&]*&gt;/)
      assert_empty text_leaks, "Found literal escaped &lt;div style=...&gt; in #{File.basename(html_path)}:\n#{text_leaks.join("\n")}"

      text_button_leaks = html.scan(/&lt;button\s+onclick=[^&]*&gt;/)
      assert_empty text_button_leaks, "Found literal escaped &lt;button onclick=...&gt; in #{File.basename(html_path)}:\n#{text_button_leaks.join("\n")}"
    end
  end

  # A link that swallows the deck is a live-presentation bug: the presenter loses their
  # slides mid-talk and has to hit Back on a projector. Reported twice in the friction
  # logs (Antigravity download link, then the "Claim GCP Credits" button), hence a test.
  def test_external_links_in_slides_open_in_a_new_tab
    offenders = []

    ALL_SLIDE_SOURCES.each do |path|
      File.readlines(path, encoding: "utf-8", chomp: true).each_with_index do |line, index|
        line.scan(/<a\s+[^>]*href="https?:\/\/[^"]*"[^>]*>/) do |tag|
          next if tag.include?('target="_blank"')

          offenders << "#{File.basename(path)}:#{index + 1}: #{tag.strip[0, 120]}"
        end
      end
    end

    assert_empty offenders, <<~MSG
      External slide links must open in a new tab, otherwise clicking one replaces the deck:
      #{offenders.join("\n")}

      Add `target="_blank" rel="noopener noreferrer"` to each link.
    MSG
  end

  # --- Rubyists deck (Helvetic Ruby 2026) -------------------------------------------------

  # Splits a Marp deck into slides (front matter removed).
  def marp_slides(path)
    content = File.read(path, encoding: "utf-8")
    body = content.sub(/\A---\n.*?\n---\n/m, "")
    body.split(/^---\s*$/).map(&:strip).reject(&:empty?)
  end

  # Words an attendee has to read on a slide: everything except the title (headings), code blocks,
  # table cells, speaker notes (HTML comments), inline SVG (icons, diagrams), links and markup.
  # A link is a label to click, not prose: Markdown links were never counted, and external links
  # have to be HTML anchors (they need target="_blank"), so anchors are treated the same way.
  # The footer is generated by CSS, so it never reaches this text.
  def body_words(slide)
    text = slide.dup
    text.gsub!(/<!--.*?-->/m, " ")
    text.gsub!(/^```.*?^```/m, " ")
    text.gsub!(/<svg\b.*?<\/svg>/m, " ")
    text.gsub!(/<style\b.*?<\/style>/m, " ")
    text.gsub!(/<table\b.*?<\/table>/m, " ")
    text.gsub!(/<a\b.*?<\/a>/m, " ")
    text.gsub!(/^\|.*\|\s*$/, " ")
    text.gsub!(/^\#{1,6}\s.*$/, " ")
    text.gsub!(/!\[[^\]]*\]\([^)]*\)/, " ")
    text.gsub!(/\[([^\]]*)\]\([^)]*\)/, '')
    text.gsub!(/<[^>]+>/, " ")
    text.split.select { |token| token.match?(/[[:alnum:]]/) }
  end

  def test_rubyists_deck_exists_with_valid_frontmatter
    assert File.exist?(RUBYISTS_MD), "slides/rubyists.en.md must exist"
    content = File.read(RUBYISTS_MD, encoding: "utf-8")
    assert_match(/^marp:\s*true/m, content)
    assert_match(/^theme:\s*gaia/m, content)
    assert_match(/^paginate:\s*true/m, content)
    refute_match(/[\u2018\u2019\u201C\u201D]/, content, "Use straight ASCII quotes only")
  end

  def test_rubyists_deck_renders_without_escaped_markup
    assert File.exist?(RUBYISTS_HTML), "Rendered slides/dist/rubyists.en.html must exist"
    html = File.read(RUBYISTS_HTML, encoding: "utf-8")
    assert_operator html.scan(/<section\b/).size, :>=, marp_slides(RUBYISTS_MD).size
    assert_empty html.scan(/&lt;(?:div|a|img|svg|table)\s+[a-z-]+=/), "Found HTML rendered as escaped text in rubyists.en.html"
  end

  # 18 slides since v0.3.20: cover, "What you need today", three framing slides, five stops, one
  # comparison, five kickoff slides, "Thank you" and one bonus slide. 18 is the top of the range.
  def test_rubyists_deck_has_16_to_18_slides_each_with_speaker_notes
    slides = marp_slides(RUBYISTS_MD)
    assert_includes 16..18, slides.size, "Expected 16 to 18 slides, found #{slides.size}"

    without_notes = slides.each_index.reject { |i| slides[i].match?(/<!--.+?-->/m) }.map { |i| i + 1 }
    assert_empty without_notes, "Slides without speaker notes: #{without_notes.join(', ')}"
  end

  # A renamed or forgotten picture renders as a broken image (or an empty background) on stage.
  def test_rubyists_deck_references_only_images_that_exist
    referenced = File.read(RUBYISTS_MD, encoding: "utf-8").scan(%r{images/[\w.-]+}).uniq
    refute_empty referenced, "The Rubyists deck is expected to reference pictures under slides/images/"

    missing = referenced.reject { |image| File.exist?(File.join(REPO_ROOT, "slides", image)) }
    assert_empty missing, "slides/rubyists.en.md references files that do not exist: #{missing.join(', ')}"
  end

  def test_rubyists_deck_stays_within_the_body_text_budget
    over = marp_slides(RUBYISTS_MD).each_with_index.filter_map do |slide, index|
      words = body_words(slide)
      "slide #{index + 1}: #{words.size} words (#{words.join(' ')})" if words.size > RUBYISTS_MAX_BODY_WORDS
    end

    assert_empty over, <<~MSG
      Slides show code, a table, a diagram or one punchline; the narrative belongs in speaker notes.
      Over the budget of #{RUBYISTS_MAX_BODY_WORDS} body words:
      #{over.join("\n")}
    MSG
  end

  def test_rubyists_deck_keeps_titles_free_of_emoji_and_numbered_kickers
    offenders = marp_slides(RUBYISTS_MD).flat_map { |slide| slide.lines.grep(/^\#{1,2}\s/) }.select do |title|
      title.match?(/\p{Extended_Pictographic}/) || title.match?(%r{^\#+\s*\d{1,2}\s*/})
    end

    assert_empty offenders, "Titles must not carry emoji or '01 /' kickers:\n#{offenders.join}"
  end

  # A reader of the narrative on GitHub must reach the rendered deck in one click.
  # A link to the Markdown source shows raw Marp markup, not slides.
  def test_rubyists_narrative_links_the_published_deck
    narrative = File.read(File.join(REPO_ROOT, "workshop/narratives/for-rubyists/README.md"))

    assert_includes narrative, "https://palladius.github.io/rails8-app-on-gcp/slides/rubyists.en.html",
                    "workshop/narratives/for-rubyists/README.md must link the published (rendered) deck"
  end

  # The workshop is on the community day, which is not in the conference building.
  def test_helvetic_ruby_event_pages_name_the_workshop_venue
    event_page = File.read(File.join(REPO_ROOT, "workshop/events/20261119-helvetic-ruby/README.md"))
    venue_line = event_page.lines.find { |line| line.start_with?("- **Venue:**") }.to_s
    events_index_entry = File.read(File.join(REPO_ROOT, "workshop/events/README.md")).lines.find { |line| line.include?("20261119-helvetic-ruby") }.to_s

    assert_match(/Paulus Akademie/, venue_line, "The venue of the workshop is Paulus Akademie")
    assert_match(/Pfingstweidstrasse 28/, venue_line, "The venue line must carry the street address")
    refute_match(/at Technopark/, events_index_entry, "The events index must not send people to the conference building")
  end

  def test_rendered_png_images_can_be_generated
    stdout, stderr, status = Open3.capture3("#{marp_cmd} --images png --allow-local-files #{SLIDES_MD} -o #{SLIDES_DIST_DIR}/slide.png")
    assert_equal 0, status.exitstatus, "Marp image rendering failed: #{stderr}"

    # Ensure slide 5 was generated and has non-zero size
    slide5 = File.join(SLIDES_DIST_DIR, "slide.005.png")
    assert File.exist?(slide5), "Slide 5 PNG was not generated"
    assert File.size(slide5) > 10_000, "Slide 5 PNG is suspiciously small (#{File.size(slide5)} bytes)"
  end
end

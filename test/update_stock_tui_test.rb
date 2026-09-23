# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/update-stock-tui"

class StockTuiReleaseUpdaterTest < Minitest::Test
  Updater = StockTuiReleaseUpdater

  class FakeClient
    attr_reader :download_count

    def initialize(release, asset_directory)
      @release = release
      @asset_directory = asset_directory
      @download_count = 0
    end

    def latest_release
      @release
    end

    def download(release, directory)
      raise "unexpected release" unless release.equal?(@release)

      @download_count += 1
      release.assets.each_key do |name|
        FileUtils.cp(File.join(@asset_directory, name), directory)
      end
    end
  end

  class ChangingClient < FakeClient
    def initialize(release, refreshed_release, asset_directory)
      super(release, asset_directory)
      @releases = [release, refreshed_release]
    end

    def latest_release
      @releases.shift || @release
    end
  end

  class UnexpectedClient
    def latest_release
      raise "current-only mode must not query releases"
    end
  end

  def test_version_requires_strict_stable_semver
    assert_equal "12.3.4", Updater::Version.from_tag("v12.3.4").to_s
    assert_operator Updater::Version.from_tag("v1.10.0"), :>, Updater::Version.from_tag("v1.9.9")

    ["1.2.3", "v1.2", "v01.2.3", "v1.2.3-rc.1", "v1.2.3+build"].each do |tag|
      assert_raises(Updater::Error) { Updater::Version.from_tag(tag) }
    end
  end

  def test_release_rejects_prereleases_and_incomplete_assets
    directory, payload = release_fixture("0.3.3")
    payload["prerelease"] = true
    assert_raises(Updater::Error) { Updater::Release.from_json(JSON.generate(payload)) }

    payload["prerelease"] = false
    payload["assets"].reject! { |asset| asset["name"].include?("x86_64-apple-darwin") }
    error = assert_raises(Updater::Error) { Updater::Release.from_json(JSON.generate(payload)) }
    assert_match "exactly one uploaded", error.message
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_latest_release_uses_numeric_order_and_ignores_nonstable_tags
    directories = []
    directory, older = release_fixture("0.3.9")
    directories << directory
    directory, newer = release_fixture("0.3.10")
    directories << directory
    prerelease = Marshal.load(Marshal.dump(newer))
    prerelease["tag_name"] = "v9.0.0-rc.1"
    prerelease["prerelease"] = true
    unrelated = Marshal.load(Marshal.dump(newer))
    unrelated["tag_name"] = "catalog-2026-09-22"

    release = Updater::Release.latest_from_json(JSON.generate([[older, prerelease], [unrelated, newer]]))
    assert_equal "0.3.10", release.version.to_s
  ensure
    directories&.each { |path| FileUtils.rm_rf(path) }
  end

  def test_download_verification_checks_manifest_api_digest_size_and_bytes
    directory, payload = release_fixture("0.3.3")
    release = Updater::Release.from_json(JSON.generate(payload))
    checksums = Updater.verify_downloads(release, directory)
    assert_equal 4, checksums.length

    archive = Updater.archive_names(release.version).values.first
    File.open(File.join(directory, archive), "ab") { |file| file.write("tampered") }
    error = assert_raises(Updater::Error) { Updater.verify_downloads(release, directory) }
    assert_match(/size changed|digest mismatch/, error.message)
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_checksum_manifest_rejects_unsafe_and_duplicate_names
    unsafe_error = assert_raises(Updater::Error) do
      Updater.parse_checksums("#{"a" * 64}  ../stock-tui.tar.gz\n")
    end
    assert_match "unsafe filename", unsafe_error.message

    duplicate_error = assert_raises(Updater::Error) do
      digest = "b" * 64
      Updater.parse_checksums("#{digest}  stock-tui.tar.gz\n#{digest}  stock-tui.tar.gz\n")
    end
    assert_match "duplicate", duplicate_error.message
  end

  def test_renderer_updates_all_targets_and_drops_revision
    directory, payload = release_fixture("0.3.3")
    release = Updater::Release.from_json(JSON.generate(payload))
    formula = Updater.render_formula(release, Updater.verify_downloads(release, directory))

    assert_equal 4, formula.scan(/^\s+url /).length
    assert_equal 4, formula.scan(/^\s+sha256 /).length
    Updater.archive_names(release.version).each_value { |name| assert_includes formula, name }
    refute_match(/^\s*revision /, formula)
    assert_equal "0.3.3", Updater.formula_version(formula).to_s
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_formula_version_rejects_mixed_conditional_versions
    formula = <<~RUBY
      class StockTui < Formula
        url "https://example.test/releases/download/v0.3.2/stock-tui-v0.3.2-a.tar.gz"
        url "https://example.test/releases/download/v0.3.3/stock-tui-v0.3.3-b.tar.gz"
      end
    RUBY

    assert_raises(Updater::Error) { Updater.formula_version(formula) }
  end

  def test_runner_is_a_network_efficient_no_op_when_current
    directory, payload = release_fixture("0.3.2")
    release = Updater::Release.from_json(JSON.generate(payload))
    client = FakeClient.new(release, directory)

    Dir.mktmpdir do |formula_directory|
      formula_path = File.join(formula_directory, "stock-tui.rb")
      File.write(formula_path, source_formula("0.3.2", revision: 1))
      original = File.binread(formula_path)

      result = Updater::Runner.new(formula_path: formula_path, client: client).run
      refute result.changed
      assert_equal Digest::SHA256.hexdigest(original), result.formula_sha256
      assert_equal 0, client.download_count
      assert_equal original, File.binread(formula_path)
    end
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_runner_current_only_does_not_resolve_or_change_releases
    Dir.mktmpdir do |formula_directory|
      formula_path = File.join(formula_directory, "stock-tui.rb")
      original = source_formula("0.3.2", revision: 1)
      File.write(formula_path, original)

      result = Updater::Runner.new(formula_path: formula_path, client: UnexpectedClient.new).run(current_only: true)
      refute result.changed
      assert_equal Digest::SHA256.hexdigest(original), result.formula_sha256
      assert_equal "0.3.2", result.version
      assert_equal "v0.3.2", result.tag
      assert_equal original, File.binread(formula_path)
    end
  end

  def test_runner_verifies_then_atomically_renders_new_release
    directory, payload = release_fixture("0.3.3")
    release = Updater::Release.from_json(JSON.generate(payload))
    client = FakeClient.new(release, directory)

    Dir.mktmpdir do |formula_directory|
      formula_path = File.join(formula_directory, "stock-tui.rb")
      File.write(formula_path, source_formula("0.3.2", revision: 1))

      result = Updater::Runner.new(formula_path: formula_path, client: client).run
      assert result.changed
      assert_equal Digest::SHA256.file(formula_path).hexdigest, result.formula_sha256
      assert_equal 1, client.download_count
      assert_equal "0.3.3", Updater.formula_version(File.read(formula_path)).to_s
      refute_match(/^\s*revision /, File.read(formula_path))
    end
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_runner_leaves_formula_unchanged_when_verification_fails
    directory, payload = release_fixture("0.3.3")
    release = Updater::Release.from_json(JSON.generate(payload))
    archive = Updater.archive_names(release.version).values.first
    File.open(File.join(directory, archive), "ab") { |file| file.write("tampered") }
    client = FakeClient.new(release, directory)

    Dir.mktmpdir do |formula_directory|
      formula_path = File.join(formula_directory, "stock-tui.rb")
      original = source_formula("0.3.2", revision: 1)
      File.write(formula_path, original)

      assert_raises(Updater::Error) { Updater::Runner.new(formula_path: formula_path, client: client).run }
      assert_equal original, File.binread(formula_path)
    end
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_runner_rechecks_release_metadata_before_writing
    directory, payload = release_fixture("0.3.3")
    release = Updater::Release.from_json(JSON.generate(payload))
    changed_payload = Marshal.load(Marshal.dump(payload))
    changed_payload["assets"].first["id"] += 100
    refreshed_release = Updater::Release.from_json(JSON.generate(changed_payload))
    client = ChangingClient.new(release, refreshed_release, directory)

    Dir.mktmpdir do |formula_directory|
      formula_path = File.join(formula_directory, "stock-tui.rb")
      original = source_formula("0.3.2", revision: 1)
      File.write(formula_path, original)

      error = assert_raises(Updater::Error) do
        Updater::Runner.new(formula_path: formula_path, client: client).run
      end
      assert_match "metadata changed", error.message
      assert_equal original, File.binread(formula_path)
    end
  ensure
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  def test_validation_job_uses_homebrew_portable_ruby
    workflow = File.read(File.expand_path("../.github/workflows/autobump.yml", __dir__))
    validation_job = workflow[/^  validate:\n(.*?)(?=^  finalize:\n)/m, 1]

    refute_nil validation_job
    assert_includes validation_job, "brew ruby"
    refute_match(/(?<!brew )\bruby\b/, validation_job)
  end

  private

  def source_formula(version, revision: nil)
    revision_line = revision ? "  revision #{revision}\n" : ""
    <<~RUBY
      class StockTui < Formula
        desc "Stock TUI"
        homepage "https://example.test"
        url "https://github.com/chatcode-lab/stock-tui/archive/refs/tags/v#{version}.tar.gz"
        sha256 "#{"a" * 64}"
      #{revision_line}end
    RUBY
  end

  def release_fixture(version)
    directory = Dir.mktmpdir("stock-tui-updater-test-")
    names = Updater.archive_names(Updater::Version.from_string(version)).values

    names.each { |name| File.binwrite(File.join(directory, name), "contents for #{name}\n") }
    manifest_lines = names.map do |name|
      "#{Digest::SHA256.file(File.join(directory, name)).hexdigest}  #{name}"
    end
    manifest = "#{manifest_lines.join("\n")}\n"
    File.binwrite(File.join(directory, "SHA256SUMS"), manifest)

    assets = ["SHA256SUMS", *names].each_with_index.map do |name, index|
      path = File.join(directory, name)
      {
        "id"     => index + 1,
        "name"   => name,
        "state"  => "uploaded",
        "size"   => File.size(path),
        "digest" => "sha256:#{Digest::SHA256.file(path).hexdigest}",
      }
    end

    [
      directory,
      {
        "tag_name"   => "v#{version}",
        "draft"      => false,
        "prerelease" => false,
        "assets"     => assets,
      },
    ]
  end
end

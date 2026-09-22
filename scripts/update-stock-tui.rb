#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "rbconfig"
require "tempfile"
require "tmpdir"

module StockTuiReleaseUpdater
  REPOSITORY = "chatcode-lab/stock-tui"
  SEMVER_SOURCE = "(?:0|[1-9]\\d*)\\.(?:0|[1-9]\\d*)\\.(?:0|[1-9]\\d*)"
  TAG_PATTERN = /\Av(#{SEMVER_SOURCE})\z/
  FORMULA_VERSION_PATTERN = %r{/(?:tags|download)/v(#{SEMVER_SOURCE})(?=[/.])}
  DIGEST_PATTERN = /\Asha256:([0-9a-f]{64})\z/i
  CHECKSUM_LINE_PATTERN = /\A([0-9a-f]{64})[ \t]+\*?([^\r\n]+)\z/i
  MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
  MAX_MANIFEST_BYTES = 1024 * 1024

  TARGETS = {
    macos_arm:   "aarch64-apple-darwin",
    macos_intel: "x86_64-apple-darwin",
    linux_arm:   "aarch64-unknown-linux-musl",
    linux_intel: "x86_64-unknown-linux-musl",
  }.freeze

  class Error < StandardError; end

  class Version
    include Comparable

    attr_reader :parts

    def self.from_tag(tag)
      match = TAG_PATTERN.match(tag.to_s)
      raise Error, "release tag must be strict stable SemVer (vMAJOR.MINOR.PATCH): #{tag.inspect}" unless match

      new(match[1])
    end

    def self.from_string(value)
      raise Error, "invalid SemVer version: #{value.inspect}" unless /\A#{SEMVER_SOURCE}\z/o.match?(value.to_s)

      new(value.to_s)
    end

    def initialize(value)
      @value = value
      @parts = value.split(".").map(&:to_i).freeze
    end

    def <=>(other)
      parts <=> other.parts
    end

    def to_s
      @value
    end

    def tag
      "v#{self}"
    end
  end

  Asset = Struct.new(:id, :name, :digest, :byte_size, keyword_init: true)

  class Release
    attr_reader :version, :assets

    def self.from_json(json)
      payload = JSON.parse(json)
      from_payload(payload)
    rescue JSON::ParserError => e
      raise Error, "invalid release JSON: #{e.message}"
    end

    def self.latest_from_json(json)
      pages = JSON.parse(json)
      pages = [pages] unless pages.is_a?(Array)
      pages = [pages] unless pages.all?(Array)

      releases = pages.flatten(1)
      candidates = releases.each_with_object([]) do |payload, values|
        next unless payload.is_a?(Hash)
        next if payload["draft"] != false || payload["prerelease"] != false
        next unless TAG_PATTERN.match?(payload["tag_name"].to_s)

        values << [Version.from_tag(payload["tag_name"]), payload]
      end
      raise Error, "GitHub returned no stable SemVer releases" if candidates.empty?

      highest_version = candidates.map(&:first).max
      highest_releases = candidates.select { |version, _payload| version == highest_version }
      raise Error, "GitHub returned duplicate releases for #{highest_version}" if highest_releases.length != 1

      from_payload(highest_releases.first.last)
    rescue JSON::ParserError => e
      raise Error, "invalid releases JSON: #{e.message}"
    end

    def self.from_payload(payload)
      raise Error, "latest release response must be a JSON object" unless payload.is_a?(Hash)
      raise Error, "latest release draft state is invalid" if payload["draft"] != false
      raise Error, "latest release prerelease state is invalid" if payload["prerelease"] != false

      version = Version.from_tag(payload["tag_name"])
      raw_assets = payload["assets"]
      raise Error, "latest release has no asset list" unless raw_assets.is_a?(Array)
      raise Error, "latest release contains malformed assets" unless raw_assets.all?(Hash)

      expected_names = ["SHA256SUMS", *StockTuiReleaseUpdater.archive_names(version).values]
      grouped_assets = raw_assets.group_by { |asset| asset["name"] }
      assets = expected_names.to_h do |name|
        matches = grouped_assets.fetch(name, [])
        raise Error, "release must contain exactly one uploaded #{name} asset" if matches.length != 1

        raw_asset = matches.first
        raise Error, "release asset is not uploaded: #{name}" if raw_asset["state"] != "uploaded"

        byte_size = raw_asset["size"]
        raise Error, "release asset is empty: #{name}" unless byte_size.is_a?(Integer)
        raise Error, "release asset is empty: #{name}" unless byte_size.positive?

        maximum_size = (name == "SHA256SUMS") ? MAX_MANIFEST_BYTES : MAX_ARCHIVE_BYTES
        raise Error, "release asset is unexpectedly large: #{name}" if byte_size > maximum_size

        asset_id = raw_asset["id"]
        raise Error, "release asset has no valid numeric ID: #{name}" unless asset_id.is_a?(Integer)
        raise Error, "release asset has no valid numeric ID: #{name}" unless asset_id.positive?

        digest_match = DIGEST_PATTERN.match(raw_asset["digest"].to_s)
        raise Error, "release asset has no valid SHA-256 digest: #{name}" unless digest_match

        [name, Asset.new(id: asset_id, name: name, digest: digest_match[1].downcase, byte_size: byte_size)]
      end

      new(version: version, assets: assets)
    end

    def initialize(version:, assets:)
      @version = version
      @assets = assets.freeze
    end

    def tag
      version.tag
    end

    def fingerprint
      [
        version.to_s,
        assets.values.sort_by(&:name).map { |asset| [asset.id, asset.name, asset.digest, asset.byte_size] },
      ]
    end
  end

  module_function

  def archive_names(version)
    TARGETS.transform_values { |target| "stock-tui-v#{version}-#{target}.tar.gz" }
  end

  def formula_version(contents)
    versions = contents.scan(FORMULA_VERSION_PATTERN).flatten.uniq
    raise Error, "formula must contain exactly one consistent stable version" if versions.length != 1

    Version.from_string(versions.first)
  end

  def parse_checksums(contents)
    checksums = {}
    contents.each_line.with_index(1) do |line, line_number|
      next if line.strip.empty?

      match = CHECKSUM_LINE_PATTERN.match(line.chomp)
      raise Error, "invalid SHA256SUMS line #{line_number}" unless match

      name = match[2]
      unsafe_name = File.basename(name) != name || name.include?("\\") || name == "." || name == ".."
      if unsafe_name
        raise Error, "unsafe filename in SHA256SUMS line #{line_number}"
      end
      raise Error, "duplicate SHA256SUMS entry: #{name}" if checksums.key?(name)

      checksums[name] = match[1].downcase
    end
    checksums
  end

  def verify_downloads(release, directory)
    actual_digests = release.assets.to_h do |name, asset|
      path = File.join(directory, name)
      raise Error, "downloaded asset is missing: #{name}" unless File.file?(path)
      raise Error, "downloaded asset must not be a symlink: #{name}" if File.symlink?(path)
      raise Error, "downloaded asset size changed: #{name}" if File.size(path) != asset.byte_size

      digest = Digest::SHA256.file(path).hexdigest
      raise Error, "GitHub asset digest mismatch: #{name}" if digest != asset.digest

      [name, digest]
    end

    manifest_path = File.join(directory, "SHA256SUMS")
    manifest = parse_checksums(File.binread(manifest_path))
    archive_names(release.version).each_value do |name|
      expected = manifest[name]
      raise Error, "SHA256SUMS is missing #{name}" unless expected
      raise Error, "SHA256SUMS mismatch: #{name}" if expected != actual_digests.fetch(name)
    end

    archive_names(release.version).values.to_h { |name| [name, actual_digests.fetch(name)] }
  end

  def render_formula(release, checksums)
    names = archive_names(release.version)
    base_url = "https://github.com/#{REPOSITORY}/releases/download/#{release.tag}"

    <<~RUBY
      class StockTui < Formula
        desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
        homepage "https://github.com/#{REPOSITORY}"
        license "MIT"

        on_macos do
          on_arm do
            url "#{base_url}/#{names.fetch(:macos_arm)}"
            sha256 "#{checksums.fetch(names.fetch(:macos_arm))}"
          end

          on_intel do
            url "#{base_url}/#{names.fetch(:macos_intel)}"
            sha256 "#{checksums.fetch(names.fetch(:macos_intel))}"
          end
        end

        on_linux do
          on_arm do
            url "#{base_url}/#{names.fetch(:linux_arm)}"
            sha256 "#{checksums.fetch(names.fetch(:linux_arm))}"
          end

          on_intel do
            url "#{base_url}/#{names.fetch(:linux_intel)}"
            sha256 "#{checksums.fetch(names.fetch(:linux_intel))}"
          end
        end

        def install
          bin.install "stock-tui"
        end

        test do
          assert_match version.to_s, shell_output("\#{bin}/stock-tui --version")
        end
      end
    RUBY
  end

  def atomic_write(path, contents)
    stat = File.stat(path)
    directory = File.dirname(path)
    Tempfile.create([".#{File.basename(path)}", ".tmp"], directory) do |file|
      file.chmod(stat.mode & 0777)
      file.write(contents)
      file.flush
      file.fsync

      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", file.path)
      raise Error, "generated formula is invalid Ruby: #{stderr.strip}" unless status.success?

      File.rename(file.path, path)
    end
  end

  class GitHubClient
    def latest_release
      json = capture("gh", "api", "--paginate", "--slurp", "repos/#{REPOSITORY}/releases?per_page=100")
      Release.latest_from_json(json)
    end

    def download(release, directory)
      release.assets.each_value do |asset|
        path = File.join(directory, asset.name)
        capture_asset(
          asset,
          path,
          "gh", "api", "-H", "Accept: application/octet-stream",
          "repos/#{REPOSITORY}/releases/assets/#{asset.id}"
        )
      end
    end

    private

    def capture(*command)
      stdout, stderr, status = Open3.capture3(*command)
      return stdout if status.success?

      message = stderr.strip
      message = "no diagnostic output" if message.empty?
      raise Error, "#{command.first} command failed: #{message}"
    end

    def capture_asset(asset, path, *command)
      diagnostic = nil
      status = nil
      total = 0

      Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        stderr_reader = Thread.new { stderr.read }
        begin
          File.open(path, "wb") do |file|
            while (chunk = stdout.read(64 * 1024))
              total += chunk.bytesize
              raise Error, "download exceeded API size: #{asset.name}" if total > asset.byte_size

              file.write(chunk)
            end
          end
        rescue
          begin
            Process.kill("TERM", wait_thread.pid)
          rescue Errno::ESRCH
            nil
          end
          raise
        ensure
          diagnostic = stderr_reader.value
          status = wait_thread.value
        end
      end

      unless status.success?
        message = diagnostic.to_s.strip
        message = "no diagnostic output" if message.empty?
        raise Error, "#{command.first} command failed while downloading #{asset.name}: #{message}"
      end
      raise Error, "downloaded asset size changed: #{asset.name}" if total != asset.byte_size
    rescue
      FileUtils.rm_f(path)
      raise
    end
  end

  Result = Struct.new(:changed, :formula_sha256, :version, :tag, keyword_init: true)

  class Runner
    def initialize(formula_path:, client: GitHubClient.new)
      @formula_path = formula_path
      @client = client
    end

    def run(current_only: false)
      raise Error, "formula must be a regular file" unless File.file?(@formula_path)
      raise Error, "formula must be a regular file" if File.symlink?(@formula_path)

      current_version = StockTuiReleaseUpdater.formula_version(File.read(@formula_path))
      if current_only
        return Result.new(
          changed:        false,
          formula_sha256: Digest::SHA256.file(@formula_path).hexdigest,
          version:        current_version.to_s,
          tag:            current_version.tag,
        )
      end

      release = @client.latest_release

      if release.version < current_version
        raise Error, "refusing to downgrade formula from #{current_version} to #{release.version}"
      end
      if release.version == current_version
        return Result.new(
          changed:        false,
          formula_sha256: Digest::SHA256.file(@formula_path).hexdigest,
          version:        release.version.to_s,
          tag:            release.tag,
        )
      end

      Dir.mktmpdir("stock-tui-release-") do |directory|
        @client.download(release, directory)
        checksums = StockTuiReleaseUpdater.verify_downloads(release, directory)
        refreshed_release = @client.latest_release
        if refreshed_release.fingerprint != release.fingerprint
          raise Error, "release metadata changed while assets were being verified"
        end

        contents = StockTuiReleaseUpdater.render_formula(release, checksums)
        StockTuiReleaseUpdater.atomic_write(@formula_path, contents)
      end

      Result.new(
        changed:        true,
        formula_sha256: Digest::SHA256.file(@formula_path).hexdigest,
        version:        release.version.to_s,
        tag:            release.tag,
      )
    end
  end

  def write_github_output(path, result)
    return unless path

    File.open(path, "a") do |file|
      file.puts "changed=#{result.changed}"
      file.puts "formula_sha256=#{result.formula_sha256}" if result.formula_sha256
      file.puts "version=#{result.version}"
      file.puts "tag=#{result.tag}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { current_only: false, formula: "Formula/stock-tui.rb" }
  OptionParser.new do |parser|
    parser.banner = "Usage: update-stock-tui.rb [options]"
    parser.on("--current-only", "Read the current formula without resolving releases") do
      options[:current_only] = true
    end
    parser.on("--formula PATH", "Formula to update") { |path| options[:formula] = path }
    parser.on("--github-output PATH", "Append step outputs to PATH") { |path| options[:github_output] = path }
  end.parse!

  begin
    result = StockTuiReleaseUpdater::Runner.new(formula_path: options.fetch(:formula)).run(
      current_only: options.fetch(:current_only),
    )
    StockTuiReleaseUpdater.write_github_output(options[:github_output], result)
    action = result.changed ? "updated" : "already current"
    puts "stock-tui formula #{action} at #{result.tag}"
  rescue StockTuiReleaseUpdater::Error, Errno::ENOENT => e
    warn "stock-tui formula update failed: #{e.message}"
    exit 1
  end
end

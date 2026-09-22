class StockTui < Formula
  desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
  homepage "https://github.com/chatcode-lab/stock-tui"
  url "https://github.com/chatcode-lab/stock-tui/archive/refs/tags/v0.3.2.tar.gz"
  sha256 "bfb366c6f7ae69c9aa054f77296d510c8184712a9b8136403a52ff3298960223"
  license "MIT"

  bottle do
    root_url "https://github.com/chatcode-lab/homebrew-tap/releases/download/stock-tui-0.3.2"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "8c5fd9e411eb09b2ae989b3c3d1eb6680f727085eab06ae9f509cb3548062895"
    sha256 cellar: :any,                 x86_64_linux: "64429217800db4ca63f2f8de240c3dc6d50e63c3b8b4d254e19016b6a1a39150"
  end

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/stock-tui --version")
  end
end

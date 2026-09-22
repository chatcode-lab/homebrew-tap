class StockTui < Formula
  desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
  homepage "https://github.com/chatcode-lab/stock-tui"
  url "https://github.com/chatcode-lab/stock-tui/archive/refs/tags/v0.3.2.tar.gz"
  sha256 "bfb366c6f7ae69c9aa054f77296d510c8184712a9b8136403a52ff3298960223"
  license "MIT"

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/stock-tui --version")
  end
end

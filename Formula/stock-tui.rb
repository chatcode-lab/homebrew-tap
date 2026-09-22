class StockTui < Formula
  desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
  homepage "https://github.com/chatcode-lab/stock-tui"
  url "https://github.com/chatcode-lab/stock-tui/archive/refs/tags/v0.3.1.tar.gz"
  sha256 "84eb34a42c1939877e36d4d00afbeb61f519e7a05cb48489760d75c1479f6a77"
  license "MIT"

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/stock-tui --version")
  end
end

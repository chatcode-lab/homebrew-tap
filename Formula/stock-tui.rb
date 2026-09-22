class StockTui < Formula
  desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
  homepage "https://github.com/chatcode-lab/stock-tui"
  url "https://github.com/chatcode-lab/stock-tui/archive/refs/tags/v0.3.1.tar.gz"
  sha256 "84eb34a42c1939877e36d4d00afbeb61f519e7a05cb48489760d75c1479f6a77"
  license "MIT"

  bottle do
    root_url "https://github.com/chatcode-lab/homebrew-tap/releases/download/stock-tui-0.3.1"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "cdd5df509f50293936ca16a9d39fd016a67decdebe01368ffab94689ad97ec71"
    sha256 cellar: :any,                 x86_64_linux: "4ebeb2139b8826a27311aca12bd04161d41150d2e5cc5897b4d662e85e55322c"
  end

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/stock-tui --version")
  end
end

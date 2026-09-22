class StockTui < Formula
  desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
  homepage "https://github.com/chatcode-lab/stock-tui"
  license "MIT"
  revision 1

  bottle do
    root_url "https://github.com/chatcode-lab/homebrew-tap/releases/download/stock-tui-0.3.2_1"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "7deeb34aa8572a2a5c736dfb0a9d76550a507d8a9def2618e41121983f13dd04"
    sha256 cellar: :any_skip_relocation, sequoia:      "2f1a041b87a47c7203663976ea257cfddd2ddbb4e87ad4ecd0d7201e57f33062"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "88a39628b335b949d24685e9edff9d0abfbc37f1b4874d7ae0edb1f791997b04"
  end

  on_macos do
    on_arm do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.2/stock-tui-v0.3.2-aarch64-apple-darwin.tar.gz"
      sha256 "e013a29c1958ad165861bfe5e317d3fd0241be34343ffba31ad2dee411b86f24"
    end

    on_intel do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.2/stock-tui-v0.3.2-x86_64-apple-darwin.tar.gz"
      sha256 "328018731bb57a3b7c6f74be15ffc775778731b562cc814e05879e1c5f4846b2"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.2/stock-tui-v0.3.2-aarch64-unknown-linux-musl.tar.gz"
      sha256 "ebc1618489b6e2dc1e98509c8b987812a1b00a978a1d6af909a2fedb24c81bf0"
    end

    on_intel do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.2/stock-tui-v0.3.2-x86_64-unknown-linux-musl.tar.gz"
      sha256 "c3163a184d47f2091493a50f6635f083351d81cfee86e5ca029a546d930ae1e6"
    end
  end

  def install
    bin.install "stock-tui"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/stock-tui --version")
  end
end

class StockTui < Formula
  desc "Mouse-first terminal stock market heatmap inspired by StockTouch"
  homepage "https://github.com/chatcode-lab/stock-tui"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.3/stock-tui-v0.3.3-aarch64-apple-darwin.tar.gz"
      sha256 "5071ccc9d413fa452ea8cedeb2b0d70913c2d3dbd1a48680c217550cb0d96031"
    end

    on_intel do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.3/stock-tui-v0.3.3-x86_64-apple-darwin.tar.gz"
      sha256 "5f53af0f2779026451c53b2673c883f57f6f528cba008fe59dec37e10cefba91"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.3/stock-tui-v0.3.3-aarch64-unknown-linux-musl.tar.gz"
      sha256 "25282e66e6ae0976f6267b0ec321a60c145a2c97277e0eb9decf10067d1d1a61"
    end

    on_intel do
      url "https://github.com/chatcode-lab/stock-tui/releases/download/v0.3.3/stock-tui-v0.3.3-x86_64-unknown-linux-musl.tar.gz"
      sha256 "a1e529c9d079b3342dd24577ce9d30806c1c598d2942ba33c2157cbc76eef2cb"
    end
  end

  def install
    bin.install "stock-tui"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/stock-tui --version")
  end
end

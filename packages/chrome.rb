require 'package'

class Chrome < Package
  description 'Google Chrome is a fast, easy to use, and secure web browser.'
  homepage 'https://www.google.com/chrome'
  version '99.0.4844.51-1'
  license 'google-chrome'
  compatibility 'x86_64'
  source_url 'https://dl.google.com/linux/chrome/deb//pool/main/g/google-chrome-stable/google-chrome-stable_99.0.4844.51-1_amd64.deb'
  source_sha256 'a19354b3f8eee069cec49cdc44bea43d7f0cbddf6a94bb49c1e221a4ee757812'

  depends_on 'nspr'
  depends_on 'cairo'
  depends_on 'gtk3'
  depends_on 'expat'
  depends_on 'cras'
  depends_on 'sommelier'

  def self.install
    FileUtils.mkdir_p "#{CREW_DEST_PREFIX}/bin"

    FileUtils.mv 'usr/share', CREW_DEST_PREFIX
    FileUtils.mv 'opt/google/chrome', "#{CREW_DEST_PREFIX}/share"

    FileUtils.ln_s "../share/chrome/google-chrome", "#{CREW_DEST_PREFIX}/bin/google-chrome-stable"
    FileUtils.ln_s "../share/chrome/google-chrome", "#{CREW_DEST_PREFIX}/bin/google-chrome"
  end
end

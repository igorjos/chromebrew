require 'package'

class Jdk15 < Package
  description 'The JDK is a development environment for building applications, applets, and components using the Java programming language.'
  homepage 'https://www.oracle.com/java/technologies/javase-jdk15-downloads.html'
  version '15.0.2'
  license 'Oracle-BCLA-JavaSE'
  compatibility 'x86_64'
  source_url 'SKIP'

  binary_url ({
    x86_64: 'https://gitlab.com/api/v4/projects/26210301/packages/generic/jdk15/15.0.2_x86_64/jdk15-15.0.2-chromeos-x86_64.tar.xz',
  })
  binary_sha256 ({
    x86_64: '76967a212cb4bded9932fa2e44328272472f780a69e1574da9f4412a81de41ae',
  })

  def self.preflight
    abort "JDK8 installed.".lightgreen if Dir.exists? "#{CREW_PREFIX}/share/jdk8"
    abort "JDK11 installed.".lightgreen if Dir.exists? "#{CREW_PREFIX}/share/jdk11"
    abort "JDK16 installed.".lightgreen if Dir.exists? "#{CREW_PREFIX}/share/jdk16"
    abort "JDK17 installed.".lightgreen if Dir.exists? "#{CREW_PREFIX}/share/jdk17"
  end

  def self.install
    jdk_bin = "#{HOME}/Downloads/jdk-#{version}_linux-x64_bin.tar.gz"
    jdk_sha256 = '54b29a3756671fcb4b6116931e03e86645632ec39361bc16ad1aaa67332c7c61'
    unless File.exists? jdk_bin then
      puts
      puts "Oracle now requires an account to download the JDK.".orange
      puts
      puts "You must login at https://login.oracle.com/mysso/signon.jsp and then visit:".orange
      puts "https://www.oracle.com/java/technologies/javase-jdk15-downloads.html".orange
      puts
      puts "Download the JDK for your architecture to #{HOME}/Downloads to continue.".orange
      puts
      abort
    end
    abort 'Checksum mismatch. :/ Try again.'.lightred unless Digest::SHA256.hexdigest( File.read(jdk_bin) ) == jdk_sha256
    system "tar xvf #{jdk_bin}"
    jdk15_dir = "#{CREW_DEST_PREFIX}/share/jdk15"
    FileUtils.mkdir_p "#{jdk15_dir}"
    FileUtils.mkdir_p "#{CREW_DEST_PREFIX}/bin"
    FileUtils.mkdir_p "#{CREW_DEST_MAN_PREFIX}/man1"
    FileUtils.cd "jdk-#{version}" do
      FileUtils.rm_f 'lib/src.zip'
      FileUtils.mv Dir['*'], "#{jdk15_dir}/"
    end
    FileUtils.cd "#{jdk15_dir}/bin" do
      system "find -type f -exec ln -s #{jdk15_dir}/bin/{} #{CREW_DEST_PREFIX}/bin/{} \\;"
    end
    system "compressdoc --gzip -9 #{jdk15_dir}/man/man1"
    FileUtils.cd "#{jdk15_dir}/man/man1" do
      system "find -type f -exec ln -s #{jdk15_dir}/man/man1/{} #{CREW_DEST_MAN_PREFIX}/man1/{} \\;"
    end
  end
end

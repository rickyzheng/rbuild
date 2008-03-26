require 'rubygems'
begin
  require 'rbuild'
rescue Exception
  raise "\n\n**** Please install rbuild gem first ! ****\n\n"
end

$GCC_VER = nil
$BINUTILS_VER = nil
$NEWLIB_VER = nil


$GCC_DOWNLOAD_SITE = "ftp://ftp.gnu.org/pub/gnu/gcc"
$BINUTILS_DOWNLOAD_SITE = "ftp://ftp.gnu.org/pub/gnu/binutils"
$NEWLIB_DOWNLOAD_SITE = "ftp://sources.redhat.com/pub/newlib"

$CURDIR = File.expand_path(Dir.pwd)
$DOWNLOAD_DIR = "./dl"
$prefix = "./gnutool"
$target="arm-elf"
$float_cflag = ""

def shell(cmd, desc = "")
  unless system(cmd)
    Dir.chdir $CURDIR
    raise "Error when: #{cmd}"
  end
end

task :download => :prepare do
  dl = File.expand_path($DOWNLOAD_DIR)
  
  Dir.chdir dl
  f = "gcc-#{$GCC_VER}.tar.bz2"
  shell("wget #{$GCC_DOWNLOAD_SITE}/gcc-#{$GCC_VER}/#{f}") unless File.exist?(f)
  Dir.chdir $CURDIR
  shell("tar -jxvf #{dl}/#{f}") unless File.exist?("gcc-#{$GCC_VER}")
  
  Dir.chdir dl
  f = "binutils-#{$BINUTILS_VER}.tar.gz"
  shell("wget #{$BINUTILS_DOWNLOAD_SITE}/#{f}") unless File.exist?(f)
  Dir.chdir $CURDIR
  shell("tar -zxvf #{dl}/#{f}") unless File.exist?("binutils-#{$BINUTILS_VER}")
  
  Dir.chdir dl
  f = "newlib-#{$NEWLIB_VER}.tar.gz"
  shell("wget #{$NEWLIB_DOWNLOAD_SITE}/#{f}") unless File.exist?(f)
  Dir.chdir $CURDIR
  shell("tar -zxvf #{dl}/#{f}") unless File.exist?("newlib-#{$NEWLIB_VER}")
  
  shell("mv newlib-#{$NEWLIB_VER}/newlib gcc-#{$GCC_VER}/") unless File.exist?("gcc-#{$GCC_VER}/newlib")
  shell("mv newlib-#{$NEWLIB_VER}/libgloss gcc-#{$GCC_VER}/") unless File.exist?("gcc-#{$GCC_VER}/libgloss")
  
end

task :menuconfig do
  rconf = RBuild::RConfig.new 'RConfig'
  rconf.menuconfig()
end

task :prepare do
  rconf = RBuild::RConfig.new 'RConfig'
  rconf.merge!
  $GCC_VER = rconf.get_value(:GCC_VER)
  $BINUTILS_VER = rconf.get_value(:BINUTILS_VER)
  $NEWLIB_VER = rconf.get_value(:NEWLIB_VER)
  $DOWNLOAD_DIR = File.expand_path(rconf.get_value(:DOWNLOAD_DIR))
  $prefix = File.expand_path(rconf.get_value(:PREFIX))
  $float_cflag = rconf.hit?(:SOFT_FLOAT) ? "--with-float=soft" : ""
end

task :diag => :prepare do
  puts "gcc ver: #{$GCC_VER}"
  puts "binutils ver: #{$BINUTILS_VER}"
  puts "newlib ver: #{$NEWLIB_VER}"
  puts "download dir: #{$DOWNLOAD_DIR}"
  puts "install: #{$prefix}"
end

task :build => [:binutils, :gcc] do
  puts "--- OK ----"
end

task :gcc => [:binutils] do
  shell("export PATH=#{$prefix}/bin:${PATH}")
  Dir.chdir $CURDIR
  shell("mkdir -p #{$target}/build/gcc")
  Dir.chdir "#{$target}/build/gcc"
  shell("#{$CURDIR}/configure
    --enable-languages=c,c++
    --with-gnu-ld --with-gnu-as
		--with-newlib
		--with-stabs
		--disable-tls
    #{$float_cflag} 
		--disable-thread
    --target=#{$target}
		--disable-libssp
		--disable-libgomp
	  --enable-interwork --enable-multilib
    --without-headers
    --disable-bootstrap
    --prefix=#{$prefix} -v
    2>&1 | tee gcc_configure.log")
  shell("make    all 2>&1 | tee gcc_make.log")
  shell("make    install 2>&1 | tee gcc_install.log")
  Dir.chdir $CURDIR
end

task :binutils => :download do
  Dir.chdir $CURDIR
  shell("mkdir -p #{$target}/build/binutils")
  Dir.chdir "#{$target}/build/binutils"
  shell("#{$CURDIR}/binutils-#{$BINUTILS_VER}/configure --prefix=#{$prefix} --target=#{$target}
    --disable-nls --enable-debug --disable-threads
    --with-gcc --with-gnu-as --with-gnu-ld --with-stabs #{$float_cflag} 
    2>&1 | tee binutils_configure.log")
  shell("make    all 2>&1 | tee binutils_make.log")
  shell("make    install 2>&1 | tee binutils_install.log")
  Dir.chdir $CURDIR
end

task :clean do
  Dir.chdir $CURDIR
  shell("rm -Rf build/*")
end



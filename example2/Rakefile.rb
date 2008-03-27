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
$target="arm-elf"
$prefix = "./#{$target}"
$float_cflag = ""
$language_cflags = "--enable-languages=c"
$add_gcc_cflags = ""
$with_newlib = true

def shell(cmd, desc = "")
  unless system(cmd)
    Dir.chdir $CURDIR
    raise "Error when invoke: #{cmd}"
  end
end

task :download => :prepare do
  dl = File.expand_path($DOWNLOAD_DIR)
  shell("mkdir -p #{dl}")
  src = $CURDIR + '/src'
  shell("mkdir -p #{src}")
  Dir.chdir dl
  f = "gcc-#{$GCC_VER}.tar.bz2"
  shell("wget #{$GCC_DOWNLOAD_SITE}/gcc-#{$GCC_VER}/#{f}") unless File.exist?(f)
  Dir.chdir src
  shell("tar -jxvf #{dl}/#{f}") unless File.exist?("gcc-#{$GCC_VER}")
  
  Dir.chdir dl
  f = "binutils-#{$BINUTILS_VER}.tar.gz"
  shell("wget #{$BINUTILS_DOWNLOAD_SITE}/#{f}") unless File.exist?(f)
  Dir.chdir src
  shell("tar -zxvf #{dl}/#{f}") unless File.exist?("binutils-#{$BINUTILS_VER}")

  if $with_newlib
    Dir.chdir dl
    f = "newlib-#{$NEWLIB_VER}.tar.gz"
    shell("wget #{$NEWLIB_DOWNLOAD_SITE}/#{f}") unless File.exist?(f)
    Dir.chdir src
    shell("tar -zxvf #{dl}/#{f}") unless File.exist?("newlib-#{$NEWLIB_VER}")
  
    shell("cp -a newlib-#{$NEWLIB_VER}/newlib gcc-#{$GCC_VER}/") unless File.exist?("gcc-#{$GCC_VER}/newlib")
    shell("cp -a newlib-#{$NEWLIB_VER}/libgloss gcc-#{$GCC_VER}/") unless File.exist?("gcc-#{$GCC_VER}/libgloss")
  end

  Dir.chdir $CURDIR
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
  if rconf.hit?(:ENABLE_CPP)
    $language_cflag += ",c++"
  end
  if rconf.hit?(:ARM_THUMB_INTERWORK)
    $add_gcc_cflags += " --enable-interwork"
  end
  if rconf.hit?(:ENABLE_MULTILIB)
    $add_gcc_cflags += " --enable-multilib"
  end
  if rconf.hit?(:WITH_NEWLIB)
    $add_gcc_cflags += " --with-newlib"
  end
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
  shell("mkdir -p build/gcc")
  Dir.chdir "build/gcc"
  s = "#{$CURDIR}/src/gcc-#{$GCC_VER}/configure #{$language_cflag} --with-gnu-ld --with-gnu-as "
  s += "--with-stabs --disable-tls #{$float_cflag} --disable-thread --target=#{$target} "
  s += "--disable-libssp --disable-libgomp #{$add_gcc_cflags} --without-headers "
  s += "--disable-bootstrap --prefix=#{$prefix} -v 2>&1 | tee gcc_configure.log"
  shell(s)
  shell("make    all 2>&1 | tee gcc_make.log")
  shell("make    install 2>&1 | tee gcc_install.log")
  Dir.chdir $CURDIR
end

task :binutils => :download do
  Dir.chdir $CURDIR
  shell("mkdir -p #{$prefix}")
  shell("mkdir -p build/binutils")
  Dir.chdir "build/binutils"
  s = "#{$CURDIR}/src/binutils-#{$BINUTILS_VER}/configure --prefix=#{$prefix} --target=#{$target} "
  s += "--disable-nls --enable-debug --disable-threads --with-gcc --with-gnu-as --with-gnu-ld --with-stabs #{$float_cflag} "
  s += "2>&1 | tee binutils_configure.log"
  shell(s)
  shell("make    all 2>&1 | tee binutils_make.log")
  shell("make    install 2>&1 | tee binutils_install.log")
  Dir.chdir $CURDIR
end

task :clean do
  Dir.chdir $CURDIR
  shell("rm -Rf build/*")
end


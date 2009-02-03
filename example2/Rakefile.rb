#
# arm-elf cross compiler toolchain building script,
# by Ricky Zheng <ricky_gz_zheng@yahoo.co.nz>
#
require 'rubygems'
begin
  require 'rbuild'
rescue Exception
  begin
    load '../lib/rbuild.rb'
  rescue Exception
    raise "\n\n**** Please install rbuild gem first ! ****\n\n"
  end
end

$GCC_VER = nil
$BINUTILS_VER = nil
$NEWLIB_VER = nil

$GCC_DOWNLOAD_SITE = "ftp://ftp.gnu.org/pub/gnu/gcc"
$BINUTILS_DOWNLOAD_SITE = "ftp://ftp.gnu.org/pub/gnu/binutils"
$NEWLIB_DOWNLOAD_SITE = "ftp://sources.redhat.com/pub/newlib"

$CURDIR = File.expand_path(Dir.pwd)
$DOWNLOAD_DIR = "./dl"
$check_integrity = false
$target="arm-elf"
$prefix = "./#{$target}"

$with_newlib = nil
$add_gcc_options = "--with-stabs --disable-tls --disable-libssp --disable-libgomp --without-headers --disable-bootstrap"
$add_bin_options = "--disable-nls --enable-debug --with-gcc --with-gnu-as --with-gnu-ld --with-stabs"

def shell(cmd, desc = "")
  unless system(cmd)
    Dir.chdir $CURDIR
    raise "Error when invoke: #{cmd}"
  end
end

def check_integrity(f)
  return unless $check_integrity
  if File.exist?(f)
    puts "Check #{f} ..."
    if f =~ /\.bz2$/
      unless system("bzip2 -t #{f}")
        `rm -f #{f}`
      end
    elsif f =~ /\.gz$/
      unless system("gzip -t #{f}")
        `rm -f #{f}`
      end
    end    
  end
end

task :download => :prepare do
  dl = File.expand_path($DOWNLOAD_DIR)
  shell("mkdir -p #{dl}")
  src = $CURDIR + '/src'
  shell("mkdir -p #{src}")
  Dir.chdir dl
  f = "gcc-#{$GCC_VER}.tar.bz2"
  check_integrity f
  shell("wget #{$GCC_DOWNLOAD_SITE}/gcc-#{$GCC_VER}/#{f}") unless File.exist?(f)
  Dir.chdir src
  shell("tar -jxvf #{dl}/#{f}") unless File.exist?("gcc-#{$GCC_VER}")
  
  Dir.chdir dl
  f = "binutils-#{$BINUTILS_VER}.tar.gz"
  check_integrity f
  shell("wget #{$BINUTILS_DOWNLOAD_SITE}/#{f}") unless File.exist?(f)
  Dir.chdir src
  shell("tar -zxvf #{dl}/#{f}") unless File.exist?("binutils-#{$BINUTILS_VER}")

  if $with_newlib
    Dir.chdir dl
    f = "newlib-#{$NEWLIB_VER}.tar.gz"
    check_integrity f
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
  rconf.merge!
  rconf.menuconfig()
end

task :prepare do
  rconf = RBuild::RConfig.new 'RConfig'
  rconf.merge!
  $GCC_VER = rconf.get_value(:GCC_VER)
  $BINUTILS_VER = rconf.get_value(:BINUTILS_VER)
  $NEWLIB_VER = rconf.get_value(:NEWLIB_VER)
  $DOWNLOAD_DIR = File.expand_path(rconf.get_value(:DOWNLOAD_DIR))
  $check_integrity = rconf.hit?(:CHECK_INTEGRITY)
  $prefix = File.expand_path(rconf.get_value(:PREFIX))

  $add_gcc_options += " --enable-languages=c"
  $add_gcc_options += ",c++" if rconf.hit?(:ENABLE_CPP)
  
  $add_gcc_options += " --prefix=#{$prefix} --target=#{$target}"
  $add_bin_options += " --prefix=#{$prefix} --target=#{$target}"
  if rconf.hit?(:SOFT_FLOAT)
    $add_gcc_options += " --with-float=soft"
    $add_bin_options += " --with-float=soft"
  end
  $add_gcc_options += " --enable-interwork" if rconf.hit?(:ARM_THUMB_INTERWORK)
  $add_gcc_options += " --enable-multilib" if rconf.hit?(:ENABLE_MULTILIB)
  $add_gcc_options += " --with-newlib" if rconf.hit?(:WITH_NEWLIB)
  if rconf.hit?(:DISABLE_THREAD)
    $add_gcc_options += " --disable-thread"
    $add_bin_options += " --disable-thread"
  end
end

task :diag => :prepare do
  puts "gcc ver: #{$GCC_VER}"
  puts "binutils ver: #{$BINUTILS_VER}"
  puts "newlib ver: #{$NEWLIB_VER}"
  puts "download dir: #{$DOWNLOAD_DIR}"
  puts "install: #{$prefix}"
  puts "gcc configure: #{$add_gcc_options}"
  puts "binutils configure: #{$add_bin_options}"
end

task :all => :build

task :build => [:binutils, :gcc] do
  puts "-------------------------------------"
  puts "The new #{$target} toolchain is ready: "
  puts "   #{$prefix}"
  puts "-------------------------------------"
end

task :gcc => [:binutils] do
  shell "export PATH=#{$prefix}/bin:${PATH}"
  Dir.chdir $CURDIR
  shell "mkdir -p build/gcc"
  Dir.chdir "build/gcc"
  shell "#{$CURDIR}/src/gcc-#{$GCC_VER}/configure #{$gcc_add_cflags} -v 2>&1 | tee gcc_configure.log"
  shell "make all 2>&1 | tee gcc_make.log"
  shell "make install 2>&1 | tee gcc_install.log"
  Dir.chdir $CURDIR
end

task :binutils => :download do
  Dir.chdir $CURDIR
  shell "mkdir -p #{$prefix}"
  shell "mkdir -p build/binutils"
  Dir.chdir "build/binutils"
  shell "#{$CURDIR}/src/binutils-#{$BINUTILS_VER}/configure #{$add_bin_options} -v 2>&1 | tee binutils_configure.log"
  shell "make all 2>&1 | tee binutils_make.log"
  shell "make install 2>&1 | tee binutils_install.log"
  Dir.chdir $CURDIR
end

task :clean do
  Dir.chdir $CURDIR
  shell "rm -Rf build/*"
end



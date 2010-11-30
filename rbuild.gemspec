$:.unshift '../lib'
require 'rubygems'

spec = Gem::Specification.new do |s|
  s.name = 'rbuild'
  s.version = "0.1.3"
  s.required_ruby_version = ">= 1.8.1"
  s.author = 'Ricky Zheng'
  s.homepage = 'http://rbuild.sf.net'
  s.platform = Gem::Platform::RUBY
  s.summary = "RBuild is a software configure/build tool"
  s.description = <<-EOF
  RBuild is a KBuild like software configure/build system in Ruby DSL
EOF
  s.email = "ricky_gz_zheng@yahoo.co.nz"
  s.files = Dir.glob("example/**/*").delete_if {|item| item.include?(".svn")}
  s.files = "example2/RConfig"
  s.files = "example2/Rakefile.rb"
  s.files += Dir.glob("lib/**/*.rb").delete_if {|item| item.include?(".svn")}
  s.files += Dir.glob("README*")
  s.require_path = 'lib'
  #s.autorequire = 'lib/rbuild.rb'
  s.has_rdoc = false
end

if $0==__FILE__
  require 'rubygems/builder'
  Gem::Builder.new(spec).build
end


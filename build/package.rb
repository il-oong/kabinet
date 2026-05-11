#!/usr/bin/env ruby
# ============================================================
# Kabinet .rbz Packager
# Run from the project root (스케치업 루비/):
#   ruby build/package.rb
# Requires: rubyzip gem on the DEV machine (not inside plugin)
#   gem install rubyzip
# ============================================================
require 'rubygems'
require 'zip'
require 'fileutils'

ROOT   = File.expand_path('..', __dir__)
OUTPUT = File.join(ROOT, 'kabinet.rbz')

puts "Building kabinet.rbz from #{ROOT}..."

File.delete(OUTPUT) if File.exist?(OUTPUT)

Zip::File.open(OUTPUT, Zip::File::CREATE) do |zip|
  # Top-level loader
  loader = File.join(ROOT, 'kabinet_loader.rb')
  zip.add('kabinet_loader.rb', loader)

  # Everything in kabinet/
  Dir[File.join(ROOT, 'kabinet', '**', '*')].each do |path|
    next if File.directory?(path)
    relative = path.sub(ROOT + File::SEPARATOR, '')
    zip.add(relative.gsub('\\', '/'), path)
  end
end

size_kb = (File.size(OUTPUT) / 1024.0).round(1)
puts "Done: #{OUTPUT} (#{size_kb} KB)"
puts ""
puts "설치 방법:"
puts "  SketchUp → Extensions → Extension Manager → Install Extension"
puts "  → kabinet.rbz 선택"

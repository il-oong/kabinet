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
  # Ship only the EP workflow. Legacy generators remain in source history,
  # but are neither installed nor loaded by the v2 extension.
  File.readlines(File.join(__dir__, 'ep_release_files.txt'), chomp: true).each do |relative|
    next if relative.empty?
    zip.add(relative, File.join(ROOT, relative))
  end
end

size_kb = (File.size(OUTPUT) / 1024.0).round(1)
puts "Done: #{OUTPUT} (#{size_kb} KB)"
puts ""
puts "설치 방법:"
puts "  SketchUp → Extensions → Extension Manager → Install Extension"
puts "  → kabinet.rbz 선택"

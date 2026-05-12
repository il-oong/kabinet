require 'sketchup.rb'
require 'json'

module Kabinet
  PLUGIN_DIR = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)
end

# Foundation
require File.join(Kabinet::PLUGIN_DIR, 'version')
require File.join(Kabinet::PLUGIN_DIR, 'constants')

# Persistence + geometry primitives
require File.join(Kabinet::PLUGIN_DIR, 'persistence', 'attributes')
require File.join(Kabinet::PLUGIN_DIR, 'persistence', 'schema')
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'transforms')
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'builder')
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'joinery')

# Domain
require File.join(Kabinet::PLUGIN_DIR, 'core', 'panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'carcase')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'door_panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'ep_finish_panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'accessory')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'shelf_module')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'drawer_module')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'assembly')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'cut_list')

# Commands
require File.join(Kabinet::PLUGIN_DIR, 'commands', 'generate')
require File.join(Kabinet::PLUGIN_DIR, 'commands', 'regenerate')
require File.join(Kabinet::PLUGIN_DIR, 'commands', 'export')

# Output (drawings)
require File.join(Kabinet::PLUGIN_DIR, 'output', 'dimensions')
require File.join(Kabinet::PLUGIN_DIR, 'output', 'views')
require File.join(Kabinet::PLUGIN_DIR, 'output', 'png_export')
require File.join(Kabinet::PLUGIN_DIR, 'output', 'pdf_bundler')

# UI (last — depends on everything)
require File.join(Kabinet::PLUGIN_DIR, 'ui', 'dialog')
require File.join(Kabinet::PLUGIN_DIR, 'ui', 'menu')

module Kabinet
  unless file_loaded?(__FILE__)
    Kabinet::UI::Menu.install
    file_loaded(__FILE__)
  end
end

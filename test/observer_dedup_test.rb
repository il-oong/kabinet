# frozen_string_literal: false
# 같은 그룹에 스케일 옵저버가 한 번만 달리는지 (중복되면 스케일이 2번 적용됨)
module Sketchup
  class EntityObserver; end
  class SelectionObserver; end
  class AppObserver; end
  class Group; end
  class ComponentInstance; end
end
module Kabinet
  module Persistence; module Attributes; def self.assembly?(e); true; end; end; end
  module Commands; end
end
require_relative '../kabinet/commands/generate'
require_relative '../kabinet/commands/regenerate'

def assert(v, m); raise m unless v; end
Model = Struct.new(:guid)
class FakeGroup < Sketchup::Group
  attr_reader :model, :entityID, :added
  def initialize(m, id); @model = m; @entityID = id; @added = 0; end
  def add_observer(_o); @added += 1; end
end

g = FakeGroup.new(Model.new('m1'), 7)
3.times { Kabinet::Commands::Generate.install_observer(g) }
assert g.added == 1, "observer added #{g.added}x"
g2 = FakeGroup.new(Model.new('m1'), 8)
Kabinet::Commands::Generate.install_observer(g2)
assert g2.added == 1, 'second group needs its own observer'
sel = [g, g2, Object.new]
sel.define_singleton_method(:each_entity) {}
Kabinet::Commands::AssemblySelectionObserver.new.attach(sel)
assert g.added == 1 && g2.added == 1, 'selection attach must not duplicate'
puts 'observer_dedup_test: OK'

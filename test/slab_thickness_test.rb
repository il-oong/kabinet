# 판재 두께 일괄 변경: 판재 판별(얇은 축)
module Kabinet; end
require_relative '../kabinet/commands/slab_thickness'
ST = Kabinet::Commands::SlabThickness
def assert(v, m); raise m unless v; end
assert ST.slab_axis([600, 15, 2000]) == 1, 'thin Y'
assert ST.slab_axis([20, 580, 2232]) == 0, 'side panel X'
assert ST.slab_axis([900, 580, 18]) == 2, 'shelf Z'
assert ST.slab_axis([30, 30, 700]).nil?, 'leg is not a slab'
assert ST.slab_axis([900, 580, 740]).nil?, 'box is not a slab'
assert ST.slab_axis([1, 500, 500]).nil?, 'too thin'
puts 'slab_thickness_test: OK'

# resize: 15T 판재(Y 두께) → 18T: Y 최대면 꼭짓점만 +3mm 이동, 공유 정의는 make_unique
require_relative 'support/geom'
module Geom
  class Transformation
    def self.translation(v); new(Point3d.new(v.x, v.y, v.z)); end
  end
  class BoundingBox
    def width; max.x - min.x; end
  end
end
module Sketchup
  class Vertex; attr_accessor :position; def initialize(p); @position = p; end; end
  class Edge; attr_reader :vertices; def initialize(a, b); @vertices = [a, b]; end; end
  class Entities < Array
    def transform_entities(tr, verts); verts.each { |v| v.position = v.position.transform(tr) }; end
  end
  class Def
    attr_reader :entities, :instances
    def initialize(ents); @entities = ents; @instances = []; end
    def bounds; b = Geom::BoundingBox.new; @entities.flat_map(&:vertices).each { |v| b.add(v.position) }; b; end
  end
  class Group
    attr_accessor :definition, :transformation, :made_unique
    def make_unique; @made_unique = true; end
  end
end
def slab(w, t, h)
  pts = [0, w].product([0, t], [0, h]).map { |x, y, z| Sketchup::Vertex.new(Geom::Point3d.new(x.mm, y.mm, z.mm)) }
  edges = Sketchup::Entities.new(pts.each_slice(2).map { |a, b| Sketchup::Edge.new(a, b) })
  g = Sketchup::Group.new
  g.definition = Sketchup::Def.new(edges)
  g.definition.instances << g
  g.transformation = Geom::Transformation.new
  g
end
g = slab(600, 15, 2000)
assert ST.resize(g, 18) == true, 'resized'
d = ST.dims_mm(g)
assert (d[1] - 18).abs < 1e-6 && (d[0] - 600).abs < 1e-6 && (d[2] - 2000).abs < 1e-6, "dims #{d}"
assert !g.made_unique, 'not shared → no make_unique'
assert ST.resize(g, 18) == false, 'already 18'
g2 = slab(600, 15, 2000); g2.definition.instances << :other
ST.resize(g2, 18)
assert g2.made_unique, 'shared definition made unique'
puts 'slab_thickness_test: resize OK'

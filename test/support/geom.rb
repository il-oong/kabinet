# Minimal affine geometry double; lengths use SketchUp's internal inches.
class Numeric
  def mm; to_f / 25.4; end
  def degrees; to_f * Math::PI / 180; end
end

module Geom
  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x, y, z); @x, @y, @z = x, y, z; end
    def to_a; [x, y, z]; end
    def cross(v); Vector3d.new(y*v.z-z*v.y, z*v.x-x*v.z, x*v.y-y*v.x); end
    def dot(v); x*v.x+y*v.y+z*v.z; end
    def length; Math.sqrt(dot(self)); end
    def normalize; raise 'Zero vector' if length == 0; Vector3d.new(*to_a.map { |n| n/length }); end
    def reverse!; @x, @y, @z = -x, -y, -z; self; end
    def transform(t); Vector3d.new(*t.apply(to_a, 0)); end
  end

  class Point3d < Vector3d
    def initialize(*args); super(*(args.size == 1 ? args.first.to_a : args)); end
    def -(p); Vector3d.new(x-p.x, y-p.y, z-p.z); end
    def offset(v, d = v.length)
      n = v.normalize
      Point3d.new(x+n.x*d, y+n.y*d, z+n.z*d)
    end
    def transform(t); Point3d.new(*t.apply(to_a, 1)); end
  end

  class Transformation
    attr_reader :matrix
    def initialize(origin = nil)
      @matrix = [[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]]
      3.times { |i| @matrix[i][3] = origin.to_a[i] } if origin
    end
    def apply(values, w)
      3.times.map { |i| 3.times.sum { |j| @matrix[i][j]*values[j] } + @matrix[i][3]*w }
    end
    def *(other)
      t = Transformation.new
      4.times { |i| 4.times { |j| t.matrix[i][j] = 4.times.sum { |k| matrix[i][k]*other.matrix[k][j] } } }
      t
    end
    def xaxis; Vector3d.new(*3.times.map { |i| matrix[i][0] }); end
    def yaxis; Vector3d.new(*3.times.map { |i| matrix[i][1] }); end
    def zaxis; Vector3d.new(*3.times.map { |i| matrix[i][2] }); end
    def self.rotation(origin, axis, angle)
      raise 'Test double supports Z rotation only' unless axis.z.abs == 1
      t = new
      c, s = Math.cos(angle), Math.sin(angle)
      t.matrix[0][0], t.matrix[0][1], t.matrix[1][0], t.matrix[1][1] = c, -s, s, c
      new(origin) * t * new(Point3d.new(*origin.to_a.map { |v| -v }))
    end
  end

  class BoundingBox
    def initialize; @points = []; end
    def add(*points); @points.concat(points.flatten); self; end
    def min; Point3d.new(*3.times.map { |i| @points.map { |p| p.to_a[i] }.min }); end
    def max; Point3d.new(*3.times.map { |i| @points.map { |p| p.to_a[i] }.max }); end
    def width; max.x-min.x; end
    def height; max.y-min.y; end
    def depth; max.z-min.z; end
    def diagonal; (max-min).length; end
    def center; Point3d.new(*3.times.map { |i| (min.to_a[i]+max.to_a[i])/2.0 }); end
  end
end

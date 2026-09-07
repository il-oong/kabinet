# In-memory geometry target for the existing Assembly/Builder pipeline.
# No SketchUp entities, attributes, materials or undo operations are modified.
module Kabinet
  module Geometry
    module Preview
      class Group
        attr_accessor :transformation, :name, :locked
        attr_reader :entities

        def initialize
          @transformation = ::Geom::Transformation.new
          @entities = Entities.new
          @attributes = {}
        end

        def set_attribute(dict, key, value)
          (@attributes[dict] ||= {})[key] = value
        end

        def get_attribute(dict, key, default = nil)
          @attributes.fetch(dict, {}).fetch(key, default)
        end
      end

      class Face
        attr_reader :points, :normal, :distance

        def initialize(points)
          @points = points.map { |p| ::Geom::Point3d.new(p) }
          @normal = (@points[1] - @points[0]).cross(@points[2] - @points[0]).normalize
          @distance = 0
        end

        def reverse!
          @points.reverse!
          @normal.reverse!
          self
        end

        def pushpull(distance, _copy = false)
          @distance = distance
        end

        def segments
          lower = @points
          upper = lower.map { |p| p.offset(@normal, @distance) }
          result = []
          lower.each_index do |i|
            j = (i + 1) % lower.size
            result << [lower[i], lower[j]]
            unless @distance == 0
              result << [upper[i], upper[j]]
              result << [lower[i], upper[i]]
            end
          end
          result
        end
      end

      class Entities
        attr_reader :items

        def initialize
          @items = []
        end

        def add_group
          group = Group.new
          @items << group
          group
        end

        def add_face(*points)
          points = points.first if points.size == 1
          face = Face.new(points)
          @items << face
          face
        end

        # Builder.rod passes the returned circle to add_face.
        def add_circle(center, normal, radius, count = 24)
          reference = normal.z.abs < 0.9 ? ::Geom::Vector3d.new(0, 0, 1) : ::Geom::Vector3d.new(0, 1, 0)
          u = normal.cross(reference).normalize
          v = normal.cross(u).normalize
          count.times.map do |i|
            angle = i * 2.0 * Math::PI / count
            center.offset(u, radius * Math.cos(angle)).offset(v, radius * Math.sin(angle))
          end
        end

        def collect(transform = ::Geom::Transformation.new, module_index = nil, front = false, result = [])
          @items.each do |item|
            if item.is_a?(Group)
              role = Kabinet::Persistence::Attributes.role(item).to_s
              index = item.get_attribute(Kabinet::Constants::ATTR_DICT, 'module_index', module_index)
              is_front = front || role.start_with?('door_', 'drawer_front_', 'cell_dfr_', 'handle_')
              item.entities.collect(transform * item.transformation, index, is_front, result)
            else
              points = item.segments.flatten.map { |p| p.transform(transform) }
              result << { points: points, module_index: module_index, front: front }
            end
          end
          result
        end
      end
    end
  end
end

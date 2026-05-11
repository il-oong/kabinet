module Kabinet
  module Persistence
    module Attributes
      DICT = Kabinet::Constants::ATTR_DICT
      ASSEMBLY_DICT = Kabinet::Constants::ATTR_DICT_ASSEMBLY

      def self.set(entity, key, value)
        entity.set_attribute(DICT, key.to_s, value)
      end

      def self.get(entity, key)
        entity.get_attribute(DICT, key.to_s)
      end

      def self.set_role(entity, role, extra = {})
        set(entity, 'role', role.to_s)
        extra.each { |k, v| set(entity, k, v) }
      end

      def self.role(entity)
        get(entity, 'role')
      end

      def self.write_assembly_spec(entity, spec_hash)
        entity.set_attribute(ASSEMBLY_DICT, 'version', spec_hash[:version] || spec_hash['version'] || 1)
        entity.set_attribute(ASSEMBLY_DICT, 'spec_json', JSON.generate(spec_hash))
      end

      def self.read_assembly_spec(entity)
        return nil unless entity.respond_to?(:attribute_dictionaries)
        json = entity.get_attribute(ASSEMBLY_DICT, 'spec_json')
        return nil unless json
        JSON.parse(json)
      end

      def self.assembly?(entity)
        return false unless entity.respond_to?(:attribute_dictionaries)
        !entity.get_attribute(ASSEMBLY_DICT, 'spec_json').nil?
      end

      def self.find_assembly_in_selection(model = Sketchup.active_model)
        sel = model.selection.to_a
        sel.find { |e| (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && assembly?(e) }
      end

      def self.find_all_assemblies(model = Sketchup.active_model)
        model.entities.grep(Sketchup::Group).select { |g| assembly?(g) }
      end
    end
  end
end

require 'fileutils'
require 'json'
require 'securerandom'
require 'time'
require 'base64'

module Kabinet
  # User-owned files live outside the extension so RBZ updates cannot erase them.
  module FurnitureLibrary
    module_function

    def root
      File.join(ENV['LOCALAPPDATA'] || File.join(Dir.home, 'Library', 'Application Support'), 'Kabinet', 'FurnitureLibrary')
    end

    def entry_dir(id, directory = root)
      raise ArgumentError, '저장 가구를 찾을 수 없습니다.' unless /\A[0-9a-f]{32}\z/.match?(id.to_s)
      File.join(directory, id)
    end

    def clean_name(value)
      name = value.to_s.strip
      raise ArgumentError, '가구 이름은 1~60자로 입력하세요.' if name.empty? || name.length > 60
      name
    end

    def clean_folder(value)
      folder = value.to_s.strip
      folder = '미분류' if folder.empty?
      raise ArgumentError, '폴더 이름은 40자 이내로 입력하세요.' if folder.length > 40 || folder.match?(/[\\\/\x00-\x1f]/)
      folder
    end

    def list(directory: root)
      return [] unless Dir.exist?(directory)
      Dir.children(directory).filter_map do |id|
        next unless /\A[0-9a-f]{32}\z/.match?(id)
        folder = entry_dir(id, directory)
        next unless File.file?(File.join(folder, 'furniture.skp'))
        begin
          data = JSON.parse(File.read(File.join(folder, 'info.json'), encoding: 'UTF-8'))
          next unless data['name'].is_a?(String) && data['saved_at'].is_a?(String)
          thumb = File.join(folder, 'thumb.png')
          { id: id, name: data['name'], folder: clean_folder(data['folder']), saved_at: data['saved_at'],
            dimensions_mm: data['dimensions_mm'],
            thumb: File.file?(thumb) ? "data:image/png;base64,#{Base64.strict_encode64(File.binread(thumb))}" : nil }
        rescue JSON::ParserError, SystemCallError, ArgumentError
          # A damaged entry must not prevent the remaining library from opening.
          next
        end
      end.sort_by { |entry| entry[:saved_at] }.reverse
    end

    def save(name, folder: '미분류', model: Sketchup.active_model, directory: root)
      name = clean_name(name)
      folder = clean_folder(folder)
      raise '그룹 편집을 닫고 저장할 가구를 선택하세요.' if model.active_path
      targets = model.selection.to_a
      unless !targets.empty? && targets.all? { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        raise '저장할 판재 또는 가구 그룹/컴포넌트만 선택하세요.'
      end
      bounds = Geom::BoundingBox.new
      targets.each { |e| bounds.add(e.bounds) }
      raise '비어 있는 가구는 저장할 수 없습니다.' unless bounds.valid? && bounds.diagonal > 0
      id = SecureRandom.hex(16)
      FileUtils.mkdir_p(directory)
      staging = File.join(directory, ".saving-#{id}")
      FileUtils.mkdir_p(staging)
      begin
        saved_front = Output::FurnitureSheet.front_axis(targets)
        model.start_operation('가구 보관함 저장용 복사', true)
        begin
          container = model.entities.add_group
          container.name = name
          # Library geometry is normalized by translation only, so its local
          # front vector can follow a placed instance when the user rotates it.
          Output::FurnitureSheet.save_front(container, saved_front)
          container.definition.set_attribute('kabinet_ep', 'front_local', container.get_attribute('kabinet_ep', 'front_local'))
          move = Geom::Transformation.translation(ORIGIN - bounds.min)
          targets.each do |entity|
            copy = container.entities.add_instance(entity.definition, move * entity.transformation)
            copy.name = entity.name
            copy.material = entity.material if entity.material
            copy.hidden = entity.hidden?
          end
          path = File.join(staging, 'furniture.skp')
          raise '가구 파일을 저장하지 못했습니다.' unless container.definition.save_as(path)
          begin
            container.definition.save_thumbnail(File.join(staging, 'thumb.png'))   # 보관함 목록 미리보기
          rescue StandardError
            nil
          end
        ensure
          model.abort_operation
          model.selection.clear
          targets.each { |e| model.selection.add(e) if e.valid? }
        end
        data = { name: name, folder: folder, saved_at: Time.now.iso8601,
                 dimensions_mm: [bounds.width, bounds.height, bounds.depth].map { |v| v.to_mm.round(2) } }
        File.write(File.join(staging, 'info.json'), JSON.pretty_generate(data), encoding: 'UTF-8')
        File.rename(staging, entry_dir(id, directory))
        id
      ensure
        # Only this operation's generated staging directory may be removed.
        FileUtils.remove_entry(staging) if Dir.exist?(staging)
      end
    end

    def update(id, name:, folder:, directory: root)
      path = File.join(entry_dir(id, directory), 'info.json')
      raise ArgumentError, '저장 가구를 찾을 수 없습니다.' unless File.file?(path) && File.file?(File.join(entry_dir(id, directory), 'furniture.skp'))
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      data['name'] = clean_name(name)
      data['folder'] = clean_folder(folder)
      File.write(path, JSON.pretty_generate(data), encoding: 'UTF-8')
      true
    end

    # 여러 가구를 한 번에 다른 폴더로
    def move(ids, folder, directory: root)
      folder = clean_folder(folder)
      Array(ids).count do |id|
        path = File.join(entry_dir(id, directory), 'info.json')
        next false unless File.file?(path)
        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        data['folder'] = folder
        File.write(path, JSON.pretty_generate(data), encoding: 'UTF-8')
        true
      end
    end

    # 삭제 = 보관함의 .trash 폴더로 옮김 (실수해도 그 폴더에서 되살릴 수 있음)
    def delete(ids, directory: root)
      trash = File.join(directory, '.trash')
      FileUtils.mkdir_p(trash)
      Array(ids).count do |id|
        src = entry_dir(id, directory)
        next false unless Dir.exist?(src)
        dst = File.join(trash, id)
        FileUtils.remove_entry(dst) if Dir.exist?(dst)
        File.rename(src, dst)
        true
      end
    end

    # 썸네일이 없는 저장 가구의 미리보기 이미지를 만든다. 반환: 만든 개수
    def build_missing_thumbnails(model: Sketchup.active_model, directory: root)
      return 0 unless Dir.exist?(directory)
      made = 0
      Dir.children(directory).each do |id|
        next unless /\A[0-9a-f]{32}\z/.match?(id)
        dir = File.join(directory, id)
        skp = File.join(dir, 'furniture.skp')
        next if File.file?(File.join(dir, 'thumb.png')) || !File.file?(skp)
        defn = model.definitions.load(skp)
        next unless defn
        begin
          made += 1 if defn.save_thumbnail(File.join(dir, 'thumb.png'))
        ensure
          # 썸네일용으로 불러온 정의는 모델에 남기지 않는다 (배치된 적 없을 때만 제거)
          model.definitions.remove(defn) if defn.instances.empty? && model.definitions.respond_to?(:remove)
        end
      end
      made
    end

    def definition(id, model: Sketchup.active_model, directory: root)
      path = File.join(entry_dir(id, directory), 'furniture.skp')
      raise '저장한 가구 파일이 없습니다. 보관함 폴더를 확인하세요.' unless File.file?(path)
      model.definitions.load(path)
    end

    def place(id, model: Sketchup.active_model)
      raise '그룹 편집을 닫고 저장 가구를 불러오세요.' if model.active_path
      item = definition(id, model: model)
      raise '가구를 불러오지 못했습니다.' unless item
      # Native placement follows the cursor and supports SketchUp inference/Esc.
      model.place_component(item, false)
    end
  end
end

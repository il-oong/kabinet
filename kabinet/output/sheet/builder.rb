require 'fileutils'
require 'json'
require_relative 'text'
require_relative 'pages'
require_relative 'dxf_writer'
require_relative 'image_info'
module Kabinet
  module Output
    module Sheet
      # 페이지 구성(config) -> Canvas 목록 -> DXF. 순수 Ruby.
      #
      # config = {
      #   'site' =>, 'furniture_name' =>, 'date' =>, 'bg' => 'white|dark|none', 'style_name' =>, 'font_file' =>,
      #   'pages' => [{ 'id', 'type', 'title', 'subject', 'sheet_no', 'scale', 'hidden', 'images' => [{'path','caption'}] }]
      # }
      module Builder
        module_function

        PAGE_TYPES = {
          'photos'    => '현장사진',
          'view3d'    => '상담 3D',
          'floor'     => '평면도',
          'furniture' => '가구 시트 (TOP / 정면)',
          'side'      => '측면 · 단면',
          'detail'    => '상세 (EP · 목찬넬)',
          'table'     => '생산 확인표'
        }.freeze

        def default_config
          {
            'site' => '', 'furniture_name' => '', 'date' => Time.now.strftime('%Y.%m.%d'),
            'bg' => 'white', 'style_name' => 'MALGUN', 'font_file' => 'malgun.ttf',
            'pages' => default_pages
          }
        end

        def default_pages
          [page('photos', '현장사진'), page('view3d', '상담 3D'), page('floor', '평면도'),
           page('furniture', '가구 시트'), page('side', '측면 · 단면'), page('detail', '상세'), page('table', '생산 확인표')]
        end

        @seq = 0
        def page(type, title, extra = {})
          @seq += 1
          { 'id' => "p#{Time.now.to_i}#{@seq}", 'type' => type, 'title' => title, 'subject' => title, 'sheet_no' => '',
            'scale' => '', 'hidden' => false, 'images' => [] }.merge(extra)
        end

        def normalize_config(cfg)
          c = default_config.merge(stringify(cfg || {}))
          c['pages'] = (c['pages'] || []).map do |p|
            type = PAGE_TYPES.key?(p['type']) ? p['type'] : 'furniture'
            page(type, p['title'] || PAGE_TYPES[type]).merge(p).merge('type' => type, 'images' => (p['images'] || []).map { |i| stringify(i) })
          end
          c['pages'] = default_pages if c['pages'].empty?
          c
        end

        def stringify(o)
          case o
          when Hash then o.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
          when Array then o.map { |v| stringify(v) }
          when String then Text.utf8(o)
          else o
          end
        end

        # 시트 번호 자동 부여(가구 시트류는 NO.001…, 입력값이 있으면 우선)
        def info_for(cfg, model, pg, auto_no)
          scale = pg['scale'].to_s =~ /\A\d+\z/ ? pg['scale'].to_i : nil
          {
            site: cfg['site'].to_s, title: (cfg['furniture_name'].to_s.empty? ? model['furniture_name'] : cfg['furniture_name']).to_s,
            subject: pg['subject'].to_s.empty? ? pg['title'].to_s : pg['subject'].to_s,
            sheet_no: pg['sheet_no'].to_s.empty? ? auto_no : pg['sheet_no'].to_s,
            date: cfg['date'].to_s, scale: scale
          }
        end

        # => [Canvas]
        def build(cfg, model, only_ids: nil, image_sizes: nil)
          cfg = normalize_config(cfg)
          model = Model.normalize(model)
          model['site'] = cfg['site']
          out = []
          n = 0
          cfg['pages'].each do |pg|
            next if pg['hidden']
            next if only_ids && !only_ids.include?(pg['id'])
            auto = %w[furniture side detail].include?(pg['type']) ? format('NO.%03d', n += 1) : ''
            info = info_for(cfg, model, pg, auto)
            case pg['type']
            when 'photos', 'view3d'
              header = pg['type'] == 'photos' ? 'SITE PHOTO' : '3D VIEW'
              imgs = (pg['images'] || []).select { |i| i['path'].to_s != '' }
              imgs = imgs.map do |i|
                sz = image_sizes && image_sizes[i['path']]
                sz ||= ImageInfo.size(i['path'])
                i.merge('pw' => sz && sz[0], 'ph' => sz && sz[1])
              end
              per = pg['type'] == 'photos' ? 6 : 4
              chunks = imgs.each_slice(per).to_a
              chunks = [[]] if chunks.empty?
              chunks.each_with_index do |chunk, idx|
                inf = info.dup
                inf[:subject] = "#{info[:subject]}#{chunks.size > 1 ? " (#{idx + 1}/#{chunks.size})" : ''}"
                out << Pages.image_page(inf, header, chunk, name: pg['type'])
              end
            when 'floor'     then out << Pages.floor(model, info)
            when 'furniture' then out << Pages.furniture(model, info)
            when 'side'      then out << Pages.side(model, info)
            when 'detail'    then out << Pages.detail(model, info)
            when 'table'     then out << Pages.table(model, info, pg['rows'])
            end
          end
          out
        end

        # DXF 저장. 이미지는 <이름>_images/ 로 복사하고 상대경로로 참조한다.
        # path 는 SketchUp(UI.savepanel)이 준 원본 경로 — 인코딩이 CP949 든 UTF-8 이든 그대로 파일 I/O 에 쓰고,
        # DXF·메시지용 문자열은 UTF-8 로 따로 만든다.
        # => { path:, pages:, images_dir:, copied: [...] }  (문자열은 모두 UTF-8)
        def export(cfg, model, path, only_ids: nil, max_image_px: nil)
          cfg = normalize_config(cfg)
          canvases = build(cfg, model, only_ids: only_ids)
          native_path = path
          base = File.basename(Text.utf8(native_path), '.*')               # UTF-8 (한글 가능)
          dir_native = File.dirname(native_path)
          images_name = "#{base}_images"                                     # UTF-8
          images_dir_native = File.join(dir_native, Text.native(images_name, dir_native))
          paths = {}
          sizes = {}
          copied = []
          canvases.each do |c|
            c.items.each do |it|
              next unless it[0] == :I
              src = it[5]
              next if src.to_s.empty? || paths.key?(src)
              real = Text.resolve_path(src)
              sz = ImageInfo.size(real) if File.file?(real)
              sizes[src] = sz || [1000, 1000]
              next unless File.file?(real)
              FileUtils.mkdir_p(images_dir_native)
              dst_name = unique_name(images_dir_native, Text.utf8(File.basename(real)))
              FileUtils.cp(real, File.join(images_dir_native, Text.native(dst_name, images_dir_native)))
              paths[src] = "#{images_name}/#{dst_name}"
              copied << "#{Text.utf8(images_dir_native)}/#{dst_name}"
            end
          end
          w = DxfWriter.new(canvases, bg: cfg['bg'], style_name: cfg['style_name'], font_file: cfg['font_file'],
                            image_paths: paths, image_sizes: sizes)
          FileUtils.mkdir_p(dir_native)
          w.write(native_path)
          { path: Text.utf8(native_path), pages: canvases.size, images_dir: (copied.empty? ? nil : Text.utf8(images_dir_native)), copied: copied }
        end

        # dir_native: 실제 파일 I/O 용 경로(원본 인코딩), name: UTF-8 파일명 → 겹치지 않는 UTF-8 파일명
        def unique_name(dir_native, name)
          exists = ->(n) { File.exist?(File.join(dir_native, Text.native(n, dir_native))) }
          return name unless exists.call(name)
          ext = File.extname(name); stem = File.basename(name, ext)
          i = 2
          i += 1 while exists.call("#{stem}_#{i}#{ext}")
          "#{stem}_#{i}#{ext}"
        end
      end
    end
  end
end

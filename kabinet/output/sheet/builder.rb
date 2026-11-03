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
      #   'images' => true(현장사진·3D 를 DXF IMAGE 로 포함; false 면 사진 없이 틀·캡션만), 'real_scale' => true(1:1 실치수),
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
            'bg' => 'white', 'style_name' => 'MALGUN', 'font_file' => 'malgun.ttf', 'images' => true, 'real_scale' => true,
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
          c['images'] = c['images'] != false
          c['real_scale'] = c['real_scale'] != false
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
          # 축척이 없는 쪽(사진·상세·확인표)은 가구 시트 축척과 같은 크기의 도곽으로 낸다(실치수 1:1 배치용)
          den = out.map { |c| c.meta[:den] }.compact.first || Model.pick_scale(model)
          out.each { |c| c.meta[:den] ||= den }
          out
        end

        # DXF 저장. 이미지는 <ASCII 이름>_images/img_01.jpg … 로 복사하고 상대경로로 참조한다
        # (한글·공백·괄호가 든 경로는 일부 CAD 가 열지 못하므로 사용자 파일명은 캡션 TEXT 로만 남긴다).
        # images: false 면 사진을 넣지 않고(틀·캡션만), 복사에 실패해도 그 사진만 건너뛴다.
        # path 는 SketchUp(UI.savepanel)이 준 원본 경로 — 인코딩이 CP949 든 UTF-8 이든 그대로 파일 I/O 에 쓰고,
        # DXF·메시지용 문자열은 UTF-8 로 따로 만든다.
        # => { path:, pages:, images_dir:, copied: [...], real_scale:, images: }  (문자열은 모두 UTF-8)
        def export(cfg, model, path, only_ids: nil, max_image_px: nil)
          cfg = normalize_config(cfg)
          canvases = build(cfg, model, only_ids: only_ids)
          native_path = path
          base = File.basename(Text.utf8(native_path), '.*')               # UTF-8 (한글 가능)
          dir_native = File.dirname(native_path)
          images_name = "#{ascii_stem(base)}_images"                         # ASCII
          images_dir_native = File.join(dir_native, images_name)
          paths = {}
          sizes = {}
          copied = []
          seq = 0
          if cfg['images']
            canvases.each do |c|
              c.items.each do |it|
                next unless it[0] == :I
                src = it[5]
                next if src.to_s.empty? || paths.key?(src)
                real = Text.resolve_path(src)
                next unless File.file?(real)
                begin
                  sz = ImageInfo.size(real)
                  FileUtils.mkdir_p(images_dir_native)
                  ext = File.extname(Text.utf8(real)).downcase
                  ext = '.jpg' unless ext =~ /\A\.[a-z0-9]{1,4}\z/
                  seq += 1
                  dst_name = format('img_%02d%s', seq, ext)
                  dst_name = format('img_%02d%s', seq += 1, ext) while File.exist?(File.join(images_dir_native, dst_name))
                  FileUtils.cp(real, File.join(images_dir_native, dst_name))
                  sizes[src] = sz || [1000, 1000]
                  paths[src] = "#{images_name}/#{dst_name}"
                  copied << "#{Text.utf8(images_dir_native)}/#{dst_name}"
                rescue StandardError
                  next                                                       # 이 사진만 건너뜀(IMAGE_FRAME 사각형은 남는다)
                end
              end
            end
            # 복사된 사진만 IMAGE 로 쓴다(없는 파일을 가리키는 IMAGE 방지)
            canvases.each { |c| c.items.reject! { |it| it[0] == :I && !paths.key?(it[5]) } }
          end
          w = DxfWriter.new(canvases, bg: cfg['bg'], style_name: cfg['style_name'], font_file: cfg['font_file'],
                            image_paths: paths, image_sizes: sizes, images: cfg['images'], real_scale: cfg['real_scale'])
          FileUtils.mkdir_p(dir_native)
          w.write(native_path)
          { path: Text.utf8(native_path), pages: canvases.size, images_dir: (copied.empty? ? nil : Text.utf8(images_dir_native)), copied: copied,
            real_scale: cfg['real_scale'], images: cfg['images'] }
        end

        # 한글·공백·특수문자를 뺀 ASCII 이름(비면 'sheet')
        def ascii_stem(base)
          st = Text.utf8(base).gsub(/[^A-Za-z0-9_\-]/, '')
          st.empty? ? 'sheet' : st
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

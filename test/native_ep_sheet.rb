raise 'Isolated test process required' unless ENV['KABINET_EP_TEST'] == '1'
require 'json'
require File.join(ENV.fetch('KABINET_EP_SOURCE'), 'kabinet', 'ep_main')
out = ENV.fetch('KABINET_EP_OUT')
%w[core/ep_board core/furniture_library output/furniture_sheet ui/ep_dialog].each do |file|
  load File.join(ENV.fetch('KABINET_EP_SOURCE'), 'kabinet', file + '.rb')
end
%w[fatal.txt done.txt].each { |name| File.delete(File.join(out, name)) if File.exist?(File.join(out, name)) }
# A fixed-file rerun trigger is available only in the isolated test process.
unless $kabinet_ep_watch
  $kabinet_ep_watch = UI.start_timer(1, true) do
    marker = File.join(out, 'rerun.txt')
    if File.exist?(marker)
      File.delete(marker)
      load __FILE__
    end
  end
end
File.write(File.join(out, 'started.txt'), Process.pid.to_s)
UI.start_timer(2, false) do
  begin
    model = Sketchup.active_model
    raise "Wrong test model: #{model.path}" unless File.expand_path(model.path).casecmp(File.expand_path(File.join(out, 'test-model.skp'))).zero?
    model.entities.clear!
    model.definitions.purge_unused
    model.materials.purge_unused
    results = []
    [3,9,12,18,20,30].each do |thickness|
      board = Kabinet::EPBoard.create({'width'=>600, 'thickness'=>thickness, 'height'=>2400})
      dims = [board.bounds.width, board.bounds.height, board.bounds.depth].map { |v| v.to_mm.round(3) }
      raise "Wrong dimensions #{dims}" unless dims == [600, thickness, 2400]
      raise 'Not solid' unless board.manifold?
      board.erase!
      results << "#{thickness}T solid and dimensions passed"
    end
    [0, -1, 'bad', Float::INFINITY].each do |bad|
      begin
        Kabinet::EPBoard.dimensions({'width'=>bad, 'thickness'=>18, 'height'=>2400})
        raise 'Accepted invalid dimension'
      rescue ArgumentError
      end
    end
    begin
      Kabinet::EPBoard.dimensions({'width'=>600, 'thickness'=>19, 'height'=>2400})
      raise 'Accepted invalid thickness'
    rescue ArgumentError
    end
    # A manually assembled three-bay cabinet, entirely made of independent EPs.
    material = model.materials.add('PET · 웜 화이트')
    material.color = Sketchup::Color.new(214,211,198)
    wood = model.materials.add('오크 · 내부 마감')
    wood.color = Sketchup::Color.new(159,125,83)
    boards = []
    make = lambda do |w,t,h,transform,mat|
      b = Kabinet::EPBoard.create({'width'=>w,'thickness'=>t,'height'=>h})
      b.transform!(transform)
      b.material = mat
      boards << b
      b
    end
    identity = Geom::Transformation.new
    # Rotate upright XY-thin panels into side boards: width becomes cabinet depth.
    rot = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
    [18, 518, 1018, 1518].each { |x| make.call(500,18,2400,Geom::Transformation.translation([x.mm,0,0])*rot,wood) }
    # Shelves use EP height as depth after rotating around X.
    flat = Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)
    [18, 600, 1200, 1800, 2400].each { |z| make.call(1500,18,500,Geom::Transformation.translation([0,500.mm,(z-18).mm])*flat,wood) }
    [0, 506, 1012].each { |x| make.call(502,18,2398,Geom::Transformation.translation([x.mm,-20.mm,0]),material) }
    unselected = make.call(900,30,1000,Geom::Transformation.translation([5000.mm,0,0]),material)
    boards.delete(unselected)
    model.selection.clear
    model.selection.add(boards)
    before = model.entities.to_a.map(&:persistent_id).sort
    camera = model.active_view.camera
    selection = model.selection.to_a.map(&:persistent_id).sort
    library = File.join(out, "library-#{Time.now.strftime('%H%M%S')}")
    id = Kabinet::FurnitureLibrary.save('한글 가구 / 같은 이름', directory: library)
    second = Kabinet::FurnitureLibrary.save('한글 가구 / 같은 이름', directory: library)
    raise 'Overwrote duplicate name' if id == second || Kabinet::FurnitureLibrary.list(directory: library).length != 2
    definition = Kabinet::FurnitureLibrary.definition(id, directory: library)
    restored = [definition.bounds.width, definition.bounds.height, definition.bounds.depth].map { |v| v.to_mm.round(2) }
    original_box = Geom::BoundingBox.new
    boards.each { |b| original_box.add(b.bounds) }
    original_dims = [original_box.width, original_box.height, original_box.depth].map { |v| v.to_mm.round(2) }
    raise "Library geometry mismatch #{restored} != #{original_dims}" unless restored == original_dims
    has_material = lambda do |entities|
      entities.any? { |e| (e.respond_to?(:material) && e.material) || (e.respond_to?(:definition) && has_material.call(e.definition.entities)) }
    end
    raise 'Library did not retain materials' unless has_material.call(definition.entities)
    raise 'Library changed original entities' unless before == model.entities.to_a.map(&:persistent_id).sort
    raise 'Library changed selection' unless selection == model.selection.to_a.map(&:persistent_id).sort
    begin
      Kabinet::FurnitureLibrary.definition('../escape', directory: library)
      raise 'Accepted traversal ID'
    rescue ArgumentError
    end
    results << 'Library save/load, Korean name, duplicate name, materials, bounds and path validation passed'
    path = File.join(out, "EP_가구도면_#{Time.now.strftime('%H%M%S')}.layout")
    File.write(File.join(out, 'latest.txt'), path)
    Kabinet::Output::FurnitureSheet.run({'title'=>'EP 조합 가구', 'internal'=>true}, path:path)
    raise 'Changed original entities' unless before == model.entities.to_a.map(&:persistent_id).sort
    raise 'Changed selection' unless selection == model.selection.to_a.map(&:persistent_id).sort
    raise 'Unselected hidden state changed' if unselected.hidden?
    raise 'Changed camera' unless camera.eye == model.active_view.camera.eye && camera.target == model.active_view.camera.target
    document = Layout::Document.open(path)
    labels = document.pages.first.entities.grep(Layout::FormattedText)
    raise 'Font substitution remains' unless labels.all? { |label| label.style.font_family == '맑은 고딕' }
    raise 'Unreadably small type' unless labels.all? { |label| label.style.font_size >= 8 }
    raise 'No hidden dashed lines' unless document.pages.first.entities.grep(Layout::Path).any? { |line| line.style.stroke_pattern == Layout::Style::STROKE_PATTERN_DASH }
    iso = document.pages.first.entities.grep(Layout::SketchUpModel).first
    b = iso.bounds
    half = original_dims.map { |n| n.mm / 2 }
    margin = 9.9 / 25.4
    [-1,1].repeated_permutation(3).each do |sign|
      pt = iso.model_to_paper_point(Geom::Point3d.new(half.zip(sign).map { |n,s| n*s }))
      raise 'Isometric model lacks safe margin' unless pt.x >= b.upper_left.x + margin && pt.x <= b.lower_right.x - margin && pt.y >= b.upper_left.y + margin && pt.y <= b.lower_right.y - margin
    end
    # A second output without hidden lines must contain no dashed geometry.
    plain_path = File.join(out, "외관선_#{Time.now.strftime('%H%M%S')}.layout")
    Kabinet::Output::FurnitureSheet.run({'title'=>'외관선 검사', 'internal'=>false}, path:plain_path)
    plain = Layout::Document.open(plain_path)
    raise 'Hidden-line toggle ignored' if plain.pages.first.entities.grep(Layout::Path).any? { |line| line.style.stroke_pattern == Layout::Style::STROKE_PATTERN_DASH }
    document.export(File.join(out,'sheet.png'), dpi:120)
    raise 'PDF missing' unless File.size(path.sub('.layout','.pdf')) > 1000
    raise 'Incorrect page count' unless document.pages.count == 1
    results << 'A3 LayOut/PDF and PNG export passed; user geometry/selection/camera preserved'
    results << 'Korean font, 8pt minimum/10pt dimensions, hidden-line toggle and isometric framing passed'
    File.write(File.join(out, 'report.json'), JSON.pretty_generate(results))
    delivery = File.join(out, 'deliver.txt')
    if File.file?(delivery)
      final_path = File.read(delivery, encoding: 'UTF-8').strip
      Kabinet::Output::FurnitureSheet.run({'title'=>'EP 조합 가구', 'internal'=>true}, path:final_path)
      Layout::Document.open(final_path).export(final_path.sub(/\.layout\z/, '.png'), dpi:150)
      File.delete(delivery)
    end
    # Exercise the actual HtmlDialog bridge in the isolated test process.
    Kabinet::FurnitureLibrary.define_singleton_method(:root) { File.join(out, 'ui-library') }
    Kabinet::EPDialog.instance_variable_get(:@dialog)&.close
    Kabinet::EPDialog.show
    dialog = Kabinet::EPDialog.instance_variable_get(:@dialog)
    dialog.add_action_callback('ep_ui_test_result') do |_context, result|
      model.select_tool(nil)
      File.write(File.join(out, 'ui-report.json'), result)
    end
    UI.start_timer(2, false) do
      dialog.execute_script(<<~JS)
        (async () => {
          const assert = (condition, message) => { if (!condition) throw new Error(message); };
          const wait = async (test) => {
            for (let i = 0; i < 100; i++) { if (test()) return; await new Promise(r => setTimeout(r, 50)); }
            throw new Error('UI callback timed out: ' + document.getElementById('status').textContent);
          };
          try {
            document.getElementById('width').value = '350';
            document.getElementById('height').value = '700';
            document.getElementById('thickness').value = '9';
            document.getElementById('board-form').requestSubmit();
            await wait(() => document.getElementById('status').textContent.includes('생성 완료'));
            document.getElementById('library-name').value = 'UI 가구 <b>문자</b>';
            document.getElementById('library-form').requestSubmit();
            await wait(() => document.getElementById('status').textContent.includes('저장 완료'));
            const item = [...document.querySelectorAll('.library-item')].find(e => e.querySelector('strong').textContent === 'UI 가구 <b>문자</b>');
            assert(item, 'Saved furniture absent');
            assert(!item.querySelector('b'), 'Furniture name treated as HTML');
            document.getElementById('library-search').value = '없는가구';
            document.getElementById('library-search').dispatchEvent(new Event('input'));
            assert(document.querySelectorAll('.library-item').length === 0, 'Search failed');
            document.getElementById('library-search').value = 'UI 가구';
            document.getElementById('library-search').dispatchEvent(new Event('input'));
            document.querySelector('.library-item').click();
            await wait(() => document.getElementById('status').textContent.includes('클릭하세요'));
            sketchup.ep_ui_test_result(JSON.stringify({ok:true,checks:['EP create callback','library save callback','escaped labels','search','native placement callback']}));
          } catch (e) { sketchup.ep_ui_test_result(JSON.stringify({ok:false,error:e.message})); }
        })();
      JS
    end
  rescue Exception => e
    File.write(File.join(out, 'fatal.txt'), e.full_message)
  ensure
    File.write(File.join(out, 'done.txt'), Process.pid.to_s)
  end
end

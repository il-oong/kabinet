raise 'Isolated process required' unless ENV['KABINET_SPACE_TEST']=='1'
require 'json'
require File.join(ENV.fetch('KABINET_EP_SOURCE'),'kabinet/ep_main')
out=ENV.fetch('KABINET_EP_OUT')
unless $space_watch
  $space_watch=UI.start_timer(1,true) do
    marker=File.join(out,'rerun.txt')
    if File.exist?(marker)
      File.delete(marker)
      load __FILE__
    end
  end
end
File.delete(File.join(out,'error.txt')) if File.exist?(File.join(out,'error.txt'))
load File.join(ENV.fetch('KABINET_EP_SOURCE'),'kabinet/output/space_sheet.rb')
UI.start_timer(2,false) do
  begin
    m=Sketchup.active_model
    raise 'Wrong model' unless File.expand_path(m.path)==File.expand_path(File.join(out,'test-model.skp'))
    m.entities.clear!
    m.definitions.purge_unused
    floor=m.entities.add_group
    floor.entities.add_face([[0,0,0],[4000.mm,0,0],[4000.mm,3000.mm,0],[0,3000.mm,0]])
    floor.set_attribute('kabinet_space','role','floor')
    make=lambda do |name,role,x,y,z,w,d,h|
      g=m.entities.add_group; g.name=name
      f=g.entities.add_face([[0,0,0],[w.mm,0,0],[w.mm,d.mm,0],[0,d.mm,0]])
      f.reverse! if f.normal.z<0;f.pushpull(h.mm)
      g.transform!(Geom::Transformation.translation([x.mm,y.mm,z.mm]))
      g.set_attribute('kabinet_space','role',role)
      g
    end
    door=make.call('출입문','door',500,-50,0,900,100,2100)
    window=make.call('창문','window',3950,1000,900,100,1200,1100)
    furniture=make.call('수납장','furniture',50,1800,0,1800,600,2200)
    furniture2=make.call('책상','furniture',2400,2100,0,1200,600,720)
    # Extra faces inside the cabinet must not appear as internal seams.
    furniture.entities.add_face([[900.mm,0,0],[900.mm,600.mm,0],[900.mm,600.mm,2200.mm],[900.mm,0,2200.mm]])
    m.selection.add([floor,door,window,furniture,furniture2])
    source=m.entities.to_a.map(&:persistent_id)
    options={'space_name'=>'서재 공간 예시','site'=>'예시 현장','ceiling_height'=>'2400','survey_date'=>'2026-10-07','drawing_date'=>'2026-10-07','memo'=>"천장 몰딩 높이 50 / 깊이 12\n걸레받이 높이 50 / 깊이 12",'wall_views'=>true}
    api=Kabinet::Output::SpaceSheet
    data=api.capture(m,options)
    raise 'Incorrect room size' unless data[:width]==4000 && data[:depth]==3000
    item=data[:items].find { |r| r[:name]=='수납장' }
    raise 'Internal furniture seam retained' unless item[:plan].length==1 && item[:plan].first.length==4 && (api.area(item[:plan].first)-1800*600).abs<0.1
    # Union keeps an L shape concavity rather than replacing it with a box.
    l=api.outlines([[[[0,0,0],[100,0,0],[100,40,0],[0,40,0]]],[[[0,40,0],[40,40,0],[40,100,0],[0,100,0]]]],->(p){p[0,2]})
    raise 'L shaped furniture silhouette lost' unless (l.sum { |loop| api.area(loop) }-6400).abs<0.1
    raise 'Furniture gap wrong' unless (api.plan_gap([[0,0],[100,0],[100,100],[0,100]],[[150,0],[200,0],[200,100],[150,100]])-50).abs<0.1
    path=File.join(out,'space.layout')
    api.run(options,path:path)
    doc=Layout::Document.open(path)
    raise 'Wrong page count' unless doc.pages.length==6
    raise 'Original model changed' unless source==m.entities.to_a.map(&:persistent_id)
    raise 'PDF missing' unless File.size(File.join(out,'space.pdf'))>1000
    # Missing floor must fail without silently dimensioning furniture bounds.
    m.selection.remove(floor)
    begin
      api.capture(m,options)
      raise 'Accepted missing floor'
    rescue RuntimeError=>e
      raise unless e.message.include?('바닥 경계')
    end
    m.selection.add(floor)
    File.write(File.join(out,'report.json'),JSON.pretty_generate({ok:true,pages:doc.pages.length,checks:['room dimensions','furniture seams removed','L-shaped outline','furniture clearance','missing floor rejection','original preserved']}))
    Kabinet::EPDialog.instance_variable_get(:@dialog)&.close
    Kabinet::EPDialog.show
    dialog=Kabinet::EPDialog.instance_variable_get(:@dialog)
    dialog.add_action_callback('space_ui_test') { |_ctx,result| File.write(File.join(out,'ui.json'),result) }
    UI.start_timer(2,false) do
      dialog.execute_script(<<~JS)
        (() => {
          const mode=document.getElementById('space-mode');
          mode.checked=true; mode.dispatchEvent(new Event('change'));
          const visible=!document.getElementById('space-options').hidden && document.getElementById('furniture-options').hidden;
          mode.checked=false; mode.dispatchEvent(new Event('change'));
          const restored=document.getElementById('space-options').hidden && !document.getElementById('furniture-options').hidden;
          sketchup.space_ui_test(JSON.stringify({ok:visible&&restored,spaceMode:visible,furnitureMode:restored}));
        })();
      JS
    end
    marker=File.join(out,'deliver.txt')
    if File.exist?(marker)
      api.run(options,path:File.read(marker,encoding:'UTF-8').strip)
      File.delete(marker)
    end
    ep_marker=File.join(out,'furniture-check.txt')
    if File.exist?(ep_marker)
      File.delete(ep_marker)
      ENV['KABINET_EP_TEST']='1'
      load File.join(ENV.fetch('KABINET_EP_SOURCE'),'test/native_ep_sheet.rb')
    end
  rescue Exception=>e
    File.write(File.join(out,'error.txt'),e.full_message)
  end
end

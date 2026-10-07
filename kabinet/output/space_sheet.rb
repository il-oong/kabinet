require 'date'

module Kabinet
  module Output
    # Separate exporter: no furniture drawing behavior is changed.
    module SpaceSheet
      module_function

      ROLES = %w[floor door window furniture wall clear].freeze

      def mark(role, model: Sketchup.active_model)
        raise '올바른 공간 구분을 선택하세요.' unless ROLES.include?(role)
        items = model.selection.to_a
        raise '그룹 또는 컴포넌트를 선택하세요.' if items.empty? || items.any? { |e| !e.respond_to?(:definition) }
        model.start_operation('공간 도면 구분', true)
        begin
          items.each { |e| role == 'clear' ? e.delete_attribute('kabinet_space', 'role') : e.set_attribute('kabinet_space', 'role', role) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        items.length
      end

      def faces(entity, parent = Geom::Transformation.new, result = [])
        return result if entity.hidden? || (entity.respond_to?(:layer) && !entity.layer.visible?)
        if entity.respond_to?(:definition)
          t = parent * entity.transformation
          entity.definition.entities.each { |child| faces(child, t, result) }
        elsif entity.is_a?(Sketchup::Face)
          loops = [entity.outer_loop] + entity.loops.reject(&:outer?)
          result << loops.map { |loop| loop.vertices.map { |v| v.position.transform(parent).to_a.map(&:to_mm) } }
        end
        result
      end

      def scan(entity, parent, records)
        return unless entity.respond_to?(:definition)
        return if entity.hidden? || !entity.layer.visible?
        role = entity.get_attribute('kabinet_space', 'role')
        if role && role != 'clear'
          polygons = faces(entity, parent)
          raise '공간 부품에 면이 없습니다.' if polygons.empty?
          records << {role: role, name: entity.name.to_s, faces: polygons}
        else
          t = parent * entity.transformation
          entity.definition.entities.each { |child| scan(child, t, records) }
        end
      end

      def cross(a,b); a[0]*b[1]-a[1]*b[0]; end
      def sub(a,b); [a[0]-b[0],a[1]-b[1]]; end
      def lerp(a,b,t); [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t]; end
      def area(poly); poly.each_with_index.sum { |a,i| cross(a,poly[(i+1)%poly.size]) } / 2.0; end
      def inside(point, poly)
        flag = false
        poly.each_with_index do |a,i|
          b=poly[(i+1)%poly.length]
          if (a[1]>point[1]) != (b[1]>point[1])
            flag = !flag if point[0] < (b[0]-a[0])*(point[1]-a[1])/(b[1]-a[1]).to_f+a[0]
          end
        end
        flag
      end

      # Project all solid faces, split intersections and retain only the outer
      # union boundary. Interior panel seams and enclosed holes are omitted.
      def outlines(polygons, projector)
        shapes=polygons.map { |loops| loops.map { |loop| loop.map { |p| projector.call(p) } } }.select { |loops| area(loops.first).abs > 0.01 }
        edges=shapes.flat_map { |loops| loops.flat_map { |loop| loop.each_with_index.map { |a,i| [a,loop[(i+1)%loop.length]] } } }
        raise '가구 형상이 너무 복잡합니다. 도면용 단순 모델을 사용하세요.' if edges.length > 2500
        contains=->(p) { shapes.any? { |loops| inside(p,loops.first) && loops.drop(1).none? { |hole| inside(p,hole) } } }
        segments={}
        edges.each do |a,b|
          v=sub(b,a); length=Math.hypot(*v); next if length < 0.001
          ts=[0.0,1.0]
          edges.each do |c,d|
            w=sub(d,c); delta=sub(c,a); det=cross(v,w)
            if det.abs > 0.000001
              t=cross(delta,w)/det.to_f; u=cross(delta,v)/det.to_f
              ts << t if t>0 && t<1 && u>=-0.000001 && u<=1.000001
            elsif cross(delta,v).abs < 0.001
              [c,d].each { |p| t=((p[0]-a[0])*v[0]+(p[1]-a[1])*v[1])/(length*length); ts << t if t>0 && t<1 }
            end
          end
          ts.sort.uniq.each_cons(2) do |t,u|
            next if (u-t)*length < 0.01
            p=lerp(a,b,t); q=lerp(a,b,u); mid=lerp(p,q,0.5)
            eps=[0.01,(u-t)*length/10].min
            n=[-v[1]/length*eps,v[0]/length*eps]
            left=contains.call([mid[0]+n[0],mid[1]+n[1]])
            right=contains.call([mid[0]-n[0],mid[1]-n[1]])
            next if left==right
            p,q=q,p unless left
            key=[p,q].map { |r| r.map { |z| z.round(3) } }
            segments[key]=key
          end
        end
        pending=segments.values
        loops=[]
        until pending.empty?
          a,b=pending.shift; loop=[a,b]
          while loop.last != loop.first
            idx=pending.index { |p,q| p==loop.last }
            break unless idx
            loop << pending.delete_at(idx)[1]
          end
          if loop.last==loop.first && area(loop)>0.01
            polygon=loop[0...-1]
            loop do
              idx=polygon.each_index.find do |i|
                u=sub(polygon[i],polygon[i-1]); v=sub(polygon[(i+1)%polygon.length],polygon[i])
                cross(u,v).abs < 0.005*(Math.hypot(*u)+Math.hypot(*v))
              end
              break unless idx && polygon.length>3
              polygon.delete_at(idx)
            end
            loops << polygon
          end
        end
        raise '가구 외곽선을 만들지 못했습니다. 그룹 형상을 확인하세요.' if loops.empty?
        loops
      end

      def capture(model, options)
        raise '그룹 편집을 닫고 공간 전체를 선택하세요.' if model.active_path
        selected=model.selection.to_a
        raise '공간 전체 그룹 또는 구성 그룹들을 선택하세요.' if selected.empty? || selected.any? { |e| !e.respond_to?(:definition) }
        records=[]
        selected.each { |e| scan(e,Geom::Transformation.new,records) }
        floors=records.select { |r| r[:role]=='floor' }
        raise '바닥 경계 그룹을 정확히 하나 지정하세요.' unless floors.length==1
        floor_faces=floors.first[:faces]
        raise '바닥 경계는 두께 없는 수평 면 한 장으로 만들어주세요.' unless floor_faces.length==1 && floor_faces.first.length==1
        floor=floor_faces.first.first
        z=floor.map { |p| p[2] }
        raise '바닥 경계는 수평이어야 합니다.' if z.max-z.min > 0.1
        floor=floor.reverse if area(floor)<0
        raise '바닥 경계는 3~12개 모서리로 구성해주세요.' unless (3..12).include?(floor.length)
        height=Float(options.fetch('ceiling_height',2400)) rescue nil
        raise '천장 높이는 100~10000mm로 입력하세요.' unless height && height.finite? && height.between?(100,10000)
        origin=[floor.map { |p| p[0] }.min,floor.map { |p| p[1] }.min,z.first]
        floor=floor.map { |p| p.zip(origin).map { |a,b| a-b } }
        items=records.reject { |r| %w[floor wall].include?(r[:role]) }
        counters=Hash.new(0)
        raise '공간 하나에 부품은 20개 이하로 나눠 출력하세요.' if items.length>20
        items.each do |r|
          counters[r[:role]]+=1
          r[:label]={'door'=>'문','window'=>'창','furniture'=>'가구'}.fetch(r[:role])+counters[r[:role]].to_s
          r[:faces]=r[:faces].map { |loops| loops.map { |loop| loop.map { |p| p.zip(origin).map { |a,b| a-b } } } }
          points=r[:faces].flatten(2)
          r[:lo]=(0..2).map { |i| points.map { |p| p[i] }.min }
          r[:hi]=(0..2).map { |i| points.map { |p| p[i] }.max }
          r[:plan]=outlines(r[:faces],->(p){p[0,2]})
          if r[:role]=='furniture'
            outside=r[:plan].flatten(1).any? do |p|
              !inside(p,floor) && floor.each_with_index.all? { |a,i| point_segment_distance(p,a,floor[(i+1)%floor.length])>0.1 }
            end
            raise "#{r[:label]}가 바닥 경계 밖에 있습니다." if outside
          end
          raise "#{r[:label]} 높이가 바닥 또는 천장 범위를 벗어납니다." if r[:lo][2]<-0.1 || r[:hi][2]>height+0.1
        end
        walls=floor.each_with_index.map do |a,i|
          b=floor[(i+1)%floor.length]; length=Math.hypot(b[0]-a[0],b[1]-a[1])
          raise '너무 짧은 바닥 모서리가 있습니다.' if length<10
          {a:a,b:b,length:length,u:[(b[0]-a[0])/length,(b[1]-a[1])/length],name:"벽 #{i+1}"}
        end
        items.each do |r|
          center=r[:lo].zip(r[:hi]).map { |a,b| (a+b)/2 }
          r[:wall]=walls.each_index.min_by do |i|
            wall=walls[i]
            r[:plan].map { |loop| plan_gap(loop,[wall[:a][0,2],wall[:b][0,2]]) }.min
          end
          if %w[door window].include?(r[:role])
            wall=walls[r[:wall]]; gap=cross(wall[:u],sub(center,wall[:a])).abs
            raise "#{r[:label]} 위치가 벽에서 멉니다. 벽에 맞춰 배치하세요." if gap>300
          end
        end
        {floor:floor,height:height,items:items,walls:walls,width:floor.map { |p| p[0] }.max,depth:floor.map { |p| p[1] }.max}
      end

      class Canvas
        include FurnitureSheet
        public :line, :text, :horizontal_dimension, :vertical_dimension
        def initialize(doc,page); @page=page; end
        def add(doc,entity); doc.add_entity(entity,doc.layers.first,@page); entity; end
        def poly(doc,points,**style)
          points.each_with_index { |a,i| b=points[(i+1)%points.length]; line(doc,*a,*b,**style) }
        end
        def scaled(doc,before,scale)
          paths=@page.entities.grep(Layout::Path).reject { |e| before.any? { |old| old==e } }
          return if paths.empty?
          group=Layout::Group.new(paths)
          group.set_scale_factor(scale,Layout::Document::DECIMAL_MILLIMETERS,Layout::Group::RESIZE_BEHAVIOR_NONE)
          group.scale_precision=1.0
        end
        def frame(doc,title,options,subtitle)
          text(doc,title,18,9,280,10,size:16,bold:true)
          text(doc,subtitle,18,21,380,8,size:9)
          fields=[['공간',options['space_name'].to_s],['현장',options['site'].to_s],['실측일',options['survey_date'].to_s],['제작일',options['drawing_date'].to_s]]
          fields.each_with_index { |(k,v),i| text(doc,"#{k}: #{v}",18+i*96,282,94,8,size:9,bold:true) }
          line(doc,18,279,402,279)
        end
      end

      def run(options={},model:Sketchup.active_model,path:nil)
        data=capture(model,options)
        title=options.fetch('space_name','').to_s.strip
        title='공간 도면' if title.empty?
        memo=options.fetch('memo','').to_s
        raise '메모는 180자, 8줄 이내로 입력하세요.' if memo.length>180 || memo.lines.count>8
        path ||= ::UI.savepanel('공간 도면 저장',nil,title.gsub(/[\\\/:*?"<>|]/,'_')+'.layout')
        return unless path
        path=path.sub(/\.(layout|pdf)\z/i,'')+'.layout'
        doc=Layout::Document.open(File.join(__dir__,'drawing_template.layout'))
        doc.units=Layout::Document::DECIMAL_MILLIMETERS; doc.precision=1.0
        doc.page_info.width=420.0/25.4; doc.page_info.height=297.0/25.4
        doc.pages.first.name='공간 평면도'
        c=Canvas.new(doc,doc.pages.first)
        scale=1.0/[data[:width]/190.0,data[:depth]/180.0,1].max.ceil
        project=->(p){[38+p[0]*scale,242-p[1]*scale]}
        c.frame(doc,title,options,"평면도 1:#{(1/scale).round} · 단위 mm · 모델 입력값 기준 · 가구 내부선 생략")
        before=doc.pages.first.entities.to_a
        c.poly(doc,data[:floor].map { |p| project.call(p) },weight:0.8)
        data[:walls].each_with_index do |wall,i|
          mid=wall[:a].zip(wall[:b]).map { |a,b| (a+b)/2 }
          p=project.call(mid); c.text(doc,wall[:name],p[0]+2,p[1]+2,25,6,size:9,bold:true)
        end
        data[:items].each do |item|
          color={'furniture'=>'#555951','window'=>'#24627c','door'=>'#8c6034'}.fetch(item[:role])
          item[:plan].each { |loop| c.poly(doc,loop.map { |p| project.call(p) },color:color,weight:0.5) }
          p=project.call(item[:lo]); c.text(doc,item[:label],p[0]+2,p[1]-6,28,6,size:9,bold:true,color:color)
        end
        c.scaled(doc,before,scale)
        c.horizontal_dimension(doc,38,38+data[:width]*scale,242,254,data[:width])
        c.vertical_dimension(doc,38,242-data[:depth]*scale,242,25,data[:depth])
        c.text(doc,'메모 / 몰딩·걸레받이·설치 유의사항',262,32,140,8,size:11,bold:true)
        c.text(doc,memo.empty? ? '메모를 입력하세요.' : memo,262,43,140,48,size:11,bold:true)
        draw_iso(doc,c,data,262,105,140,152)
        draw_schedule(doc,data,options,title)
        if options.fetch('wall_views',true)
          data[:walls].each_with_index { |wall,i| draw_wall(doc,data,wall,i,options,title) }
        end
        doc.save(path)
        begin
          doc.export(path.sub(/\.layout\z/i,'.pdf'))
        rescue StandardError=>e
          raise "LayOut은 저장했습니다: #{path}\nPDF 출력 실패: #{e.message}"
        end
        path
      end

      def draw_iso(doc,c,data,x,y,w,h)
        # Diagrammatic open-room view with only furniture perimeter lines.
        raw=->(p){[p[0]-p[1]*0.6,-p[2]+p[1]*0.35]}
        polylines=[data[:floor],data[:floor].map { |p| [p[0],p[1],data[:height]] }]
        data[:items].each do |item|
          item[:plan].each do |loop|
            low=loop.map { |p| [*p,item[:lo][2]] }; high=loop.map { |p| [*p,item[:hi][2]] }
            polylines << low << high
            low.zip(high).each { |a,b| polylines << [a,b] }
          end
        end
        data[:floor].each { |p| polylines << [p,[p[0],p[1],data[:height]]] }
        points=polylines.flatten(1).map { |p| raw.call(p) }
        lo=[points.map(&:first).min,points.map(&:last).min]; hi=[points.map(&:first).max,points.map(&:last).max]
        scale=[(w-10)/(hi[0]-lo[0]),(h-10)/(hi[1]-lo[1])].min
        polylines.each do |loop|
          points=loop.map { |p| q=raw.call(p);[x+5+(q[0]-lo[0])*scale,y+5+(q[1]-lo[1])*scale] }
          c.poly(doc,points,weight:0.35)
        end
        c.text(doc,'입체 배치도 · 외곽 윤곽 / 축척 없음',x,y+h,140,7,size:9)
      end

      def point_segment_distance(p,a,b)
        v=sub(b,a); length2=v.sum { |x| x*x }
        return Math.hypot(*sub(p,a)) if length2<0.00001
        t=[[sub(p,a).zip(v).sum { |x,y| x*y }/length2.to_f,0].max,1].min
        Math.hypot(*sub(p,lerp(a,b,t)))
      end

      def plan_gap(first,second)
        return 0.0 if first.any? { |p| inside(p,second) } || second.any? { |p| inside(p,first) }
        a=first.each_with_index.map { |p,i| [p,first[(i+1)%first.length]] }
        b=second.each_with_index.map { |p,i| [p,second[(i+1)%second.length]] }
        a.each do |p,q|
          b.each do |r,s|
            v=sub(q,p); w=sub(s,r); det=cross(v,w)
            next if det.abs<0.000001
            t=cross(sub(r,p),w)/det.to_f; u=cross(sub(r,p),v)/det.to_f
            return 0.0 if t.between?(0,1) && u.between?(0,1)
          end
        end
        (a.flat_map { |p,q| second.map { |r| point_segment_distance(r,p,q) } } + b.flat_map { |p,q| first.map { |r| point_segment_distance(r,p,q) } }).min
      end

      def draw_schedule(doc,data,options,title)
        page=doc.pages.add('공간 치수표'); c=Canvas.new(doc,page)
        c.frame(doc,title+' / 치수표',options,'단위 mm · 치수는 모델 입력값 기준 · 가구 사이 거리는 외곽 간 최단거리(통로 유효폭과 다를 수 있음)')
        rows=[['부품','가로 / 벽방향 폭','깊이','높이','바닥 높이','기준 벽','벽 시작 거리','벽과 간격']]
        data[:items].each do |item|
          wall=data[:walls][item[:wall]]
          points=item[:faces].flatten(2)
          along=points.map { |p| sub(p,wall[:a]).zip(wall[:u]).sum { |a,b| a*b } }
          normal=points.map { |p| cross(wall[:u],sub(p,wall[:a])) }
          gap=normal.min<=0 && normal.max>=0 ? 0 : normal.map(&:abs).min
          width=item[:role]=='furniture' ? item[:hi][0]-item[:lo][0] : along.max-along.min
          depth=item[:role]=='furniture' ? item[:hi][1]-item[:lo][1] : normal.max-normal.min
          rows << [item[:label],width.round.to_s,depth.round.to_s,(item[:hi][2]-item[:lo][2]).round.to_s,item[:lo][2].round.to_s,wall[:name],along.min.round.to_s,gap.round.to_s]
        end
        rows.each_with_index do |row,i|
          y=36+i*7
          row.each_with_index { |value,j| c.text(doc,value,20+j*48,y+1,47,6,size:9,bold:i==0) }
          c.line(doc,18,y+7,402,y+7,weight:0.2)
        end
        y=46+rows.length*7
        furniture=data[:items].select { |item| item[:role]=='furniture' }
        furniture.each_with_index do |item,i|
          others=furniture.reject { |other| other.equal?(item) }
          next if others.empty?
          closest=others.map { |other| [other,item[:plan].product(other[:plan]).map { |a,b| plan_gap(a,b) }.min] }.min_by(&:last)
          c.text(doc,"#{item[:label]} ↔ #{closest[0][:label]} : #{closest[1].round}",20+(i%3)*125,y+(i/3)*7,123,6,size:9)
        end
      end

      def draw_wall(doc,data,wall,index,options,title)
        page=doc.pages.add(wall[:name])
        c=Canvas.new(doc,page)
        scale=1.0/[wall[:length]/325.0,data[:height]/155.0,1].max.ceil
        left=32; bottom=219; top=bottom-data[:height]*scale
        c.frame(doc,title+' / '+wall[:name],options,"벽면도 1:#{(1/scale).round} · 가까운 벽에 배정한 문·창문·가구 · 단위 mm")
        before=page.entities.to_a
        c.poly(doc,[[left,top],[left+wall[:length]*scale,top],[left+wall[:length]*scale,bottom],[left,bottom]],weight:0.7)
        project=->(p){v=sub(p,wall[:a]);[v.zip(wall[:u]).sum { |a,b| a*b },p[2]]}
        items=data[:items].select { |r| r[:wall]==index }
        items.each_with_index do |item,k|
          loops=outlines(item[:faces],project)
          loops.each { |loop| c.poly(doc,loop.map { |u,z| [left+u*scale,bottom-z*scale] },weight:0.5) }
          pts=loops.flatten(1); a=pts.map(&:first).min; b=pts.map(&:first).max
          z0=item[:lo][2]; z1=item[:hi][2]
          c.text(doc,item[:label],left+a*scale+2,bottom-z1*scale+2,35,7,size:10,bold:true)
          # Editable dimensions plus a readable measurement schedule below.
          c.horizontal_dimension(doc,left+a*scale,left+b*scale,bottom,228+(k%2)*7,b-a)
          distance=loops.flatten(1).map { |u,z| u }.min
          dims="#{item[:label]}  幅 #{(b-a).round} × 高 #{(z1-z0).round}  / 바닥 #{z0.round} / 벽 시작 #{distance.round}"
          c.text(doc,dims.gsub('幅','폭').gsub('高','높이'),32+(k%2)*185,250+(k/2)*6,182,6,size:9)
        end
        c.scaled(doc,before,scale)
        raise '한 벽의 부품은 8개 이하로 나눠 출력하세요.' if items.length>8
        c.horizontal_dimension(doc,left,left+wall[:length]*scale,top,top-12,wall[:length])
        c.vertical_dimension(doc,left+wall[:length]*scale,top,bottom,left+wall[:length]*scale+12,data[:height])
      end
    end
  end
end

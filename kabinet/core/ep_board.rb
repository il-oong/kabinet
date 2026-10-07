module Kabinet
  module EPBoard
    THICKNESSES = [3, 9, 12, 18, 20, 30].freeze
    module_function

    def dimensions(payload)
      values = %w[width thickness height].map do |key|
        begin
          value = Float(payload.fetch(key))
        rescue ArgumentError, TypeError, KeyError
          raise ArgumentError, '가로·깊이(두께)·높이에 숫자를 입력하세요.'
        end
        raise ArgumentError, '치수는 0보다 크고 10,000mm 이하여야 합니다.' unless value.finite? && value > 0 && value <= 10_000
        value
      end
      raise ArgumentError, '두께는 3·9·12·18·20·30T 중에서 선택하세요.' unless THICKNESSES.include?(values[1])
      values
    end

    def create(payload, model: Sketchup.active_model)
      w, t, h = dimensions(payload)
      model.start_operation('EP 한 장 생성', true)
      begin
        board = model.active_entities.add_group
        board.name = "EP #{w.round(2)} × #{t.to_i}T × #{h.round(2)}"
        face = board.entities.add_face([0, 0, 0], [w.mm, 0, 0], [w.mm, t.mm, 0], [0, t.mm, 0])
        face.reverse! if face.normal.z < 0
        face.pushpull(h.mm)
        board.set_attribute('kabinet_ep', 'dimensions_mm', [w, t, h])
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      model.selection.clear
      model.selection.add(board)
      board
    end
  end
end

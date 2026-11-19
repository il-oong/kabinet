# 제작도면 시트 — 선/색/글자 규칙 (tools/sheet/build_sheet.py 의 Ruby 이식)
# 순수 Ruby (SketchUp 불필요).
module Kabinet
  module Output
    module Sheet
      PW = 420.0
      PH = 297.0
      PT = 25.4 / 72.0

      # 스타일: 이름 => [DXF 레이어, 선굵기 pt, RGB]
      STY = {
        'OUT'   => ['OUTLINE',   0.72, [0, 0, 0]],
        'FR'    => ['FRAME',     0.36, [0, 0, 0]],
        'SEC'   => ['FRAME',     0.72, [0, 0, 0]],
        'FRTH'  => ['FRAME',     2.83, [0, 0, 0]],
        'DIM'   => ['DIM',       0.36, [185, 185, 185]],
        'DIMT'  => ['DIM',       0.36, [110, 110, 110]],
        'THIN'  => ['THIN',      0.12, [125, 125, 125]],
        'HATCH' => ['THIN',      0.12, [170, 170, 170]],
        'BLUE'  => ['NOTE_BLUE', 0.24, [0, 0, 255]],
        'RED'   => ['NOTE_RED',  0.36, [222, 0, 56]],
        'REDT'  => ['NOTE_RED',  0.72, [222, 0, 56]],
        'IMG'   => ['IMAGE_FRAME', 0.36, [0, 0, 0]]
      }.freeze

      # 글자 색: 이름 => [레이어, RGB]
      TXT = {
        'k' => ['TEXT', [0, 0, 0]], 'g' => ['TEXT', [110, 110, 110]], 'b' => ['NOTE_BLUE', [0, 0, 255]],
        'r' => ['NOTE_RED', [222, 0, 56]], 'w' => ['TEXT', [255, 255, 255]]
      }.freeze

      LAYER_ORDER = %w[OUTLINE DIM THIN NOTE_BLUE NOTE_RED FRAME TEXT IMAGE_FRAME IMAGE].freeze
      DXF_LW = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140, 158, 200, 211].freeze

      # 배경(white/dark/none)별 DXF 색: int = ACI 번호
      BG_RGB = { 'white' => [255, 255, 255], 'dark' => [33, 37, 43] }.freeze
      COLOR_MAP = {
        [0, 0, 0]       => [[0, 0, 0],       [255, 255, 255], 7],
        [255, 255, 255] => [[255, 255, 255], [255, 255, 255], [255, 255, 255]],
        [225, 225, 225] => [[225, 225, 225], [70, 74, 80],    [200, 200, 200]],
        [185, 185, 185] => [[150, 150, 150], [150, 150, 150], [150, 150, 150]],
        [110, 110, 110] => [[90, 90, 90],    [200, 200, 200], [150, 150, 150]],
        [125, 125, 125] => [[110, 110, 110], [190, 190, 190], [150, 150, 150]],
        [170, 170, 170] => [[165, 165, 165], [120, 120, 120], [130, 130, 130]],
        [85, 85, 85]    => [[85, 85, 85],    [140, 140, 140], [130, 130, 130]],
        [0, 0, 255]     => [[0, 0, 255],     [80, 160, 255],  [80, 160, 255]],
        [222, 0, 56]    => [[222, 0, 56],    1,               1]
      }.freeze

      # => Integer(ACI) 또는 [r,g,b]
      def self.dxf_color(rgb, bg)
        idx = { 'white' => 0, 'dark' => 1, 'none' => 2 }.fetch(bg, 0)
        (COLOR_MAP[rgb] || [rgb, rgb, rgb])[idx]
      end

      def self.lineweight(pt)
        DXF_LW.min_by { |q| (q - pt * PT * 100).abs }
      end

      # 글자 폭 추정(mm) — 폰트 메트릭 없이 한글 ≈ 0.95em / 숫자·대문자 0.6 / 그 외 0.5
      def self.text_width(str, size)
        w = 0.0
        str.to_s.each_char do |ch|
          o = ch.ord
          w += if o >= 0x2E80 then 0.95
               elsif ch == ' ' then 0.3
               elsif ch =~ /[A-Z0-9%@W*]/ then 0.62
               elsif ch =~ /[ilj.,:;'|!]/ then 0.3
               else 0.52
               end
        end
        w * size
      end

      def self.fmt(n)
        n.to_f.round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse.then { |s| n.to_f < 0 ? "-#{s.delete('-')}" : s }
      end
    end
  end
end

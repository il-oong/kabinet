require 'json'
require_relative 'support/geom'
module Kabinet; end
%w[constants persistence/attributes persistence/schema geometry/transforms geometry/builder
   geometry/joinery geometry/handle_builder core/fitting core/panel core/carcase
   core/door_panel core/ep_finish_panel core/accessory core/shelf_module core/drawer_module
   core/desk_module core/assembly geometry/preview_entities ui/live_preview].each do |file|
  require_relative "../kabinet/#{file}"
end

def assert(value, message); raise message unless value; end
def near(a, b); (a-b).abs < 0.00001; end
def build(spec)
  entities = Kabinet::Geometry::Preview::Entities.new
  norm = Kabinet::Persistence::Schema.normalize(spec)
  Kabinet::Persistence::Schema.validate!(norm)
  root = Kabinet::Core::Assembly.from_hash(norm).build(entities)
  batches = root.entities.collect
  bounds = Geom::BoundingBox.new
  batches.each { |b| bounds.add(b[:points]) }
  [root, batches, bounds]
end

spec = { 'width'=>900, 'max_depth'=>580, 'base_height'=>100,
  'ep'=>{'left'=>true, 'right'=>true}, 'top_panel'=>{'thickness'=>18},
  'modules'=>[{'kind'=>'shelf_module', 'width'=>860, 'depth'=>580, 'height'=>1982,
    'door_config'=>'pair', 'handle_type'=>'none', 'shelves'=>[],
    'accessories'=>[{'kind'=>'hanging_rod', 'height_from_bottom'=>1000, 'depth_inset'=>75, 'diameter'=>32}]}] }
before = Marshal.dump(spec)
root, batches, bounds = build(spec)
assert(Marshal.dump(spec) == before, 'Preview must not mutate input')
assert(near(bounds.width,900.mm) && near(bounds.depth,2100.mm), 'Overall W/H must match')
assert(near(bounds.height,602.mm), '20T door + 2mm gap must contribute to depth')
assert(batches.any? { |b| b[:front] } && batches.any? { |b| !b[:front] }, 'Front filtering')
assert(batches.any? { |b| b[:module_index] == 0 }, 'Module highlight identity')

%w[bar knob channel cup_pull none].each do |handle|
  spec['modules'][0]['handle_type'] = handle
  _, parts, = build(spec)
  assert(parts.count { |b| b[:front] } >= 2, "Door preview missing: #{handle}")
end

spec['run_mode'] = true
spec['run_height'] = 720
spec['modules'] = [400, 500].map { |w| { 'kind'=>'drawer_module', 'width'=>w, 'depth'=>580,
  'height'=>720, 'drawer_count'=>3, 'handle_type'=>'channel' } }
_, parts, bounds = build(spec)
assert(near(bounds.width,940.mm), 'Run includes both 20T EPs')
assert(parts.any? { |b| b[:module_index] == 1 }, 'Second module identity')
assert(parts.any? { |b| b[:front] }, 'Drawer fronts can be hidden')

# Host doubles deliberately have NO entities/start_operation/commit_operation API.
# Updating, viewing and canceling must work without those mutation methods.
module Sketchup
  class << self; attr_accessor :active_model; end
  class Group < Kabinet::Geometry::Preview::Group
    def valid?; true; end
    def locked?; false; end
    def attribute_dictionaries; {}; end
  end
  class Color; def initialize(*); end; end
  class Camera; def initialize(*); end; end
end
GL_LINES = 1
class TestView
  attr_accessor :camera, :drawing_color, :line_width, :line_stipple
  attr_reader :texts, :draws
  def initialize; @texts=[]; @draws=[]; end
  def zoom(*); end
  def invalidate; end
  def screen_coords(p); p; end
  def draw2d(_, pts); @draws << pts; end
  def draw_text(_, text); @texts << text; end
end
class TestModel
  attr_accessor :active_path
  attr_reader :active_view
  def initialize; @active_view = TestView.new; end
  def select_tool(tool)
    @tool.deactivate(@active_view) if @tool
    @tool=tool
    tool.activate if tool
  end
end
model = TestModel.new
Sketchup.active_model = model
stopped = 0
preview = Kabinet::UI::LivePreview.new(model) { stopped += 1 }
target = Sketchup::Group.new
target.transformation = Geom::Transformation.new(Geom::Point3d.new(100.mm,200.mm,0)) *
  Geom::Transformation.rotation(Geom::Point3d.new(0,0,0),Geom::Vector3d.new(0,0,1),90.degrees)
Kabinet::Persistence::Attributes.write_assembly_spec(target, spec)
original = Marshal.dump(target)
preview.update(spec, target: target)
preview.draw(model.active_view)
assert(Marshal.dump(target) == original, 'Original group must remain byte-for-byte unchanged')
assert(model.active_view.texts.first.include?('940.0'), 'Rotated preview keeps local width')
full_count = model.active_view.draws.size
preview.update(spec, target: target, internal: true, selected_module: 1)
model.active_view.draws.clear
preview.draw(model.active_view)
assert(model.active_view.draws.size < full_count, 'Internal view removes front geometry')
%w[front side top iso].each { |v| preview.set_view(v) }
preview.onCancel(0, model.active_view)
assert(stopped == 1, 'Cancel must stop exactly once')
preview.stop
assert(stopped == 1, 'Repeated stop must be safe')
model.active_path = [target]
begin
  preview.update(spec)
  raise 'Nested edit should be refused'
rescue RuntimeError => e
  raise unless e.message.include?('그룹 편집')
end
model.active_path = nil
require_relative '../kabinet/ui/dialog'
class TestDialog
  attr_reader :callbacks, :scripts
  def initialize; @callbacks = {}; @scripts = []; end
  def add_action_callback(name, &callback); @callbacks[name] = callback; end
  def execute_script(script); @scripts << script; end
  def visible?; true; end
end
dialog = TestDialog.new
controller = Kabinet::UI::Dialog
controller.instance_variable_set(:@dialog_model, model)
controller.register_callbacks(dialog)
dialog.callbacks['kabinet:preview'].call(nil, JSON.generate({spec: spec, revision: 1}))
assert(controller.instance_variable_get(:@preview), 'Preview callback must activate tool')
dialog.callbacks['kabinet:preview'].call(nil, JSON.generate({spec: spec.merge('width'=>-1), revision: 2}))
assert(controller.instance_variable_get(:@preview).nil?, 'Invalid spec must remove stale preview')
assert(dialog.scripts.last.include?('"ok":false'), 'Validation error must reach UI')
dialog.callbacks['kabinet:preview'].call(nil, JSON.generate({spec: spec, revision: 3}))
controller.stop_preview
assert(controller.instance_variable_get(:@preview).nil?, 'Apply/close cleanup')
Sketchup.active_model = TestModel.new
dialog.callbacks['kabinet:preview'].call(nil, JSON.generate({spec: spec, revision: 4}))
assert(dialog.scripts.last.include?('다른 SketchUp 모델'), 'Cross-model editing must be refused')
Sketchup.active_model = model
Dir[File.expand_path('../kabinet/**/*.rb', __dir__)].each { |f| RubyVM::InstructionSequence.compile_file(f) }
if ENV['KABINET_PRESETS_JSON']
  presets = JSON.parse(File.read(ENV['KABINET_PRESETS_JSON']))
  presets.each do |name, preset|
    _, parts, box = build(preset)
    assert(!parts.empty? && box.width > 0 && box.height > 0 && box.depth > 0, "Empty preset #{name}")
  end
  puts "PASS: #{presets.size} built-in presets through the real Assembly/Builder calculation path"
end
puts 'PASS: live preview geometry, inch conversion, roles, rotation, cancel, no model mutation, Ruby syntax'

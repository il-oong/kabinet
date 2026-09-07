const fs = require('fs');
const vm = require('vm');
const path = require('path');
const context = vm.createContext({ document: { addEventListener() {} } });
vm.runInContext(fs.readFileSync(path.join(__dirname, '../kabinet/ui/web/app.js'), 'utf8'), context);
fs.writeFileSync(process.argv[2], vm.runInContext('JSON.stringify(FURNITURE_PRESETS)', context));
